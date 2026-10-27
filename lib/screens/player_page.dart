import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../data/storage.dart';
import '../data/watch_history.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/common.dart';
import '../widgets/stream_info.dart';
import '../widgets/sub_style.dart';
import '../l10n.dart';

/// The episode after the one playing ("Next episode" button).
class NextEpisode {
  final String label;
  final void Function(BuildContext context) open;
  const NextEpisode({required this.label, required this.open});
}

/// Full-screen player for movies and episodes, driven by the TV remote:
/// OK = play / pause, ◀ ▶ = seek 10 s (hold to go faster), BACK = close.
class PlayerPage extends StatefulWidget {
  final String url;
  final String title;

  /// Movie / episode being watched (to remember where it stopped).
  final WatchEntry? watch;

  /// Jump here once the video is ready ("continue watching").
  final Duration startAt;

  /// Series only: the following episode.
  final NextEpisode? next;
  const PlayerPage({
    super.key,
    required this.url,
    required this.title,
    this.watch,
    this.startAt = Duration.zero,
    this.next,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PlayerService _svc = PlayerService.instance;
  final FocusNode _focus = FocusNode();
  Timer? _hideTimer;
  bool _overlay = true;
  int _repeat = 0;

  // Seeking: while ◀ ▶ are pressed only the bar moves; the player jumps ONCE
  // shortly after the button is let go (many seeks in a row crashed some TVs).
  Duration? _seekTarget;
  Timer? _seekTimer;

  // Continue watching / saving the position.
  StreamSubscription<Duration>? _durSub;
  Timer? _saveTimer;
  bool _started = false; // the jump to [startAt] was done (or not needed)

  // Preferred subtitles (Settings), picked once when the file's tracks are known.
  StreamSubscription<Tracks>? _tracksSub;
  bool _subsPicked = false;

  void _pickSubtitles(Tracks tracks) {
    if (_subsPicked) return;
    final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no');
    final video = tracks.video.where((t) => t.id != 'auto' && t.id != 'no');
    if (audio.isEmpty && video.isEmpty) return; // file not opened yet
    _subsPicked = true;
    _tracksSub?.cancel();
    final pref = Storage.subtitleLang;
    final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    if (pref == 'off') {
      _svc.player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }
    bool isLang(SubtitleTrack t, List<String> codes, List<String> words) {
      final l = (t.language ?? '').toLowerCase().trim();
      final title = (t.title ?? '').toLowerCase();
      return codes.contains(l) || words.any((w) => title.contains(w) || l.contains(w));
    }
    bool ar(SubtitleTrack t) => isLang(t, const ['ar', 'ara', 'arb'], const ['arab', 'عرب']);
    bool en(SubtitleTrack t) => isLang(t, const ['en', 'eng'], const ['english']);
    SubtitleTrack? pick;
    for (final test in pref == 'en' ? [en] : (pref == 'ar_en' ? [ar, en] : [ar])) {
      for (final t in subs) {
        if (test(t)) {
          pick = t;
          break;
        }
      }
      if (pick != null) break;
    }
    if (pick != null) _svc.player.setSubtitleTrack(pick);
  }

  @override
  void initState() {
    super.initState();
    _started = widget.startAt <= Duration.zero;
    _svc.play(widget.url);
    _tracksSub = _svc.player.stream.tracks.listen(_pickSubtitles);
    if (!_started) {
      _seekTarget = widget.startAt; // the bar shows the target right away
      _durSub = _svc.player.stream.duration.listen((d) {
        if (d > Duration.zero) _jumpToStart();
      });
    }
    if (widget.watch != null) {
      _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _savePosition());
    }
    _poke();
  }

  Future<void> _jumpToStart() async {
    if (_started) return;
    _started = true;
    _durSub?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    try {
      await _svc.player.seek(widget.startAt);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted && _seekTimer?.isActive != true) setState(() => _seekTarget = null);
  }

  void _savePosition() {
    final w = widget.watch;
    if (w == null || !_started) return;
    final st = _svc.player.state;
    final pos = (_seekTarget ?? st.position).inSeconds;
    final dur = st.duration.inSeconds;
    if (dur <= 0) return;
    WatchHistory.report(w, pos, dur);
  }

  // ▼ moves the remote onto the buttons under the picture
  // (audio & subtitles, next episode); ▲ or BACK goes back to the video.
  bool _inButtons = false;
  final FocusNode _tracksBtn = FocusNode();

  void _enterButtons() {
    _hideTimer?.cancel();
    setState(() {
      _overlay = true;
      _inButtons = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tracksBtn.requestFocus();
    });
  }

  void _leaveButtons() {
    setState(() => _inButtons = false);
    _focus.requestFocus();
    _poke();
  }

  /// Set when leaving for the next episode (its position is already saved).
  bool _left = false;

  void _goNext() {
    final n = widget.next;
    if (n == null || _left) return;
    _savePosition();
    WatchHistory.saveNow();
    _left = true;
    n.open(context);
  }

  @override
  void dispose() {
    _tracksBtn.dispose();
    if (!_left) {
      _savePosition();
      WatchHistory.saveNow();
    }
    _hideTimer?.cancel();
    _seekTimer?.cancel();
    _saveTimer?.cancel();
    _durSub?.cancel();
    _tracksSub?.cancel();
    _focus.dispose();
    // Don't stop the next episode that is already starting.
    if (_svc.currentUrl == widget.url) _svc.stop();
    super.dispose();
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!_overlay) setState(() => _overlay = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_inButtons) setState(() => _overlay = false);
    });
  }

  void _seek(int direction, {bool repeat = false}) {
    final p = _svc.player;
    final dur = p.state.duration;
    if (dur <= Duration.zero) return; // not loaded yet
    _repeat = repeat ? _repeat + 1 : 0;
    // Holding the button speeds up: 10 s, then 30 s, then 60 s steps.
    final step = _repeat > 12 ? 60 : (_repeat > 4 ? 30 : 10);
    var target = (_seekTarget ?? p.state.position) + Duration(seconds: step * direction);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur - const Duration(seconds: 2)) target = dur - const Duration(seconds: 2);
    if (target < Duration.zero) target = Duration.zero;
    setState(() => _seekTarget = target);
    _poke();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 600), _commitSeek);
  }

  Future<void> _commitSeek() async {
    final t = _seekTarget;
    if (t == null || !mounted) return;
    try {
      await _svc.player.seek(t);
    } catch (_) {}
    // Keep showing the target until the player reports the new position.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted && _seekTimer?.isActive != true) setState(() => _seekTarget = null);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (_inButtons) {
      // On the buttons: OK / ◀ ▶ work as usual; ▲ or BACK return to the video.
      if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
        if (e is KeyUpEvent) _leaveButtons();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        if (e is KeyDownEvent) _leaveButtons();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      if (e is KeyUpEvent) Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final repeat = e is KeyRepeatEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seek(-1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seek(1, repeat: repeat);
      return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _svc.player.playOrPause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlay) {
      _svc.player.play();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPause) {
      _svc.player.pause();
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _enterButtons();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.contextMenu || k == LogicalKeyboardKey.info) {
      _openTracks();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _poke();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// ▼ on the remote: pick the audio language and the subtitles of the file.
  Future<void> _openTracks() async {
    _hideTimer?.cancel();
    await showDialog<void>(context: context, builder: (_) => _TracksDialog(player: _svc.player));
    if (!mounted) return;
    if (_inButtons) {
      _tracksBtn.requestFocus();
    } else {
      _focus.requestFocus();
      _poke();
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = _svc.player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTap: () {
            p.playOrPause();
            _poke();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Redrawn when the subtitle look is changed in the ▼ menu.
              ValueListenableBuilder<int>(
                valueListenable: SubStyle.changed,
                builder: (context, _, __) => Video(
                  controller: _svc.controller,
                  controls: NoVideoControls,
                  fill: Colors.black,
                  subtitleViewConfiguration: SubtitleViewConfiguration(
                    style: SubStyle.textStyle(),
                    padding: const EdgeInsets.fromLTRB(60, 0, 60, 70),
                  ),
                ),
              ),
              StreamBuilder<bool>(
                stream: p.stream.buffering,
                initialData: p.state.buffering,
                builder: (context, snap) => snap.data == true
                    ? const IgnorePointer(child: Center(child: CircularProgressIndicator()))
                    : const SizedBox.shrink(),
              ),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _overlay ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(28, 22, 28, 40),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [fade(Colors.black, 0.75), Colors.transparent],
                            ),
                          ),
                          child: Row(
                            // Quality badge stays top-left in both languages.
                            textDirection: TextDirection.ltr,
                            children: [
                              StreamInfoBadge(show: _overlay),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                tr('OK  play/pause     ◀ ▶  seek     ▼  buttons     BACK  exit', 'OK  تشغيل/إيقاف     ◀ ▶  ترجيع/تقديم     ▼  الأزرار     رجوع  خروج'),
                                style: TextStyle(fontSize: 12, color: fade(Colors.white, 0.6)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(32, 50, 32, 28),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [fade(Colors.black, 0.85), Colors.transparent],
                            ),
                          ),
                          // Time bar always runs left → right, like the ◀ ▶ buttons.
                          child: Directionality(
                            textDirection: TextDirection.ltr,
                            // One line: ▶  [CC]  time ━━━━ duration  [Next episode]
                            child: Row(
                            children: [
                            StreamBuilder<bool>(
                              stream: p.stream.playing,
                              initialData: p.state.playing,
                              builder: (context, s) => Icon(
                                s.data == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _RoundIconButton(
                              focusNode: _tracksBtn,
                              icon: Icons.subtitles_rounded,
                              tooltip: tr('Audio & subtitles', 'الصوت والترجمة'),
                              onPressed: _openTracks,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                            child: StreamBuilder<Duration>(
                            stream: p.stream.position,
                            initialData: p.state.position,
                            builder: (context, _) {
                              final pos = _seekTarget ?? p.state.position;
                              final dur = p.state.duration;
                              final v = dur.inMilliseconds > 0
                                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0;
                              return Row(
                                children: [
                                  Text(_fmt(pos), style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: v,
                                        minHeight: 5,
                                        color: AppConfig.primary,
                                        backgroundColor: fade(Colors.white, 0.2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(_fmt(dur), style: const TextStyle(color: Colors.white, fontSize: 14)),
                                ],
                              );
                            },
                          ),
                            ),
                            if (widget.next != null) ...[
                              const SizedBox(width: 16),
                              _PlayerButton(
                                icon: Icons.skip_next_rounded,
                                label: '${tr('Next episode', 'الحلقة التالية')}  ${widget.next!.label}',
                                onPressed: _goNext,
                              ),
                            ],
                            ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// Button under the picture, reached with ▼ on the remote.
class _PlayerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _PlayerButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: fade(Colors.black, 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
}

/// Small round icon button (subtitles) next to the play icon.
/// A white ring shows when the remote is on it.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  const _RoundIconButton({required this.icon, required this.tooltip, required this.onPressed, this.focusNode});

  @override
  Widget build(BuildContext context) => Semantics(
        label: tooltip,
        button: true,
        child: IconButton(
          focusNode: focusNode,
          onPressed: onPressed,
          icon: Icon(icon, size: 24),
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(Size(46, 46)),
            shape: const WidgetStatePropertyAll(CircleBorder()),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.focused) ? fade(Colors.white, 0.25) : fade(Colors.black, 0.45)),
            side: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.focused)
                ? const BorderSide(color: Colors.white, width: 2.5)
                : BorderSide.none),
          ),
        ),
      );
}

// ------------------------------------------------------------ tracks menu

String _trackLabel(String id, String? title, String? language, int index) {
  final lang = (language ?? '').trim();
  final name = (title ?? '').trim();
  final parts = <String>[
    if (lang.isNotEmpty) lang.toUpperCase(),
    if (name.isNotEmpty && name.toLowerCase() != lang.toLowerCase()) name,
  ];
  return parts.isEmpty ? tr('Track ${index + 1}', 'مسار ${index + 1}') : parts.join('  ·  ');
}

class _TracksDialog extends StatefulWidget {
  final Player player;
  const _TracksDialog({required this.player});

  @override
  State<_TracksDialog> createState() => _TracksDialogState();
}

class _TracksDialogState extends State<_TracksDialog> {
  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final tracks = p.state.tracks;
    final current = p.state.track;
    final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();

    Widget option({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      bool autofocus = false,
    }) {
      return FocusRing(
        radius: 8,
        child: ListTile(
        dense: true,
        autofocus: autofocus,
        selected: selected,
        selectedColor: AppConfig.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onTap,
      ),
      );
    }

    Widget column(String title, IconData icon, List<Widget> children) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: AppConfig.textSecondary),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontSize: 12, letterSpacing: L.spacing(1.3), color: AppConfig.textSecondary, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Flexible(child: ListView(shrinkWrap: true, children: children)),
            ],
          ),
        );

    final audioList = <Widget>[
      if (audio.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('Only one audio track', 'يوجد مسار صوت واحد فقط'), style: const TextStyle(color: AppConfig.textSecondary)),
        ),
      for (var i = 0; i < audio.length; i++)
        option(
          label: _trackLabel(audio[i].id, audio[i].title, audio[i].language, i),
          selected: current.audio.id == audio[i].id,
          autofocus: current.audio.id == audio[i].id || (i == 0 && !audio.any((a) => a.id == current.audio.id)),
          onTap: () {
            p.setAudioTrack(audio[i]);
            Navigator.of(context).pop();
          },
        ),
    ];

    final subList = <Widget>[
      option(
        label: tr('Off', 'بدون ترجمة'),
        selected: current.subtitle.id == 'no' || !subs.any((s) => s.id == current.subtitle.id),
        autofocus: audio.isEmpty,
        onTap: () {
          p.setSubtitleTrack(SubtitleTrack.no());
          Navigator.of(context).pop();
        },
      ),
      for (var i = 0; i < subs.length; i++)
        option(
          label: _trackLabel(subs[i].id, subs[i].title, subs[i].language, i),
          selected: current.subtitle.id == subs[i].id,
          onTap: () {
            p.setSubtitleTrack(subs[i]);
            Navigator.of(context).pop();
          },
        ),
      if (subs.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('No subtitles in this file', 'ما فيه ترجمة في هذا الملف'), style: const TextStyle(color: AppConfig.textSecondary)),
        ),
    ];

    return AlertDialog(
      backgroundColor: AppConfig.surface,
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      content: SizedBox(
        width: 820,
        height: 360,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            column(tr('AUDIO', 'الصوت'), Icons.audiotrack_rounded, audioList),
            const SizedBox(width: 20),
            column(tr('SUBTITLES', 'الترجمة'), Icons.subtitles_rounded, subList),
            const SizedBox(width: 20),
            column(tr('SUBTITLE STYLE', 'شكل الترجمة'), Icons.format_color_text_rounded,
                const [SubStylePicker(compact: true)]),
          ],
        ),
      ),
    );
  }
}
