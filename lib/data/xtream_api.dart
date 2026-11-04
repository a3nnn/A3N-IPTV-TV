import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

import '../config.dart';
import 'catalog_db.dart';
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

  // ------------------------------------------------------------ lists
  // Saved on the TV in a database (CatalogDb), downloaded from the server
  // once, then again only once a day (in the background, one list after the
  // other) or when "Update the lists" is pressed in Settings.

  /// Lists opened during this app start, kept in memory: going back to a
  /// section is instant.
  static final Map<String, (List<Category>, List<Object>)> _mem = {};
  static final Map<String, Future<(List<Category>, List<Object>)>> _opening = {};
  static final Map<String, Future<int>> _downloads = {};

  /// Bumped when an open list was replaced by a fresh download (open pages
  /// refresh quietly).
  static final ValueNotifier<int> listsChanged = ValueNotifier<int>(0);

  /// Bumped after a list was saved (the dates on the start screen).
  static final ValueNotifier<int> listsSaved = ValueNotifier<int>(0);

  /// What is happening right now, like "Loading your series list... 2/2
  /// (12.4 MB)" (shown under the loading circle), null = nothing.
  static final ValueNotifier<String?> loadStatus = ValueNotifier<String?>(null);

  /// Section being updated in the background ('live' / 'vod' / 'series').
  static final ValueNotifier<String?> updating = ValueNotifier<String?>(null);

  /// Kept for the sign-in screens.
  static void markSignedIn() {}

  /// Forget the lists in memory (sign out).
  static void clearMemory() => _mem.clear();

  static String sectionName(String sec) => switch (sec) {
        'live' => tr('channels', 'القنوات'),
        'vod' => tr('movies', 'الأفلام'),
        _ => tr('series', 'المسلسلات'),
      };

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  String _key(String sec) => '$username|$sec';

  /// When this section was last saved on the TV (null = never).
  DateTime? savedAt(String sec) => CatalogDb.updatedAt(username, sec);

  Future<(List<Category>, List<Object>)> _section(String sec) {
    final k = _key(sec);
    final m = _mem[k];
    if (m != null) return Future.value(m);
    return _opening[k] ??= _open(sec).whenComplete(() => _opening.remove(k));
  }

  Future<(List<Category>, List<Object>)> _open(String sec) async {
    final name = sectionName(sec);
    try {
      loadStatus.value = tr('Opening the $name list...', 'جاري فتح قائمة $name...');
      var data = await CatalogDb.read(username, sec);
      if (data == null) {
        // First time: download it now (with the progress shown).
        await _download(sec);
        loadStatus.value = tr('Opening the $name list...', 'جاري فتح قائمة $name...');
        data = await CatalogDb.read(username, sec);
      }
      if (data == null) {
        throw XtreamException(tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.'));
      }
      _mem[_key(sec)] = data;
      return data;
    } finally {
      loadStatus.value = null;
    }
  }

  /// Downloads [sec] into the database (one download per section at a time;
  /// asking again joins the running one).
  Future<int> _download(String sec) {
    final k = _key(sec);
    return _downloads[k] ??= () async {
      final name = sectionName(sec);
      try {
        return await CatalogDb.download(
          host: host,
          username: username,
          password: password,
          userAgent: AppConfig.userAgent,
          sec: sec,
          onProgress: (step, bytes, total) {
            if (step >= 3) {
              loadStatus.value = tr('Saving the $name list...', 'جاري حفظ قائمة $name...');
              return;
            }
            final size = bytes <= 0
                ? ''
                : total > 0
                    ? ' (${_mb(bytes)} / ${_mb(total)} ${tr('MB', 'ميقا')})'
                    : ' (${_mb(bytes)} ${tr('MB', 'ميقا')})';
            loadStatus.value = tr('Loading your $name list... $step/2$size', 'جاري تحميل قائمة $name... $step/2$size');
          },
        );
      } catch (e) {
        throw XtreamException(_downloadError('$e'));
      } finally {
        _downloads.remove(k);
        loadStatus.value = null;
        listsSaved.value++;
      }
    }();
  }

  static String _downloadError(String code) {
    if (code == 'NET') {
      return tr('Could not reach the server. Check your internet connection.', 'ما قدرنا نوصل للسيرفر. تأكد من الإنترنت.');
    }
    if (code == 'STALL') {
      return tr('The server stopped sending the list. Check your internet connection.', 'السيرفر وقف وهو يرسل القائمة. تأكد من الإنترنت.');
    }
    if (code == 'EMPTY') {
      return tr('The server sent an empty list, the saved list was kept.', 'السيرفر رجّع قائمة فاضية، وخلّينا القائمة المحفوظة.');
    }
    if (code == 'HTTP 401' || code == 'HTTP 403') {
      return tr('Access denied by the server.', 'السيرفر رفض الدخول.');
    }
    if (code.startsWith('HTTP')) return tr('Server error ($code).', 'خطأ في السيرفر ($code).');
    return tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.');
  }

  /// Downloads [sec] again now (Settings > Update the lists, or the daily
  /// update). An open list is replaced quietly. Returns an error text, or
  /// null when it worked.
  Future<String?> updateSection(String sec) async {
    updating.value = sec;
    try {
      await _download(sec);
      final k = _key(sec);
      if (_mem.containsKey(k)) {
        final d = await CatalogDb.read(username, sec);
        if (d != null) {
          _mem[k] = d;
          listsChanged.value++;
        }
      }
      return null;
    } on XtreamException catch (e) {
      return e.message;
    } catch (_) {
      return tr('Unexpected response from the server.', 'رد غير متوقع من السيرفر.');
    } finally {
      updating.value = null;
    }
  }

  static bool _dailyStarted = false;

  /// Once per app start, a little after the home screen opens: lists saved
  /// more than a day ago are downloaded again, one after the other, in the
  /// background. Lists never opened are left alone (downloaded when opened).
  void updateOldLists() {
    if (_dailyStarted) return;
    _dailyStarted = true;
    unawaited(() async {
      for (final sec in const ['live', 'vod', 'series']) {
        final at = savedAt(sec);
        if (at == null || DateTime.now().difference(at) < const Duration(hours: 24)) continue;
        await updateSection(sec);
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

  Future<List<Category>> liveCategories() async => (await _section('live')).$1;
  Future<List<LiveChannel>> liveStreams() async => (await _section('live')).$2 as List<LiveChannel>;
  Future<List<Category>> vodCategories() async => (await _section('vod')).$1;
  Future<List<Movie>> vodStreams() async => (await _section('vod')).$2 as List<Movie>;
  Future<List<Category>> seriesCategories() async => (await _section('series')).$1;
  Future<List<Series>> series() async => (await _section('series')).$2 as List<Series>;

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
