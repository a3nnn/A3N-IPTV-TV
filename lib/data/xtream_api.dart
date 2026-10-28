import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

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

  Future<List<T>> _listOf<T>(String action, T Function(Map<String, dynamic>) fromJson) async {
    final bytes = await _cachedFetch(action);
    try {
      return await Isolate.run(() => _parseList<T>(bytes, fromJson));
    } catch (_) {
      await DiskCache.deleteList(_listName(action));
      throw XtreamException(tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.'));
    }
  }

  String _listName(String action) => '$host|$username|$action';

  /// Lists already updated in the background during this app start.
  static final Set<String> _refreshed = {};

  /// Uses the copy saved on the TV so the screen opens at once, and quietly
  /// downloads a fresh copy for next time. A copy older than a day is only
  /// used if the server can't be reached.
  Future<Uint8List> _cachedFetch(String action) async {
    final name = _listName(action);
    final saved = await DiskCache.readList(name);
    if (saved != null && saved.$2 < const Duration(hours: 24)) {
      if (_refreshed.add(name)) {
        unawaited(_fetch({'action': action}).then((b) => DiskCache.writeList(name, b)).catchError((_) {}));
      }
      return saved.$1;
    }
    try {
      final fresh = await _fetch({'action': action});
      _refreshed.add(name);
      unawaited(DiskCache.writeList(name, fresh));
      return fresh;
    } catch (e) {
      if (saved != null) return saved.$1;
      rethrow;
    }
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
    Object? firstError;
    if (saved != null && hosts.contains(saved)) {
      final api = XtreamApi(host: saved, username: username, password: password);
      try {
        return (api, await api.login());
      } catch (e) {
        firstError = e;
        hosts.remove(saved);
      }
    }
    if (hosts.isEmpty) throw firstError ?? XtreamException(tr('No server set.', 'ما فيه سيرفر.'));

    final done = Completer<(XtreamApi, AccountInfo)>();
    final errors = <Object>[if (firstError != null) firstError];
    var left = hosts.length;
    for (final h in hosts) {
      final api = XtreamApi(host: h, username: username, password: password);
      api.login().then((info) {
        if (!done.isCompleted) done.complete((api, info));
      }, onError: (Object e) {
        errors.add(e);
        if (--left == 0 && !done.isCompleted) {
          // A server that answered says more than one that couldn't be reached.
          done.completeError(errors.firstWhere((x) => x is XtreamAuthException, orElse: () => errors.first));
        }
      });
    }
    return done.future;
  }

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
