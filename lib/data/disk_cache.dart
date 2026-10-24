import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Keeps posters, logos and the channel / movie lists on the TV itself, so
/// they show at once instead of being downloaded again every time.
class DiskCache {
  static const int _maxImageBytes = 100 * 1024 * 1024; // 100 MB
  static const int _trimToBytes = 80 * 1024 * 1024;

  static Directory? _images;
  static Directory? _lists;
  static final Set<String> _known = {};
  static final Map<String, Future<File?>> _inFlight = {};
  static int _addedSinceTrim = 0;
  static bool _trimming = false;

  // At most a few image downloads at once, so scrolling fast never floods
  // the internet connection that the video is using.
  static int _running = 0;
  static final List<Completer<void>> _waiting = [];

  static Future<void> init() async {
    try {
      final tmp = await getTemporaryDirectory();
      final sup = await getApplicationSupportDirectory();
      _images = await Directory('${tmp.path}/a3n_images').create(recursive: true);
      _lists = await Directory('${sup.path}/a3n_lists').create(recursive: true);
      // Remember which images are already saved (in the background).
      unawaited(() async {
        try {
          await for (final e in _images!.list()) {
            if (e is File) _known.add(e.uri.pathSegments.last);
          }
        } catch (_) {}
        unawaited(_trim());
      }());
    } catch (_) {}
  }

  /// Short, file-name-safe key for a text (FNV-1a hash).
  static String key(String s) {
    var h = 0x4bf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${h.toRadixString(16)}_${s.length}';
  }

  // ------------------------------------------------------------ images

  /// The saved file if it is already on the TV (no waiting), otherwise null.
  static File? cachedImage(String url) {
    final dir = _images;
    if (dir == null) return null;
    final name = key(url);
    return _known.contains(name) ? File('${dir.path}/$name') : null;
  }

  /// Downloads the image once and saves it. Null if it couldn't be loaded.
  static Future<File?> image(String url) {
    final dir = _images;
    if (dir == null) return Future.value(null);
    final name = key(url);
    return _inFlight.putIfAbsent(name, () async {
      try {
        final file = File('${dir.path}/$name');
        if (await file.exists()) {
          _known.add(name);
          return file;
        }
        await _slot();
        try {
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
          final ct = (res.headers['content-type'] ?? '').toLowerCase();
          final notImage = ct.startsWith('text/') || ct.contains('json') || ct.contains('html');
          if (res.statusCode != 200 || res.bodyBytes.length < 64 || notImage) return null;
          final part = File('${file.path}.part');
          await part.writeAsBytes(res.bodyBytes, flush: false);
          await part.rename(file.path);
          _known.add(name);
          _addedSinceTrim += res.bodyBytes.length;
          if (_addedSinceTrim > 20 * 1024 * 1024) unawaited(_trim());
          return file;
        } finally {
          _release();
        }
      } catch (_) {
        return null;
      } finally {
        _inFlight.remove(name);
      }
    });
  }

  /// A saved image that turned out broken.
  static void forgetImage(String url) {
    final dir = _images;
    if (dir == null) return;
    final name = key(url);
    _known.remove(name);
    File('${dir.path}/$name').delete().catchError((_) => File(''));
  }

  static Future<void> _slot() async {
    if (_running < 4) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete(); // hand the slot over
    } else {
      _running--;
    }
  }

  /// Deletes the oldest images when the folder grows over 100 MB.
  static Future<void> _trim() async {
    final dir = _images;
    if (dir == null || _trimming) return;
    _trimming = true;
    _addedSinceTrim = 0;
    try {
      final files = <(File, int, DateTime)>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final st = await e.stat();
        files.add((e, st.size, st.modified));
        total += st.size;
      }
      if (total <= _maxImageBytes) return;
      files.sort((a, b) => a.$3.compareTo(b.$3));
      for (final f in files) {
        if (total <= _trimToBytes) break;
        try {
          await f.$1.delete();
          _known.remove(f.$1.uri.pathSegments.last);
          total -= f.$2;
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      _trimming = false;
    }
  }

  // ------------------------------------------------------------ lists

  static File? _listFile(String name) {
    final dir = _lists;
    return dir == null ? null : File('${dir.path}/${key(name)}.json');
  }

  /// Saved copy of a list and how old it is, or null.
  static Future<(Uint8List, Duration)?> readList(String name) async {
    try {
      final f = _listFile(name);
      if (f == null || !await f.exists()) return null;
      final age = DateTime.now().difference(await f.lastModified());
      return (await f.readAsBytes(), age);
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeList(String name, Uint8List bytes) async {
    try {
      final f = _listFile(name);
      if (f == null || bytes.length < 2) return;
      final part = File('${f.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(f.path);
    } catch (_) {}
  }

  static Future<void> deleteList(String name) async {
    try {
      await _listFile(name)?.delete();
    } catch (_) {}
  }
}
