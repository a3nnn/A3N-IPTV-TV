import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static String? get username => _p.getString('username');
  static String? get password => _p.getString('password');

  static Future<void> saveCredentials(String u, String p) async {
    await _p.setString('username', u);
    await _p.setString('password', p);
  }

  /// The server this account signed in on last time.
  static String? get host => _p.getString('host');
  static Future<void> setHost(String h) => _p.setString('host', h);

  static Future<void> clearCredentials() async {
    await _p.remove('username');
    await _p.remove('password');
    await _p.remove('host');
    await _p.remove('last_channel');
    await _p.remove('last_category');
  }

  static Set<int> get favorites =>
      (_p.getStringList('fav_live') ?? const []).map(int.tryParse).whereType<int>().toSet();

  static Future<void> setFavorites(Set<int> ids) =>
      _p.setStringList('fav_live', ids.map((e) => '$e').toList());

  static int? get lastChannel => _p.getInt('last_channel');
  static Future<void> setLastChannel(int id) => _p.setInt('last_channel', id);

  static String? get lastCategory => _p.getString('last_category');
  static Future<void> setLastCategory(String id) => _p.setString('last_category', id);

  /// Pinned category ids per section ('live', 'movies', 'series'), in pin order.
  static List<String> pinned(String section) => _p.getStringList('pinned_$section') ?? const [];
  static Future<void> setPinned(String section, List<String> ids) => _p.setStringList('pinned_$section', ids);

  /// Last section opened from the start menu (0 live, 1 movies, 2 series, 3 settings).
  static int get lastSection => _p.getInt('last_section') ?? 0;
  static Future<void> setLastSection(int i) => _p.setInt('last_section', i);

  /// Subtitles picked automatically for movies / episodes:
  /// 'off', 'ar', 'en' or 'ar_en' (Arabic, else English). Default Arabic.
  static String get subtitleLang => _p.getString('subtitle_lang') ?? 'ar';
  static Future<void> setSubtitleLang(String v) => _p.setString('subtitle_lang', v);

  /// Subtitle look: color, size, background box and its opacity.
  static String get subColor => _p.getString('sub_color') ?? 'white';
  static Future<void> setSubColor(String v) => _p.setString('sub_color', v);
  static String get subSize => _p.getString('sub_size') ?? 'm';
  static Future<void> setSubSize(String v) => _p.setString('sub_size', v);
  static bool get subBackground => _p.getBool('sub_bg') ?? false;
  static Future<void> setSubBackground(bool v) => _p.setBool('sub_bg', v);
  static double get subBgOpacity => _p.getDouble('sub_bg_opacity') ?? 0.5;
  static Future<void> setSubBgOpacity(double v) => _p.setDouble('sub_bg_opacity', v);

  /// Watch progress of movies / episodes (JSON, see WatchHistory).
  static String? get watchJson => _p.getString('watch_history');
  static Future<void> setWatchJson(String v) => _p.setString('watch_history', v);

  /// Last category / last opened poster per section ('movies', 'series').
  static String? lastCatalogCategory(String section) => _p.getString('last_cat_$section');
  static Future<void> setLastCatalogCategory(String section, String id) => _p.setString('last_cat_$section', id);
  static int? lastCatalogItem(String section) => _p.getInt('last_item_$section');
  static Future<void> setLastCatalogItem(String section, int id) => _p.setInt('last_item_$section', id);

  static String? get language => _p.getString('language');
  static Future<void> setLanguage(String code) => _p.setString('language', code);

  /// Text size of the whole app: 'small', 'normal' or 'large'.
  static String get textSize => _p.getString('text_size') ?? 'normal';
  static Future<void> setTextSize(String v) => _p.setString('text_size', v);

  static double get volume => _p.getDouble('volume') ?? 100;
  static Future<void> setVolume(double v) => _p.setDouble('volume', v);

  /// Random id created the first time the app runs on this computer.
  static String get deviceId {
    var id = _p.getString('device_id');
    if (id == null || id.length < 16) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _p.setString('device_id', id);
    }
    return id;
  }

  static bool get licenseBlocked => _p.getBool('license_blocked') ?? false;
  static String? get licenseMessage => _p.getString('license_message');

  static Future<void> setLicense(bool blocked, String? message) async {
    await _p.setBool('license_blocked', blocked);
    if (message == null || message.isEmpty) {
      await _p.remove('license_message');
    } else {
      await _p.setString('license_message', message);
    }
  }

  // ---------- TV settings ----------
  /// Use the "Compatible" video decoder (only if "Fast" shows a black picture).
  static bool get compatibleDecoder => _p.getBool('compatible_decoder') ?? false;
  static Future<void> setCompatibleDecoder(bool v) => _p.setBool('compatible_decoder', v);

  /// Play the channel in the small preview while browsing.
  /// Off in light mode (Lite) whatever the setting says.
  static bool get previewEnabled => !liteMode && previewEnabledSetting;
  static bool get previewEnabledSetting => _p.getBool('preview_enabled') ?? true;

  /// Light mode for weak devices (Fire Stick...). See lib/lite.dart.
  static bool get liteMode => _p.getBool('lite_mode') ?? false;
  static Future<void> setLiteMode(bool v) => _p.setBool('lite_mode', v);
  static Future<void> setPreviewEnabled(bool v) => _p.setBool('preview_enabled', v);

  // ---------- Movie / series favorites ----------
  static Set<int> _ids(String key) =>
      (_p.getStringList(key) ?? const []).map(int.tryParse).whereType<int>().toSet();

  static Set<int> get favMovies => _ids('fav_movies');
  static Set<int> get favSeries => _ids('fav_series');

  static Future<bool> toggleFav(String key, int id) async {
    final ids = _ids(key);
    final added = !ids.remove(id);
    if (added) ids.add(id);
    await _p.setStringList(key, ids.map((e) => '$e').toList());
    return added;
  }
}
