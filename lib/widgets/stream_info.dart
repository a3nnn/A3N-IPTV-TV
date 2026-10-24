import 'dart:async';

import 'package:flutter/material.dart';

import '../player/player_service.dart';
import '../utils.dart';

/// "FHD 1080p · 50Hz" — shown for a few seconds when a channel / movie starts.
class StreamInfoBadge extends StatefulWidget {
  /// Smaller text for the small preview window.
  final bool compact;

  /// When given, the badge shows and hides together with the player's info
  /// bar (true = shown) instead of disappearing on its own.
  final bool? show;
  const StreamInfoBadge({super.key, this.compact = false, this.show});

  @override
  State<StreamInfoBadge> createState() => _StreamInfoBadgeState();
}

class _StreamInfoBadgeState extends State<StreamInfoBadge> {
  final PlayerService _svc = PlayerService.instance;
  Timer? _poll;
  Timer? _hide;
  String? _text;
  bool _visible = false;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    _svc.opened.addListener(_detect);
    _detect();
  }

  @override
  void dispose() {
    _svc.opened.removeListener(_detect);
    _poll?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  /// Waits until the new stream reports its size, then shows the badge.
  void _detect() {
    final run = ++_run;
    _poll?.cancel();
    _hide?.cancel();
    // Old stream's info goes away until the new one is known.
    if ((_visible || _text != null) && mounted) {
      setState(() {
        _visible = false;
        _text = null;
      });
    }
    var tries = 0;
    _poll = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      if (++tries > 25) t.cancel();
      final w = int.tryParse(await _svc.property('video-params/w')) ?? 0;
      final h = int.tryParse(await _svc.property('video-params/h')) ?? 0;
      if (!mounted || run != _run || h <= 0) return;
      t.cancel();
      var fps = double.tryParse(await _svc.property('container-fps')) ?? 0;
      if (fps <= 0) fps = double.tryParse(await _svc.property('estimated-vf-fps')) ?? 0;
      if (!mounted || run != _run) return;
      setState(() {
        _text = _label(w, h, fps);
        _visible = true;
      });
      if (widget.show != null) return; // follows the info bar
      _hide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _visible = false);
      });
    });
  }

  static String _label(int w, int h, double fps) {
    final q = (w >= 3200 || h >= 1800)
        ? '4K'
        : (w >= 1800 || h >= 1000)
            ? 'FHD'
            : (w >= 1200 || h >= 700)
                ? 'HD'
                : 'SD';
    final parts = ['$q ${h}p'];
    if (fps > 0) {
      final f = (fps - fps.round()).abs() < 0.05 ? '${fps.round()}' : fps.toStringAsFixed(2);
      parts.add('${f}Hz');
    }
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    final small = widget.compact;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: (widget.show ?? _visible) && _text != null ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 4 : 6),
          decoration: BoxDecoration(
            color: fade(Colors.black, 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: fade(Colors.white, 0.25)),
          ),
          child: Text(
            _text ?? '',
            style: TextStyle(
              color: Colors.white,
              fontSize: small ? 11 : 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
