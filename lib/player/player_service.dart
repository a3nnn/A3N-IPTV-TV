import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

import '../config.dart';
import '../data/storage.dart';

/// One shared player for the whole app, so switching channels is instant
/// and only one connection to the server is used at a time.
///
/// Two engines, picked in Settings ("Video player"), read once at start:
///  * mpv (default): video decoded AND drawn by the TV's video chip, with
///    audio / subtitle choice.
///  * System player (Android ExoPlayer): for old TVs / Fire Sticks where mpv
///    can't use the video chip. No audio / subtitle choice.
///
/// The screens only use the methods below, never an engine directly
/// (except the audio / subtitle menu, which is mpv only).
class PlayerService {
  PlayerService._() {
    if (!isExo) _tune();
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

  /// The ExoPlayer of the stream on screen (null while none / opening).
  final ValueNotifier<VideoPlayerController?> _exoNow = ValueNotifier<VideoPlayerController?>(null);
  VideoPlayerController? _exo;

  /// Why the system player couldn't play (shown on the picture), null = fine.
  final ValueNotifier<String?> _exoError = ValueNotifier<String?>(null);

  final StreamController<Duration> _posCtl = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durCtl = StreamController<Duration>.broadcast();
  final StreamController<bool> _playCtl = StreamController<bool>.broadcast();
  final StreamController<bool> _bufCtl = StreamController<bool>.broadcast();
  final StreamController<(int, int)> _sizeCtl = StreamController<(int, int)>.broadcast();

  Duration _xPos = Duration.zero, _xDur = Duration.zero;
  bool _xPlaying = false, _xBuffering = false;
  (int, int) _xSize = (0, 0);

  void _exoTick() {
    final c = _exo;
    if (c == null) return;
    final v = c.value;
    if (v.position != _xPos) _posCtl.add(_xPos = v.position);
    if (v.duration != _xDur) _durCtl.add(_xDur = v.duration);
    if (v.isPlaying != _xPlaying) _playCtl.add(_xPlaying = v.isPlaying);
    final buf = v.isBuffering || (!v.isInitialized && !v.hasError);
    if (buf != _xBuffering) _bufCtl.add(_xBuffering = buf);
    if (v.hasError && _exoError.value == null) {
      _exoError.value = v.errorDescription ?? 'unknown error';
    }
    final size = (v.size.width.round(), v.size.height.round());
    if (size != _xSize) _sizeCtl.add(_xSize = size);
  }

  void _exoReset() {
    _posCtl.add(_xPos = Duration.zero);
    _durCtl.add(_xDur = Duration.zero);
    _playCtl.add(_xPlaying = false);
    _sizeCtl.add(_xSize = (0, 0));
  }

  Future<void> _exoClose() async {
    final old = _exo;
    _exo = null;
    _exoNow.value = null;
    _exoError.value = null;
    if (old != null) {
      old.removeListener(_exoTick);
      try {
        await old.dispose();
      } catch (_) {}
    }
  }

  Future<void> _exoOpen(String url) async {
    await _exoClose();
    _exoReset();
    _bufCtl.add(_xBuffering = true);
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: const {'User-Agent': AppConfig.userAgent},
      // A real Android video surface (straight from the TV's video chip to
      // the screen) instead of a Flutter texture, which shows only black on
      // some TVs.
      viewType: VideoViewType.platformView,
    );
    _exo = c;
    c.addListener(_exoTick);
    try {
      await c.initialize().timeout(const Duration(seconds: 25));
      if (_exo != c) return; // another stream was opened meanwhile
      _exoNow.value = c;
      await c.play();
    } on TimeoutException {
      if (_exo == c) {
        _bufCtl.add(_xBuffering = false);
        _exoError.value = 'Timed out opening the stream';
      }
    } catch (e) {
      if (_exo == c) {
        _bufCtl.add(_xBuffering = false);
        _exoError.value = e.toString();
      }
    }
  }

  // ------------------------------------------------------------ one API for the screens

  Future<void> play(String url) async {
    if (_currentUrl == url) return;
    _currentUrl = url;
    openedAt = DateTime.now();
    opened.value++;
    if (isExo) {
      await _exoOpen(url);
    } else {
      await player.open(Media(url, httpHeaders: const {'User-Agent': AppConfig.userAgent}));
    }
  }

  Future<void> stop() async {
    _currentUrl = null;
    if (isExo) {
      await _exoClose();
      _exoReset();
      _bufCtl.add(_xBuffering = false);
    } else {
      await player.stop();
    }
  }

  Stream<Duration> get positionStream => isExo ? _posCtl.stream : player.stream.position;
  Duration get position => isExo ? _xPos : player.state.position;

  Stream<Duration> get durationStream => isExo ? _durCtl.stream : player.stream.duration;
  Duration get duration => isExo ? _xDur : player.state.duration;

  Stream<bool> get playingStream => isExo ? _playCtl.stream : player.stream.playing;
  bool get playing => isExo ? _xPlaying : player.state.playing;

  Stream<bool> get bufferingStream => isExo ? _bufCtl.stream : player.stream.buffering;
  bool get buffering => isExo ? _xBuffering : player.state.buffering;

  /// Width / height of the picture, (0, 0) while unknown.
  Stream<(int, int)> get videoSizeStream =>
      isExo ? _sizeCtl.stream : player.stream.videoParams.map((v) => (v.w ?? 0, v.h ?? 0));
  (int, int) get videoSize {
    if (isExo) return _xSize;
    final v = player.state.videoParams;
    return (v.w ?? 0, v.h ?? 0);
  }

  Future<void> seek(Duration to) async {
    if (isExo) {
      await _exo?.seekTo(to);
    } else {
      await player.seek(to);
    }
  }

  Future<void> resume() async {
    if (isExo) {
      await _exo?.play();
    } else {
      await player.play();
    }
  }

  Future<void> pause() async {
    if (isExo) {
      await _exo?.pause();
    } else {
      await player.pause();
    }
  }

  Future<void> playOrPause() async {
    if (isExo) {
      final c = _exo;
      if (c == null) return;
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        await c.play();
      }
    } else {
      await player.playOrPause();
    }
  }

  /// The picture. [subtitles] is used by mpv only.
  Widget view({Key? key, SubtitleViewConfiguration? subtitles}) {
    if (!isExo) {
      return Video(
        key: key,
        controller: controller,
        controls: NoVideoControls,
        fill: Colors.black,
        subtitleViewConfiguration: subtitles ?? const SubtitleViewConfiguration(),
      );
    }
    return ValueListenableBuilder<VideoPlayerController?>(
      key: key,
      valueListenable: _exoNow,
      builder: (context, c, _) => ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, v, _) => Center(
                  child: AspectRatio(
                    aspectRatio: v.isInitialized && v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
                    child: VideoPlayer(c),
                  ),
                ),
              ),
            ValueListenableBuilder<String?>(
              valueListenable: _exoError,
              builder: (context, err, _) => err == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Weak-device player error:\n$err',
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
