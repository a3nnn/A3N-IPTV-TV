import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// The channel / movie / series lists, saved on the TV in a small SQLite
/// database (like Hot Player / TiviMate do).
///
///  * A list is downloaded from the server ONCE and saved here. Opening a
///    section reads this database (fast, no big JSON to decode).
///  * The download is read piece by piece while it arrives: one movie at a
///    time is decoded and written, so even a 70 MB list needs very little
///    memory.
///  * A new download is written next to the old list and only replaces it
///    once it is complete (no internet in the middle = the old list stays).
///  * All the heavy work runs on a background isolate: the screen never
///    freezes.
///
/// Sections: 'live', 'vod', 'series'. [acc] = the account (username).
class CatalogDb {
  static String? _path;
  static Database? _main; // small queries on the main isolate (dates)

  /// Bumped after a list was saved (the start screen shows the new date).
  static int changes = 0;

  /// Call once at start with the folder for the database.
  static void init(String folder) {
    _path = '$folder/catalog.db';
    try {
      _main = _open(_path!);
    } catch (_) {
      _main = null;
    }
  }

  static bool get ready => _path != null;

  static Database _open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA synchronous=NORMAL;');
    db.execute('PRAGMA busy_timeout=8000;');
    db.execute('CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT)');
    db.execute('CREATE TABLE IF NOT EXISTS cats(acc TEXT, sec TEXT, pos INTEGER, id TEXT, name TEXT)');
    db.execute('CREATE TABLE IF NOT EXISTS items(acc TEXT, sec TEXT, pos INTEGER, id INTEGER, num INTEGER, '
        'cat TEXT, name TEXT, img TEXT, rating REAL, ext TEXT)');
    db.execute('CREATE INDEX IF NOT EXISTS items_sec ON items(acc, sec, pos)');
    db.execute('CREATE INDEX IF NOT EXISTS cats_sec ON cats(acc, sec, pos)');
    return db;
  }

  /// When [sec] was last saved for [acc], or null if it never was.
  static DateTime? updatedAt(String acc, String sec) {
    final db = _main;
    if (db == null) return null;
    try {
      final r = db.select('SELECT v FROM meta WHERE k = ?', ['upd|$acc|$sec']);
      if (r.isEmpty) return null;
      final ms = int.tryParse('${r.first.columnAt(0)}');
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  /// Everything saved for every account (sign out).
  static Future<void> clearAll() async {
    final path = _path;
    if (path == null) return;
    await Isolate.run(() {
      final db = _open(path);
      try {
        db.execute('DELETE FROM items');
        db.execute('DELETE FROM cats');
        db.execute("DELETE FROM meta WHERE k LIKE 'upd|%'");
      } finally {
        db.dispose();
      }
    });
    changes++;
  }

  /// Reads a saved section: (categories, items), or null if never saved.
  /// Items are LiveChannel / Movie / Series depending on [sec].
  static Future<(List<Category>, List<Object>)?> read(String acc, String sec) {
    final path = _path;
    if (path == null) return Future.value(null);
    return _readOn(path, acc, sec);
  }

  static Future<(List<Category>, List<Object>)?> _readOn(String path, String acc, String sec) =>
      Isolate.run(() => readNow(path, acc, sec));

  /// The read itself (also used by the tests).
  static (List<Category>, List<Object>)? readNow(String path, String acc, String sec) {
    final db = _open(path);
    try {
      final saved = db.select('SELECT 1 FROM meta WHERE k = ?', ['upd|$acc|$sec']);
      if (saved.isEmpty) return null;
      final cats = <Category>[
        for (final r in db.select('SELECT id, name FROM cats WHERE acc = ? AND sec = ? ORDER BY pos', [acc, sec]))
          Category('${r.columnAt(0) ?? ''}', '${r.columnAt(1) ?? ''}'),
      ];
      final rows = db.select(
          'SELECT id, num, cat, name, img, rating, ext FROM items WHERE acc = ? AND sec = ? ORDER BY pos', [acc, sec]);
      // A list of the real type (List<Movie>...), so the screens can use it as is.
      final List<Object> items = switch (sec) {
        'live' => <LiveChannel>[],
        'vod' => <Movie>[],
        _ => <Series>[],
      };
      for (final r in rows) {
        final id = (r.columnAt(0) as int?) ?? 0;
        final cat = '${r.columnAt(2) ?? ''}';
        final name = '${r.columnAt(3) ?? ''}';
        final img = '${r.columnAt(4) ?? ''}';
        final rating = (r.columnAt(5) as num?)?.toDouble() ?? 0;
        switch (sec) {
          case 'live':
            items.add(LiveChannel(id: id, number: (r.columnAt(1) as int?) ?? 0, name: name, logo: img, categoryId: cat));
          case 'vod':
            items.add(Movie(
                id: id, name: name, poster: img, categoryId: cat, rating: rating, ext: '${r.columnAt(6) ?? 'mp4'}'));
          default:
            items.add(Series(id: id, name: name, cover: img, categoryId: cat, rating: rating, plot: ''));
        }
      }
      return (cats, items);
    } finally {
      db.dispose();
    }
  }

  /// Downloads [sec] from the server and saves it. [onProgress] gets
  /// (step 1..2, bytes so far, total bytes or 0) while downloading, then
  /// (3, 0, 0) while the new list replaces the old one. Throws a message
  /// (String) on failure, the old list is then kept.
  static Future<int> download({
    required String host,
    required String username,
    required String password,
    required String userAgent,
    required String sec,
    void Function(int step, int bytes, int total)? onProgress,
  }) async {
    final path = _path;
    if (path == null) throw 'The database is not ready.';
    final port = ReceivePort();
    final sub = port.listen((m) {
      if (m is List && m.length == 3 && onProgress != null) onProgress(m[0] as int, m[1] as int, m[2] as int);
    });
    try {
      final args = ImportArgs(path, host, username, password, userAgent, sec);
      return await _importOn(args, port.sendPort);
    } finally {
      await sub.cancel();
      port.close();
      changes++;
    }
  }

  static Future<int> _importOn(ImportArgs a, SendPort progress) => Isolate.run(() => importNow(a, progress));

  static String _actions(String sec, bool categories) => switch (sec) {
        'live' => categories ? 'get_live_categories' : 'get_live_streams',
        'vod' => categories ? 'get_vod_categories' : 'get_vod_streams',
        _ => categories ? 'get_series_categories' : 'get_series',
      };

  /// The download + save itself (runs on a background isolate; also used by
  /// the tests). Returns the number of items saved.
  static Future<int> importNow(ImportArgs a, SendPort? progress) async {
    final db = _open(a.dbPath);
    final acc = a.username;
    final stage = '${a.sec}~new';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..userAgent = a.userAgent;
    var last = DateTime(2000);
    void report(int step, int bytes, int total, {bool force = false}) {
      final now = DateTime.now();
      if (!force && now.difference(last) < const Duration(milliseconds: 250)) return;
      last = now;
      progress?.send([step, bytes, total]);
    }

    Uri url(String action) {
      var h = a.host.trim();
      while (h.endsWith('/')) {
        h = h.substring(0, h.length - 1);
      }
      return Uri.parse('$h/player_api.php').replace(queryParameters: {
        'username': a.username,
        'password': a.password,
        'action': action,
      });
    }

    Future<HttpClientResponse> open(String action) async {
      final HttpClientResponse res;
      try {
        final req = await client.getUrl(url(action)).timeout(const Duration(seconds: 30));
        res = await req.close().timeout(const Duration(seconds: 30));
      } catch (_) {
        throw 'NET';
      }
      if (res.statusCode != 200) {
        await res.drain<void>().catchError((_) {});
        throw 'HTTP ${res.statusCode}';
      }
      return res;
    }

    void clearStage() {
      db.execute('DELETE FROM items WHERE acc = ? AND sec = ?', [acc, stage]);
      db.execute('DELETE FROM cats WHERE acc = ? AND sec = ?', [acc, stage]);
    }

    try {
      clearStage();

      // 1/2: categories (small).
      report(1, 0, 0, force: true);
      final catRes = await open(_actions(a.sec, true));
      final catBytes = BytesBuilder(copy: false);
      try {
        await for (final c in catRes.timeout(const Duration(seconds: 30))) {
          catBytes.add(c);
          report(1, catBytes.length, catRes.contentLength > 0 ? catRes.contentLength : 0);
        }
      } catch (_) {
        throw 'STALL';
      }
      final catJson = jsonDecode(utf8.decode(catBytes.takeBytes(), allowMalformed: true));
      final insCat = db.prepare('INSERT INTO cats(acc, sec, pos, id, name) VALUES (?, ?, ?, ?, ?)');
      db.execute('BEGIN');
      var cpos = 0;
      if (catJson is List) {
        for (final e in catJson) {
          if (e is! Map) continue;
          final c = Category.fromJson(e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e));
          insCat.execute([acc, stage, cpos++, c.id, c.name]);
        }
      }
      db.execute('COMMIT');
      insCat.dispose();

      // 2/2: the items (big): read piece by piece, one item at a time.
      report(2, 0, 0, force: true);
      final res = await open(_actions(a.sec, false));
      final total = res.contentLength > 0 ? res.contentLength : 0;
      final ins = db.prepare(
          'INSERT INTO items(acc, sec, pos, id, num, cat, name, img, rating, ext) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
      var pos = 0;
      var inTx = false;
      void addItem(Uint8List bytes) {
        final Object? m;
        try {
          m = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        } catch (_) {
          return;
        }
        if (m is! Map) return;
        final j = m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m);
        if (!inTx) {
          db.execute('BEGIN');
          inTx = true;
        }
        switch (a.sec) {
          case 'live':
            final c = LiveChannel.fromJson(j);
            ins.execute([acc, stage, pos++, c.id, c.number, c.categoryId, c.name, c.logo, 0.0, '']);
          case 'vod':
            final v = Movie.fromJson(j);
            ins.execute([acc, stage, pos++, v.id, 0, v.categoryId, v.name, v.poster, v.rating, v.ext]);
          default:
            final s = Series.fromJson(j);
            ins.execute([acc, stage, pos++, s.id, 0, s.categoryId, s.name, s.cover, s.rating, '']);
        }
        if (pos % 4000 == 0) {
          db.execute('COMMIT');
          inTx = false;
        }
      }

      final splitter = JsonArraySplitter(addItem);
      var received = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          splitter.add(chunk);
          report(2, received, total);
        }
      } catch (e) {
        if (inTx) db.execute('ROLLBACK');
        inTx = false;
        throw 'STALL';
      } finally {
        if (inTx) db.execute('COMMIT');
        ins.dispose();
      }
      report(2, received, total, force: true);

      // A server answering with an empty list (error page, hiccup) must not
      // wipe a good saved list.
      final old = db.select('SELECT COUNT(*) FROM items WHERE acc = ? AND sec = ?', [acc, a.sec]).first.columnAt(0) as int;
      if (pos == 0 && old > 0) throw 'EMPTY';

      // 3: the new list replaces the old one, all at once.
      report(3, 0, 0, force: true);
      db.execute('BEGIN');
      try {
        db.execute('DELETE FROM items WHERE acc = ? AND sec = ?', [acc, a.sec]);
        db.execute('DELETE FROM cats WHERE acc = ? AND sec = ?', [acc, a.sec]);
        db.execute('UPDATE items SET sec = ? WHERE acc = ? AND sec = ?', [a.sec, acc, stage]);
        db.execute('UPDATE cats SET sec = ? WHERE acc = ? AND sec = ?', [a.sec, acc, stage]);
        db.execute('INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)',
            ['upd|$acc|${a.sec}', '${DateTime.now().millisecondsSinceEpoch}']);
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      return pos;
    } catch (e) {
      try {
        clearStage();
      } catch (_) {}
      if (e is String) rethrow;
      throw 'ERR $e';
    } finally {
      client.close(force: true);
      db.dispose();
    }
  }
}

/// What a background download needs (only plain text: safe to send).
class ImportArgs {
  final String dbPath, host, username, password, userAgent, sec;
  const ImportArgs(this.dbPath, this.host, this.username, this.password, this.userAgent, this.sec);
}

/// Cuts a JSON array of objects ([{...},{...}]) into its objects while the
/// bytes arrive, without ever holding the whole text: [onObject] gets the
/// bytes of one object at a time.
class JsonArraySplitter {
  final void Function(Uint8List object) onObject;
  JsonArraySplitter(this.onObject);

  int _depth = 0;
  bool _inString = false;
  bool _escape = false;
  bool _array = false;
  BytesBuilder? _current;

  void add(List<int> chunk) {
    var start = _current != null ? 0 : -1;
    for (var i = 0; i < chunk.length; i++) {
      final b = chunk[i];
      if (_inString) {
        if (_escape) {
          _escape = false;
        } else if (b == 0x5C) {
          _escape = true;
        } else if (b == 0x22) {
          _inString = false;
        }
        continue;
      }
      if (b == 0x22) {
        _inString = true;
      } else if (b == 0x5B || b == 0x7B) {
        _depth++;
        if (_depth == 1 && b == 0x5B) {
          _array = true;
        } else if (_depth == 2 && b == 0x7B && _array) {
          _current = BytesBuilder(copy: false);
          start = i;
        }
      } else if (b == 0x5D || b == 0x7D) {
        if (_depth == 2 && b == 0x7D && _current != null) {
          _current!.add(chunk.sublist(start, i + 1));
          final bytes = _current!.takeBytes();
          _current = null;
          start = -1;
          onObject(bytes);
        }
        _depth--;
      }
    }
    if (_current != null && start >= 0 && start < chunk.length) {
      _current!.add(chunk.sublist(start));
    }
  }
}
