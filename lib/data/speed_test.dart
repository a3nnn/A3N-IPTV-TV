import 'dart:async';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../player/player_service.dart';
import 'xtream_api.dart';

/// Settings > Internet: how fast the internet is, and how fast the channels
/// server sends a movie (what actually decides if the video stutters).
class SpeedTest {
  /// Downloads from [url] for about [seconds] s; [onProgress] gets the speed
  /// so far in Mbit/s. Returns the final speed.
  static Future<double> _download(Uri url, int seconds, void Function(double mbps) onProgress,
      {Map<String, String> headers = const {}}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', url)..headers.addAll(headers);
      final res = await client.send(req).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final sw = Stopwatch()..start();
      var bytes = 0;
      double speed() {
        final t = sw.elapsedMicroseconds / 1e6;
        return t > 0 ? bytes * 8 / t / 1e6 : 0;
      }

      final done = Completer<void>();
      late final StreamSubscription<List<int>> sub;
      sub = res.stream.listen(
        (chunk) {
          bytes += chunk.length;
          onProgress(speed());
          if (sw.elapsed.inSeconds >= seconds && !done.isCompleted) {
            sub.cancel();
            done.complete();
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e) {
          if (!done.isCompleted) done.completeError(e);
        },
        cancelOnError: true,
      );
      await done.future.timeout(Duration(seconds: seconds + 5), onTimeout: () {
        sub.cancel();
      });
      return speed();
    } finally {
      client.close();
    }
  }

  /// General internet speed: small files from Cloudflare's speed test, one
  /// after the other, for about 8 s (one big file is refused).
  static Future<double> internet(void Function(double mbps) onProgress) async {
    final sw = Stopwatch()..start();
    var bytes = 0;
    var ok = false;
    double speed() {
      final t = sw.elapsedMicroseconds / 1e6;
      return t > 0 ? bytes * 8 / t / 1e6 : 0;
    }

    final client = http.Client();
    try {
      while (sw.elapsed.inSeconds < 8) {
        final res = await client
            .send(http.Request('GET', Uri.parse('https://speed.cloudflare.com/__down?bytes=25000000')))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        ok = true;
        await for (final chunk in res.stream.timeout(const Duration(seconds: 10))) {
          bytes += chunk.length;
          onProgress(speed());
          if (sw.elapsed.inSeconds >= 8) break;
        }
      }
    } catch (e) {
      if (!ok) rethrow;
    } finally {
      client.close();
    }
    return speed();
  }

  /// Time for the channels server to answer (best of 3), in ms.
  static Future<int?> ping() async {
    final api = Session.api;
    if (api == null) return null;
    final uri = Uri.parse('${api.host}/player_api.php').replace(queryParameters: {
      'username': api.username,
      'password': api.password,
    });
    int? best;
    for (var i = 0; i < 3; i++) {
      final sw = Stopwatch()..start();
      try {
        await http.get(uri, headers: {'User-Agent': AppConfig.userAgent}).timeout(const Duration(seconds: 8));
        final ms = sw.elapsedMilliseconds;
        if (best == null || ms < best) best = ms;
      } catch (_) {}
    }
    return best;
  }

  /// Speed from the channels server: part of a movie (not limited like a
  /// live channel), or a channel if there are no movies. The player is
  /// stopped first (it would share the connection).
  static Future<double?> server(void Function(double mbps) onProgress) async {
    final api = Session.api;
    if (api == null) return null;
    await PlayerService.instance.stop();
    String? url;
    try {
      final movies = await api.vodStreams();
      if (movies.isNotEmpty) url = api.movieUrl(movies[movies.length ~/ 2]);
    } catch (_) {}
    if (url == null) {
      try {
        final chans = await api.liveStreams();
        if (chans.isNotEmpty) url = api.liveUrl(chans.first);
      } catch (_) {}
    }
    if (url == null) return null;
    return _download(Uri.parse(url), 8, onProgress, headers: {'User-Agent': AppConfig.userAgent});
  }
}
