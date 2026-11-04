import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

import '../config.dart';
import 'disk_cache.dart';
import 'models.dart';
import '../l10n.dart';

class XtreamException implements Exception {
  final String message;
  XtreamException(this.message);
  @override
  String toString() => message;
}

/// The server answered, but refused this account (wrong password, expired…).
class XtreamAuthException extends XtreamException {
  XtreamAuthException(super.message);
}

/// The logged-in session, shared across screens.
class Session {
  static XtreamApi? api;
  static AccountInfo? account;
}

class XtreamApi {
  final String host;
  final String username;
  final String password;

  XtreamApi({required String host, required this.username, required this.password})
      : host = _normalize(host);

  static String _normalize(String h) {
    var x = h.trim();
    while (x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    if (!x.startsWith('http://') && !x.startsWith('https://')) x = 'http://$x';
    return x;
  }

  String get _u => Uri.encodeComponent(username);
  String get _p => Uri.encodeComponent(password);

  /// Big playlists (tens of thousands of items) are parsed on a background
  /// isolate so the TV interface never freezes while loading.
  static dynamic _decode(Uint8List bytes) => jsonDecode(utf8.decode(bytes, allowMalformed: true));

  static List<T> _parseList<T>(Uint8List bytes, T Function(Map<String, dynamic>) fromJson) {
    final data = _decode(bytes);
    if (data is! List) return <T>[];
    return data.whereType<Map>().map((e) => fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// The only fields the lists use. The copy saved on the TV keeps just
  /// these (the server's list also has plots, cast, backdrops...), so it is
  /// several times smaller and much faster to read.
  static const Map<String, List<String>> _fields = {
    'get_live_categories': ['category_id', 'category_name'],
    'get_vod_categories': ['category_id', 'category_name'],
    'get_series_categories': ['category_id', 'category_name'],
    'get_live_streams': ['stream_id', 'num', 'name', 'stream_icon', 'category_id'],
    'get_vod_streams': ['stream_id', 'name', 'stream_icon', 'category_id', 'rating', 'container_extension'],
    'get_series': ['series_id', 'name', 'cover', 'category_id', 'rating'],
  };

  /// Server answer -> the list + the small copy to save.
  static (List<T>, Uint8List) _parseAndSlim<T>(Uint8List bytes, T Function(Map<String, dynamic>) fromJson, List<String>? keys) {
    final data = _decode(bytes);
    if (data is! List) return (<T>[], Uint8List(0));
    final maps = data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final list = maps.map(fromJson).toList();
    final slim = keys == null ? maps : [for (final m in maps) {for (final k in keys) if (m.containsKey(k)) k: m[k]}];
    return (list, Uint8List.fromList(utf8.encode(jsonEncode(slim))));
  }

  String _listName(String action) => '$host|$username|$action';
  String _slimName(String action) => '${_listName(action)}|s1';

  /// Lists kept ready in memory (until the app is closed).
  static final Map<String, List<Object?>> _mem = {};
  static final Map<String, Future<Object>> _pending = {};

  /// Lists already updated from the server during this app start.
  static final Set<String> _refreshed = {};

  /// Completed once the account is signed in: the lists are only updated
  /// from the server after that, so the sign-in never has to share the
  /// internet connection with big downloads.
  static final Completer<void> _signedIn = Completer<void>();
  static void markSignedIn() {
    if (!_signedIn.isCompleted) _signedIn.complete();
  }

  /// Bumped when a fresh list from the server is ready (open pages refresh).
  static final ValueNotifier<int> listsChanged = ValueNotifier<int>(0);

  /// Copy in memory -> copy saved on the TV (any age, shown at once and
  /// updated from the server in the background) -> the server (only when
  /// nothing is saved yet, e.g. right after signing in).
  Future<List<T>> _listOf<T>(String action, T Function(Map<String, dynamic>) fromJson) async {
    final name = _listName(action);
    final m = _mem[name];
    if (m != null) return m as List<T>;
    final job = _pending[name] ??= _load<T>(action, fromJson).whenComplete(() => _pending.remove(name));
    return (await job) as List<T>;
  }

  Future<List<T>> _load<T>(String action, T Function(Map<String, dynamic>) fromJson) async {
    final name = _listName(action);
    final saved = await DiskCache.readList(_slimName(action)) ?? await DiskCache.readList(name);
    if (saved != null) {
      try {
        final bytes = saved.$1;
        final list = await Isolate.run(() => _parseList<T>(bytes, fromJson));
        _mem[name] ??= list;
        if (_refreshed.add(name)) {
          unawaited(_signedIn.future
              .then((_) => Future<void>.delayed(const Duration(seconds: 3)))
              .then((_) => _refresh<T>(action, fromJson)));
        }
        return _mem[name]! as List<T>;
      } catch (_) {
        await DiskCache.deleteList(_slimName(action));
        await DiskCache.deleteList(name);
      }
    }
    _refreshed.add(name);
    final list = await _fromServer<T>(action, fromJson);
    _mem[name] = list;
    return list;
  }

  Future<List<T>> _fromServer<T>(String action, T Function(Map<String, dynamic>) fromJson) async {
    final raw = await _fetch({'action': action});
    final keys = _fields[action];
    final r = await Isolate.run(() => _parseAndSlim<T>(raw, fromJson, keys)).catchError(
        (Object _) => throw XtreamException(tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.')));
    unawaited(() async {
      await DiskCache.writeList(_slimName(action), r.$2);
      await DiskCache.deleteList(_listName(action)); // old full-size copy
    }());
    return r.$1;
  }

  Future<void> _refresh<T>(String action, T Function(Map<String, dynamic>) fromJson) async {
    try {
      final list = await _fromServer<T>(action, fromJson);
      _mem[_listName(action)] = list;
      listsChanged.value++;
    } catch (_) {}
  }

  /// Reads the saved lists into memory right when the app starts (before the
  /// sign-in finishes), the section used last first, so opening a section
  /// is instant. [onlyFirst] = weak devices: just that one section.
  static void preload({required String host, required String username, required String password, required int firstSection, bool onlyFirst = false}) {
    final api = XtreamApi(host: host, username: username, password: password);
    final jobs = <int, List<(String, Future<Object> Function())>>{
      0: [('get_live_categories', api.liveCategories), ('get_live_streams', api.liveStreams)],
      1: [('get_vod_categories', api.vodCategories), ('get_vod_streams', api.vodStreams)],
      2: [('get_series_categories', api.seriesCategories), ('get_series', api.series)],
    };
    final order = [if (jobs.containsKey(firstSection)) firstSection, ...[0, 2, 1].where((i) => i != firstSection)];
    unawaited(() async {
      for (final i in onlyFirst ? order.take(1) : order) {
        for (final (action, job) in jobs[i]!) {
          // Only what is already saved on the TV: never the server here.
          final saved = await DiskCache.hasList(api._slimName(action)) || await DiskCache.hasList(api._listName(action));
          if (!saved) continue;
          try {
            await job();
          } catch (_) {}
        }
      }
    }());
  }

  Future<dynamic> _get(Map<String, String> extra) async {
    final bytes = await _fetch(extra);
    try {
      return await Isolate.run(() => _decode(bytes));
    } catch (_) {
      throw XtreamException(tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.'));
    }
  }

  Future<Uint8List> _fetch(Map<String, String> extra) async {
    final uri = Uri.parse('$host/player_api.php').replace(queryParameters: {
      'username': username,
      'password': password,
      ...extra,
    });
    http.Response res;
    try {
      res = await http
          .get(uri, headers: {'User-Agent': AppConfig.userAgent})
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw XtreamException(tr('Could not reach the server. Check your internet connection.', 'ما قدرنا نوصل للسيرفر. تأكد من الإنترنت.'));
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw XtreamException(tr('Access denied by the server (${res.statusCode}).', 'السيرفر رفض الدخول (${res.statusCode}).'));
    }
    if (res.statusCode != 200) {
      throw XtreamException(tr('Server error (${res.statusCode}).', 'خطأ في السيرفر (${res.statusCode}).'));
    }
    return res.bodyBytes;
  }

  /// Signs in on whichever server in [AppConfig.hosts] knows this account.
  /// The server that worked last time ([savedHost]) is tried first; if it
  /// fails, all the others are tried at the same time and the first one that
  /// accepts the account wins.
  static Future<(XtreamApi, AccountInfo)> signIn(String username, String password, {String? savedHost}) async {
    final hosts = [for (final h in AppConfig.hosts) _normalize(h)];
    final saved = savedHost == null ? null : _normalize(savedHost);
    final errors = <Object>[];

    // The server that worked last time is tried on its own first.
    if (saved != null && hosts.remove(saved)) {
      final api = XtreamApi(host: saved, username: username, password: password);
      try {
        return (api, await _tryLogin(api));
      } catch (e) {
        errors.add(e);
      }
    }
    if (hosts.isEmpty) {
      throw errors.isNotEmpty ? errors.first : XtreamException(tr('No server set.', 'ما فيه سيرفر.'));
    }

    // The others are asked at the same time (a dead server doesn't hold the
    // rest up), but the answer is taken in list order: the first server in
    // AppConfig.hosts that accepts the account wins.
    final apis = [for (final h in hosts) XtreamApi(host: h, username: username, password: password)];
    final tries = [for (final a in apis) _tryLogin(a)];
    for (final t in tries) {
      t.ignore(); // errors are read below, in order
    }
    for (var i = 0; i < apis.length; i++) {
      try {
        return (apis[i], await tries[i]);
      } catch (e) {
        errors.add(e);
      }
    }
    // A server that answered says more than one that couldn't be reached.
    throw errors.firstWhere((x) => x is XtreamAuthException, orElse: () => errors.first);
  }

  static Future<AccountInfo> _tryLogin(XtreamApi api) => api.login().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw XtreamException(
            tr('Could not reach the server. Check your internet connection.', 'ما قدرنا نوصل للسيرفر. تأكد من الإنترنت.')),
      );

  Future<AccountInfo> login() async {
    final data = await _get(const {});
    if (data is! Map) throw XtreamException(tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.'));
    final ui = data['user_info'];
    if (ui is! Map || '${ui['auth']}' != '1') {
      throw XtreamAuthException(tr('Wrong username or password.', 'اسم المستخدم أو كلمة المرور غلط.'));
    }
    final info = AccountInfo.fromJson(Map<String, dynamic>.from(ui));
    if (info.status.isNotEmpty && info.status.toLowerCase() != 'active') {
      throw XtreamAuthException(tr('Subscription status: ${info.status}', 'حالة الاشتراك: ${info.status}'));
    }
    return info;
  }

  Future<List<Category>> liveCategories() async =>
      _listOf('get_live_categories', Category.fromJson);

  Future<List<LiveChannel>> liveStreams() async =>
      _listOf('get_live_streams', LiveChannel.fromJson);

  Future<List<Category>> vodCategories() async =>
      _listOf('get_vod_categories', Category.fromJson);

  Future<List<Movie>> vodStreams() async =>
      _listOf('get_vod_streams', Movie.fromJson);

  Future<List<Category>> seriesCategories() async =>
      _listOf('get_series_categories', Category.fromJson);

  Future<List<Series>> series() async =>
      _listOf('get_series', Series.fromJson);

  Future<SeriesInfo> seriesInfo(int seriesId) async =>
      SeriesInfo.fromJson(await _get({'action': 'get_series_info', 'series_id': '$seriesId'}));

  Future<List<EpgEntry>> shortEpg(int streamId, {int limit = 10}) async {
    final data = await _get({
      'action': 'get_short_epg',
      'stream_id': '$streamId',
      'limit': '$limit',
    });
    if (data is Map && data['epg_listings'] is List) {
      final list = (data['epg_listings'] as List)
          .whereType<Map>()
          .map((e) => EpgEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => a.start.compareTo(b.start));
      return list;
    }
    return [];
  }

  String liveUrl(LiveChannel c) => '$host/live/$_u/$_p/${c.id}.${AppConfig.liveFormat}';
  String movieUrl(Movie m) => '$host/movie/$_u/$_p/${m.id}.${m.ext}';
  String episodeUrl(Episode e) => '$host/series/$_u/$_p/${e.id}.${e.ext}';
  String vodUrl(String id, String ext) => '$host/movie/$_u/$_p/$id.$ext';
  String seriesEpisodeUrl(String id, String ext) => '$host/series/$_u/$_p/$id.$ext';
}
