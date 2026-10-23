import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/common.dart';

/// Full-screen player for movies and episodes, driven by the TV remote:
/// OK = play / pause, ◀ ▶ = seek 10 s (hold to go faster), BACK = close.
class PlayerPage extends StatefulWidget {
  final String url;
  final String title;
  const PlayerPage({super.key, required this.url, required this.title});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PlayerService _svc = PlayerService.instance;
  final FocusNode _focus = FocusNode();
  Timer? _hideTimer;
  bool _overlay = true;
  int _repeat = 0;

  @override
  void initState() {
    super.initState();
    _svc.play(widget.url);
    _poke();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    _svc.stop();
    super.dispose();
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!_overlay) setState(() => _overlay = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  void _seek(int direction, {bool repeat = false}) {
    final p = _svc.player;
    final dur = p.state.duration;
    if (dur == Duration.zero) return;
    _repeat = repeat ? _repeat + 1 : 0;
    // Holding the button speeds up: 10 s, then 30 s, then 60 s steps.
    final step = _repeat > 12 ? 60 : (_repeat > 4 ? 30 : 10);
    var target = p.state.position + Duration(seconds: step * direction);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    p.seek(target);
    _poke();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
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
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      _poke();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
              Video(controller: _svc.controller, controls: NoVideoControls, fill: Colors.black),
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
                            children: [
                              const SignatureBadge(),
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
                                'OK  play/pause     ◀ ▶  seek     BACK  exit',
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
                          child: StreamBuilder<Duration>(
                            stream: p.stream.position,
                            initialData: p.state.position,
                            builder: (context, _) {
                              final pos = p.state.position;
                              final dur = p.state.duration;
                              final v = dur.inMilliseconds > 0
                                  ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                                  : 0.0;
                              return Row(
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
                                  const SizedBox(width: 14),
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
