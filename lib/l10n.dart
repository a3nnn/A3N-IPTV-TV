import 'package:flutter/widgets.dart';

import 'data/storage.dart';

/// App language. Arabic is the default; English can be chosen in Settings.
class L {
  static final ValueNotifier<bool> arabic = ValueNotifier<bool>(true);

  static bool get isAr => arabic.value;

  static void init() => arabic.value = Storage.language != 'en';

  static Future<void> setArabic(bool value) async {
    await Storage.setLanguage(value ? 'ar' : 'en');
    arabic.value = value;
  }

  /// Letter spacing must be 0 for Arabic (spacing breaks the joined letters).
  static double spacing(double english) => isAr ? 0 : english;
}

/// The text in the current language.
String tr(String en, String ar) => L.arabic.value ? ar : en;
