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

  static Future<void> clearCredentials() async {
    await _p.remove('username');
    await _p.remove('password');
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
}
