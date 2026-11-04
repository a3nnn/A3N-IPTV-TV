import 'dart:async';
import 'dart:io';

import 'package:flutter_displaymode/flutter_displaymode.dart';

/// "Match screen refresh rate" (Settings > Display): while a movie or an
/// episode plays, the TV is switched to the refresh rate that fits the video
/// (25 / 50 fps -> 50 Hz, 24 -> 24 Hz, 30 / 60 -> 60 Hz) at the same
/// resolution, so motion is smooth. Put back when the player closes.
class FrameRateMatch {
  static bool _switched = false;
  static int _gen = 0;

  static double? _targetFor(double fps) {
    bool near(double v) => (fps - v).abs() < 0.6;
    if (near(25) || near(50)) return 50;
    if (near(24)) return 24; // also 23.976
    if (near(30) || near(60)) return 60; // also 29.97 / 59.94
    return null;
  }

  static Future<void> apply(double fps) async {
    _gen++; // cancels a pending "put back" (next episode)
    if (!Platform.isAndroid || fps <= 0) return;
    final target = _targetFor(fps);
    if (target == null) return;
    try {
      final active = await FlutterDisplayMode.active;
      if ((active.refreshRate - target).abs() < 0.6) return; // already right
      final modes = await FlutterDisplayMode.supported;
      DisplayMode? best;
      for (final m in modes) {
        if (m.width != active.width || m.height != active.height) continue;
        if ((m.refreshRate - target).abs() < 0.6) {
          best = m;
          break;
        }
      }
      if (best == null) return; // the TV can't do it: change nothing
      await FlutterDisplayMode.setPreferredMode(best);
      _switched = true;
    } catch (_) {}
  }

  /// Puts the TV back shortly after the player closes (not at all if the
  /// next episode starts in the meantime, to avoid two switches).
  static void restoreSoon() {
    if (!_switched) return;
    final g = ++_gen;
    Timer(const Duration(milliseconds: 1500), () async {
      if (g != _gen || !_switched) return;
      _switched = false;
      try {
        await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
      } catch (_) {}
    });
  }
}
