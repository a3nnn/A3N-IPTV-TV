// Tests the lists database with a list as big as the real one (~70 MB of
// series), served by a local fake server. Run on GitHub (test.yml).
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:a3n_iptv_tv/data/catalog_db.dart';
import 'package:a3n_iptv_tv/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

String _plot(int i) =>
    'قصة المسلسل رقم $i {مع أقواس} و "علامات تنصيص" \\ وخط مائل، ' * 6;

/// ~70 MB like the real series list: plots, cast, backdrops...
Uint8List _bigSeries(int n) {
  final sb = StringBuffer('[');
  for (var i = 0; i < n; i++) {
    if (i > 0) sb.write(',');
    sb.write(jsonEncode({
      'num': i + 1,
      'name': 'مسلسل $i {test} "x"',
      'series_id': 100000 + i,
      'cover': 'http://img.example.com/covers/$i.jpg',
      'plot': _plot(i),
      'cast': 'ممثل أ، ممثل ب، ممثل ج، ممثل د',
      'director': 'مخرج',
      'genre': 'دراما / أكشن',
      'releaseDate': '2024-01-01',
      'last_modified': '1700000000',
      'rating': '${(i % 10)}.5',
      'rating_5based': 3.2,
      'backdrop_path': ['http://img.example.com/back/$i-1.jpg', 'http://img.example.com/back/$i-2.jpg'],
      'youtube_trailer': '',
      'episode_run_time': '45',
      'category_id': '${i % 120}',
      'category_ids': [i % 120],
    }));
  }
  sb.write(']');
  return Uint8List.fromList(utf8.encode(sb.toString()));
}

Uint8List _cats(int n) => Uint8List.fromList(utf8.encode(jsonEncode([
      for (var i = 0; i < n; i++) {'category_id': '$i', 'category_name': 'قسم $i', 'parent_id': 0},
    ])));

// Isolate.run only gets plain values (a local server or port must not be sent).
Future<int> _import(ImportArgs a, SendPort? p) => Isolate.run(() => CatalogDb.importNow(a, p));
Future<(List<Category>, List<Object>)?> _read(String path) =>
    Isolate.run(() => CatalogDb.readNow(path, 'user', 'series'));

void main() {
  late HttpServer server;
  late Directory dir;
  var seriesBody = Uint8List(0);
  var catsBody = Uint8List(0);
  var cutHalfway = false;
  var emptyList = false;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('catalog_test');
    seriesBody = _bigSeries(60000);
    catsBody = _cats(120);
    // ignore: avoid_print
    print('fake series list: ${(seriesBody.length / 1048576).toStringAsFixed(1)} MB');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final action = req.uri.queryParameters['action'];
      final body = action == 'get_series_categories' ? catsBody : (emptyList ? utf8.encode('[]') : seriesBody);
      req.response.headers.contentLength = body.length;
      // Sent in small pieces, like a real network.
      const piece = 64 * 1024;
      for (var i = 0; i < body.length; i += piece) {
        if (cutHalfway && action == 'get_series' && i > body.length ~/ 2) {
          // Less than announced, then the connection closes.
          try {
            await req.response.close();
          } catch (_) {}
          return;
        }
        req.response.add(body.sublist(i, i + piece > body.length ? body.length : i + piece));
      }
      await req.response.close();
    });
    CatalogDb.init(dir.path);
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  ImportArgs args() => ImportArgs('${dir.path}/catalog.db', 'http://127.0.0.1:${server.port}', 'user', 'pass', 'test', 'series');

  test('splitter: braces / quotes / escapes inside strings, pieces cut anywhere', () {
    final objs = [
      {'a': 'x{y}z', 'b': r'q"uo\te'},
      {'n': 1, 'list': [1, 2, {'deep': '}]'}]},
      {'ar': 'مرحبا {عالم} "اقتباس"'},
    ];
    final bytes = utf8.encode(jsonEncode(objs));
    for (final size in [1, 2, 3, 7, 50, 100000]) {
      final got = <Object?>[];
      final s = JsonArraySplitter((b) => got.add(jsonDecode(utf8.decode(b))));
      for (var i = 0; i < bytes.length; i += size) {
        s.add(bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size));
      }
      expect(jsonEncode(got), jsonEncode(objs), reason: 'piece size $size');
    }
  });

  test('big list: download + save + read, fast and light', () async {
    final rssBefore = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    final port = ReceivePort();
    var lastMb = 0.0;
    port.listen((m) {
      if (m is List) lastMb = (m[1] as int) / 1048576;
    });
    final n = await _import(args(), port.sendPort);
    port.close();
    final importMs = sw.elapsedMilliseconds;
    expect(n, 60000);
    expect(lastMb, greaterThan(0));

    sw.reset();
    final path = '${dir.path}/catalog.db';
    final data = await _read(path);
    final readMs = sw.elapsedMilliseconds;
    expect(data, isNotNull);
    final (cats, items) = data!;
    expect(cats.length, 120);
    expect(items.length, 60000);
    expect(items, isA<List<Series>>());
    final s = items[7] as Series;
    expect(s.id, 100007);
    expect(s.name, 'مسلسل 7 {test} "x"');
    expect(s.categoryId, '7');
    expect(s.cover, 'http://img.example.com/covers/7.jpg');
    expect(s.rating, 7.5);
    expect(CatalogDb.updatedAt('user', 'series'), isNotNull);
    final dbMb = File(path).lengthSync() / 1048576;
    final rssMb = (ProcessInfo.maxRss - rssBefore) / 1048576;
    // ignore: avoid_print
    print('import ${importMs}ms, read ${readMs}ms, db ${dbMb.toStringAsFixed(1)} MB, extra peak RAM ~${rssMb.toStringAsFixed(0)} MB');
    expect(readMs, lessThan(5000));
  });

  test('download cut in the middle: the saved list is kept', () async {
    cutHalfway = true;
    Object? error;
    try {
      await _import(args(), null);
    } catch (e) {
      error = e;
    }
    cutHalfway = false;
    expect(error, isNotNull);
    final path = '${dir.path}/catalog.db';
    final data = await _read(path);
    expect(data!.$2.length, 60000);
  });

  test('empty answer from the server: the saved list is kept', () async {
    emptyList = true;
    Object? error;
    try {
      await _import(args(), null);
    } catch (e) {
      error = e;
    }
    emptyList = false;
    expect('$error', contains('EMPTY'));
    final path = '${dir.path}/catalog.db';
    final data = await _read(path);
    expect(data!.$2.length, 60000);
  });

  test('second download replaces the list (no duplicates)', () async {
    final n = await _import(args(), null);
    expect(n, 60000);
    final path = '${dir.path}/catalog.db';
    final data = await _read(path);
    expect(data!.$2.length, 60000);
    expect(data.$1.length, 120);
  });

  test('clear all (sign out)', () async {
    await CatalogDb.clearAll();
    final path = '${dir.path}/catalog.db';
    final data = await _read(path);
    expect(data, isNull);
  });
}
