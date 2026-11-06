import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:a3n_exo/a3n_exo.dart';

import '../config.dart';
import '../data/storage.dart';
import '../widgets/sub_style.dart';

/// One shared player for the whole app, so switching channels is instant
/// and only one connection to the server is used at a time.
///
/// Two engines, picked in Settings ("Video player"), read once at start:
///  * ExoPlayer (default, package a3n_exo): Android's own player on a real
///    video surface, with audio / subtitle choice, frame rate, HDR info. A
///    stream it can't decode is played by mpv instead, by itself.
///  * mpv (the other choice): kept for the rare stream / TV it suits better.
///
/// The screens only use the methods below, never an engine directly.
class PlayerService {
  PlayerService._() {
    if (!isExo) _tune();
    if (isExo) SubStyle.changed.addListener(() => unawaited(_exoSubStyle()));
  }
  static final PlayerService instance = PlayerService._();

  /// true = Android system player (ExoPlayer).
  final bool isExo = Storage.playerEngine == 'exo';

  // ------------------------------------------------------------ shared state

  /// True while live TV is shown full screen (hides the menu).
  final ValueNotifier<bool> fullscreen = ValueNotifier<bool>(false);

  /// Bumped to ask the live screen to leave full screen (Android BACK fallback).
  final ValueNotifier<int> exitFullscreen = ValueNotifier<int>(0);

  /// Bumped every time a new stream is opened (shows the quality badge).
  final ValueNotifier<int> opened = ValueNotifier<int>(0);
  DateTime openedAt = DateTime(2000);

  String? _currentUrl;
  String? get currentUrl => _currentUrl;

  // ------------------------------------------------------------ mpv

  late final Player player = Player(
    configuration: PlayerConfiguration(
      title: AppConfig.appName,
      // Demuxer cache. 16 MB is ~15 s of a 1080p live stream (8 MB in light mode).
      bufferSize: (Storage.liteMode ? 8 : 16) * 1024 * 1024,
    ),
  );

  /// Decoded and drawn by the TV's video chip (lightest). The old
  /// "Compatible video mode" was removed in 1.5.4 (a TV showing a black
  /// picture uses the weak-device player instead).
  late final VideoController controller = VideoController(
    player,
    configuration: const VideoControllerConfiguration(
      vo: 'mediacodec_embed',
      hwdec: 'mediacodec',
      enableHardwareAcceleration: true,
    ),
  );

  Future<void> _tune() async {
    // Extra mpv limits (ignored safely if a property is unknown).
    final props = <String, String>{
      'demuxer-max-back-bytes': '2097152', // no big rewind buffer for live TV
      'demuxer-readahead-secs': '10',
      'cache-pause-initial': 'no',
      'vd-lavc-threads': '2', // only used if software decoding kicks in
      'framedrop': 'vo',
      'video-sync': 'audio',
      'network-timeout': '20',
      // Jump to the nearest keyframe when seeking: much lighter for the TV's
      // video chip than an exact seek (exact seeks could crash some TVs).
      'hr-seek': 'no',
      // Light mode: less read-ahead (memory) and cheaper software decoding.
      if (Storage.liteMode) ...{
        'demuxer-readahead-secs': '5',
        'vd-lavc-skiploopfilter': 'all',
        'vd-lavc-fast': 'yes',
      },
    };
    for (final e in props.entries) {
      try {
        await (player.platform as dynamic).setProperty(e.key, e.value);
      } catch (_) {}
    }
  }

  /// Reads an mpv property, '' if it isn't available (always '' on ExoPlayer).
  Future<String> property(String name) async {
    if (isExo) return '';
    try {
      final v = await (player.platform as dynamic).getProperty(name);
      return v?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ ExoPlayer

  // State of the ExoPlayer stream on screen (from the native events).
  final StreamController<Duration> _posCtl = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durCtl = StreamController<Duration>.broadcast();
  final StreamController<bool> _playCtl = StreamController<bool>.broadcast();
  final StreamController<bool> _bufCtl = StreamController<bool>.broadcast();
  final StreamController<(int, int)> _sizeCtl = StreamController<(int, int)>.broadcast();

  Duration _xPos = Duration.zero, _xDur = Duration.zero;
  bool _xPlaying = false, _xBuffering = false;
  (int, int) _xSize = (0, 0);
  double _xFps = 0;
  String _xCodec = '', _xHdr = '';

  /// Why ExoPlayer couldn't play (shown on the picture), null = fine.
  final ValueNotifier<String?> _exoError = ValueNotifier<String?>(null);

  /// This stream is played by mpv instead (ExoPlayer couldn't decode it).
  final ValueNotifier<bool> _fallback = ValueNotifier<bool>(false);

  /// Bumped when the audio / subtitle tracks of the stream change.
  final ValueNotifier<int> tracksChanged = ValueNotifier<int>(0);

  StreamSubscription<Map<dynamic, dynamic>>? _exoEvents;

  void _exoListen() {
    _exoEvents ??= A3nExo.events.listen((m) {
      switch (m['event']) {
        case 'tracks':
          tracksChanged.value++;
        case 'error':
          _exoError.value = '${m['message'] ?? m['code'] ?? 'error'}';
          if (m['decoder'] == true && _currentUrl != null && !_fallback.value) {
            unawaited(_toMpv(_currentUrl!));
          }
        case 'state':
          if (_fallback.value) return;
          final pos = Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0);
          final dur = Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0);
          final playing = m['playing'] == true;
          final buf = m['buffering'] == true;
          final size = ((m['width'] as num?)?.toInt() ?? 0, (m['height'] as num?)?.toInt() ?? 0);
          _xFps = (m['fps'] as num?)?.toDouble() ?? 0;
          _xCodec = '${m['codec'] ?? ''}';
          _xHdr = '${m['hdr'] ?? ''}';
          if (pos != _xPos) _posCtl.add(_xPos = pos);
          if (dur != _xDur) _durCtl.add(_xDur = dur);
          if (playing != _xPlaying) _playCtl.add(_xPlaying = playing);
          if (buf != _xBuffering) _bufCtl.add(_xBuffering = buf);
          if (size != _xSize) _sizeCtl.add(_xSize = size);
      }
    });
  }

  void _exoReset() {
    _exoError.value = null;
    _xFps = 0;
    _xCodec = '';
    _xHdr = '';
    _posCtl.add(_xPos = Duration.zero);
    _durCtl.add(_xDur = Duration.zero);
    _playCtl.add(_xPlaying = false);
    _sizeCtl.add(_xSize = (0, 0));
  }

  /// Subtitle language from Settings, given to ExoPlayer before each stream
  /// (it then picks the track by itself), and the subtitle look.
  Future<void> _exoPrefs() async {
    final pref = Storage.subtitleLang;
    await A3nExo.setLanguages(
      text: switch (pref) { 'en' => ['en'], 'ar_en' => ['ar', 'en'], _ => ['ar'] },
      textOff: pref == 'off',
    );
    await _exoSubStyle();
  }

  Future<void> _exoSubStyle() async {
    try {
      await A3nExo.subtitleStyle(
        color: (SubStyle.colors[Storage.subColor] ?? Colors.white).toARGB32(),
        scale: switch (Storage.subSize) { 's' => 0.8, 'l' => 1.3, _ => 1.0 },
        background: Storage.subBackground,
        opacity: Storage.subBgOpacity,
      );
    } catch (_) {}
  }

  /// ExoPlayer can't decode this stream: play it with mpv instead.
  Future<void> _toMpv(String url) async {
    _fallback.value = true;
    _exoError.value = null;
    try {
      await A3nExo.stop();
    } catch (_) {}
    _tune();
    await player.open(Media(url, httpHeaders: const {'User-Agent': AppConfig.userAgent}));
  }

  bool get _mpvNow => !isExo || _fallback.value;

  // ------------------------------------------------------------ one API for the screens

  Future<void> play(String url) async {
    if (_currentUrl == url) return;
    _currentUrl = url;
    openedAt = DateTime.now();
    opened.value++;
    if (isExo) {
      if (_fallback.value) {
        _fallback.value = false;
        try {
          await player.stop();
        } catch (_) {}
      }
      _exoListen();
      _exoReset();
      _bufCtl.add(_xBuffering = true);
      await _exoPrefs();
      await A3nExo.open(url, userAgent: AppConfig.userAgent);
    } else {
      await player.open(Media(url, httpHeaders: const {'User-Agent': AppConfig.userAgent}));
    }
  }

  Future<void> stop() async {
    _currentUrl = null;
    if (isExo) {
      if (_fallback.value) {
        try {
          await player.stop();
        } catch (_) {}
        _fallback.value = false;
      }
      try {
        await A3nExo.stop();
      } catch (_) {}
      _exoReset();
      _bufCtl.add(_xBuffering = false);
    } else {
      await player.stop();
    }
  }

  Stream<Duration> get positionStream => _mpvNow ? player.stream.position : _posCtl.stream;
  Duration get position => _mpvNow ? player.state.position : _xPos;

  Stream<Duration> get durationStream => _mpvNow ? player.stream.duration : _durCtl.stream;
  Duration get duration => _mpvNow ? player.state.duration : _xDur;

  Stream<bool> get playingStream => _mpvNow ? player.stream.playing : _playCtl.stream;
  bool get playing => _mpvNow ? player.state.playing : _xPlaying;

  Stream<bool> get bufferingStream => _mpvNow ? player.stream.buffering : _bufCtl.stream;
  bool get buffering => _mpvNow ? player.state.buffering : _xBuffering;

  /// Width / height of the picture, (0, 0) while unknown.
  Stream<(int, int)> get videoSizeStream =>
      _mpvNow ? player.stream.videoParams.map((v) => (v.w ?? 0, v.h ?? 0)) : _sizeCtl.stream;
  (int, int) get videoSize {
    if (!_mpvNow) return _xSize;
    final v = player.state.videoParams;
    return (v.w ?? 0, v.h ?? 0);
  }

  /// Frames per second of the video (0 = unknown yet).
  Future<double> frameRate() async {
    if (!_mpvNow) return _xFps;
    var fps = double.tryParse(await property('container-fps')) ?? 0;
    if (fps <= 0) fps = double.tryParse(await property('estimated-vf-fps')) ?? 0;
    return fps;
  }

  /// "HEVC · HLG" for the info badge ('' = nothing to add).
  String get videoExtra {
    if (_mpvNow) return '';
    final c = _xCodec.toLowerCase();
    final codec = c.contains('hevc') || c.contains('h265')
        ? 'HEVC'
        : c.contains('avc') || c.contains('h264')
            ? 'H.264'
            : c.contains('av01')
                ? 'AV1'
                : c.contains('vp9')
                    ? 'VP9'
                    : '';
    return [codec, _xHdr].where((x) => x.isNotEmpty).join('  ·  ');
  }

  Future<void> seek(Duration to) async {
    if (_mpvNow) {
      await player.seek(to);
    } else {
      await A3nExo.seek(to);
    }
  }

  Future<void> resume() async {
    if (_mpvNow) {
      await player.play();
    } else {
      await A3nExo.play();
    }
  }

  Future<void> pause() async {
    if (_mpvNow) {
      await player.pause();
    } else {
      await A3nExo.pause();
    }
  }

  Future<void> playOrPause() async {
    if (_mpvNow) {
      await player.playOrPause();
    } else if (_xPlaying) {
      await A3nExo.pause();
    } else {
      await A3nExo.play();
    }
  }

  // ------------------------------------------------ audio / subtitle tracks

  /// (audio, subtitles) of the stream on screen.
  Future<(List<PlayerTrack>, List<PlayerTrack>)> tracks() async {
    if (_mpvNow) {
      final t = player.state.tracks;
      final cur = player.state.track;
      final noSub = cur.subtitle.id == 'no';
      return (
        [
          for (final a in t.audio.where((x) => x.id != 'auto' && x.id != 'no'))
            PlayerTrack(a.id, a.title ?? '', a.language ?? '', cur.audio.id == a.id),
        ],
        [
          for (final x in t.subtitle.where((x) => x.id != 'auto' && x.id != 'no'))
            PlayerTrack(x.id, x.title ?? '', x.language ?? '', !noSub && cur.subtitle.id == x.id),
        ],
      );
    }
    try {
      final (a, t) = await A3nExo.tracks();
      return (
        [for (final x in a) if (x.supported) PlayerTrack(x.id, x.label, x.language, x.selected)],
        [for (final x in t) if (x.supported) PlayerTrack(x.id, x.label, x.language, x.selected)],
      );
    } catch (_) {
      return (<PlayerTrack>[], <PlayerTrack>[]);
    }
  }

  Future<void> selectAudio(String id) async {
    if (_mpvNow) {
      final a = player.state.tracks.audio.where((x) => x.id == id);
      if (a.isNotEmpty) await player.setAudioTrack(a.first);
    } else {
      await A3nExo.selectAudio(id);
    }
  }

  /// [id] null = subtitles off.
  Future<void> selectSubtitle(String? id) async {
    if (_mpvNow) {
      if (id == null) {
        await player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        final s = player.state.tracks.subtitle.where((x) => x.id == id);
        if (s.isNotEmpty) await player.setSubtitleTrack(s.first);
      }
    } else {
      await A3nExo.selectText(id);
    }
  }

  /// The subtitle look changed in Settings / the tracks menu.
  Future<void> subtitleStyleChanged() async {
    if (isExo) await _exoSubStyle();
  }

  /// The picture. [subtitles] is used by mpv only (ExoPlayer draws its own).
  Widget view({Key? key, SubtitleViewConfiguration? subtitles}) {
    Widget mpv() => Video(
          key: key,
          controller: controller,
          controls: NoVideoControls,
          fill: Colors.black,
          subtitleViewConfiguration: subtitles ?? const SubtitleViewConfiguration(),
        );
    if (!isExo) return mpv();
    return ValueListenableBuilder<bool>(
      key: key,
      valueListenable: _fallback,
      builder: (context, fb, _) => fb
          ? mpv()
          : ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const A3nExoView(),
                  ValueListenableBuilder<String?>(
                    valueListenable: _exoError,
                    builder: (context, err, _) => err == null
                        ? const SizedBox.shrink()
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Player error:\n$err',
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// One audio / subtitle track (either player).
class PlayerTrack {
  final String id;
  final String title;
  final String language;
  final bool selected;
  const PlayerTrack(this.id, this.title, this.language, this.selected);
}
