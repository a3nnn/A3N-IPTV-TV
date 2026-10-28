import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'models.dart';

/// Categories hidden for every user with "A3N Category Manager"
/// (Supabase table `hidden_categories`).
///
/// A category is hidden if its id OR its name is in the list, so the list
/// also works on every server in AppConfig.hosts.
///
/// Safe to remove: if the table is deleted or empty, every category is
/// shown. If Supabase can't be reached, the last list received is used.
class CategoryFilter {
  static const _prefsKey = 'hidden_categories_v2';
  static const _cacheFor = Duration(minutes: 2);

  /// section -> {'ids': {...}, 'names': {...}}
  static Map<String, HiddenCategories>? _hidden;
  static DateTime? _fetchedAt;
  static Future<void>? _running;

  /// Rule for 'live', 'movies' or 'series'.
  static Future<HiddenCategories> forSection(String section) async {
    await _ensure();
    return _hidden?[section] ?? HiddenCategories.none;
  }

  /// Ids of the categories in [cats] that must not be shown.
  static Future<Set<String>> hiddenIds(String section, List<Category> cats) async {
    final rule = await forSection(section);
    if (rule.isEmpty) return const <String>{};
    return {for (final c in cats) if (rule.hides(c.id, c.name)) c.id};
  }

  static Future<void> _ensure() {
    final at = _fetchedAt;
    if (_hidden != null && at != null && DateTime.now().difference(at) < _cacheFor) return Future.value();
    return _running ??= _refresh().whenComplete(() => _running = null);
  }

  static Future<void> _refresh() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    final fresh = await _fetch();
    if (fresh != null) {
      _hidden = fresh;
      try {
        await prefs?.setString(_prefsKey, jsonEncode({for (final e in fresh.entries) e.key: e.value.toJson()}));
      } catch (_) {}
    } else if (_hidden == null) {
      _hidden = _fromPrefs(prefs);
    }
    _fetchedAt = DateTime.now();
  }

  static Map<String, HiddenCategories> _fromPrefs(SharedPreferences? prefs) {
    try {
      final raw = prefs?.getString(_prefsKey);
      if (raw == null) return {};
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {for (final e in j.entries) '${e.key}': HiddenCategories.fromJson(e.value)};
    } catch (_) {
      return {};
    }
  }

  /// null = couldn't ask Supabase (keep the last list).
  static Future<Map<String, HiddenCategories>?> _fetch() async {
    if (AppConfig.supabaseUrl.isEmpty || AppConfig.supabaseKey.isEmpty) return {};
    final base = AppConfig.supabaseUrl.endsWith('/')
        ? AppConfig.supabaseUrl.substring(0, AppConfig.supabaseUrl.length - 1)
        : AppConfig.supabaseUrl;
    final ids = <String, Set<String>>{};
    final names = <String, Set<String>>{};
    const page = 1000;
    try {
      for (var offset = 0;; offset += page) {
        final res = await http.get(
          Uri.parse('$base/rest/v1/hidden_categories'
              '?select=section,category_id,name&order=section,category_id&limit=$page&offset=$offset'),
          headers: {'apikey': AppConfig.supabaseKey},
        ).timeout(const Duration(seconds: 6));
        // Table removed (Category Manager uninstalled): show everything.
        if (res.statusCode == 404) return {};
        if (res.statusCode != 200) return null;
        final rows = jsonDecode(utf8.decode(res.bodyBytes));
        if (rows is! List) return null;
        for (final r in rows.whereType<Map>()) {
          final s = '${r['section']}';
          (ids[s] ??= <String>{}).add('${r['category_id']}');
          final n = HiddenCategories.norm('${r['name'] ?? ''}');
          if (n.isNotEmpty) (names[s] ??= <String>{}).add(n);
        }
        if (rows.length < page) break;
      }
      return {
        for (final s in {...ids.keys, ...names.keys})
          s: HiddenCategories(ids[s] ?? const <String>{}, names[s] ?? const <String>{}),
      };
    } catch (_) {
      return null;
    }
  }
}

class HiddenCategories {
  final Set<String> ids;
  final Set<String> names;
  const HiddenCategories(this.ids, this.names);

  static const none = HiddenCategories(<String>{}, <String>{});

  bool get isEmpty => ids.isEmpty && names.isEmpty;

  static String norm(String name) => name.trim().toLowerCase();

  bool hides(String id, String name) => ids.contains(id) || names.contains(norm(name));

  Map<String, List<String>> toJson() => {'ids': ids.toList(), 'names': names.toList()};

  factory HiddenCategories.fromJson(dynamic j) {
    if (j is! Map) return none;
    Set<String> read(Object? v) => v is List ? {for (final x in v) '$x'} : <String>{};
    return HiddenCategories(read(j['ids']), read(j['names']));
  }
}
