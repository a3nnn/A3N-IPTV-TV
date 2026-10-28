import 'package:flutter/widgets.dart';

import 'data/storage.dart';

/// App-wide text size, picked in Settings: 'small', 'normal' (default) or
/// 'large'. Changing it redraws the app at once.
class TextSize {
  static final ValueNotifier<String> value = ValueNotifier('normal');

  static void init() => value.value = Storage.textSize;

  static double scale(String v) => switch (v) {
        'small' => 0.85,
        'large' => 1.0,
        _ => 0.92,
      };

  static Future<void> set(String v) async {
    value.value = v;
    await Storage.setTextSize(v);
  }
}
