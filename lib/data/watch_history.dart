import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'storage.dart';

/// Where the user stopped in one movie or episode.
class WatchEntry {
  /// 'm:<movie id>' or 'e:<episode id>'.
  final String key;
  final bool isEpisode;
  final String id;
  final String ext;
  final String title; // movie name, or episode title line
  final String image;
  // Episodes only:
  final int seriesId;
  final String seriesName;
  final String seriesCover;
  final int season;
  final int episodeNum;

  int position; // seconds
  int duration; // seconds
  int updated; // ms since epoch
  bool done;

  WatchEntry({
    required this.key,
    required this.isEpisode,
    required this.id,
    required this.ext,
    required this.title,
    required this.image,
    this.seriesId = 0,
    this.seriesName = '',
    this.seriesCover = '',
    this.season = 0,
    this.episodeNum = 0,
    this.position = 0,
    this.duration = 0,
    this.updated = 0,
    this.done = false,
  });

  double get fraction => duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

  /// Worth offering "continue": started (over a minute in) and not finished.
  bool get resumable => !done && position >= 60;

  Map<String, dynamic> toJson() => {
        'k': key,
        'ep': isEpisode,
        'id': id,
        'x': ext,
        't': title,
        'i': image,
        'sid': seriesId,
        'sn': seriesName,
        'sc': seriesCover,
        's': season,
        'e': episodeNum,
        'p': position,
        'd': duration,
        'u': updated,
        'f': done,
      };

  static WatchEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      return WatchEntry(
        key: j['k'] as String,
        isEpisode: j['ep'] == true,
        id: '${j['id']}',
        ext: '${j['x'] ?? 'mp4'}',
        title: '${j['t'] ?? ''}',
        image: '${j['i'] ?? ''}',
        seriesId: (j['sid'] as num?)?.toInt() ?? 0,
        seriesName: '${j['sn'] ?? ''}',
        seriesCover: '${j['sc'] ?? ''}',
        season: (j['s'] as num?)?.toInt() ?? 0,
        episodeNum: (j['e'] as num?)?.toInt() ?? 0,
        position: (j['p'] as num?)?.toInt() ?? 0,
        duration: (j['d'] as num?)?.toInt() ?? 0,
        updated: (j['u'] as num?)?.toInt() ?? 0,
        done: j['f'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Saved on the TV only. Read once at start and kept in memory, so the lists
/// can show the progress bars without any slowdown.
class WatchHistory {
  static const int _maxEntries = 400;
  static final Map<String, WatchEntry> _map = {};
  static Timer? _saveTimer;

  /// Bumped when something changes (lists redraw their progress bars).
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void init() {
    try {
      final raw = Storage.watchJson;
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final j in list) {
        final e = WatchEntry.fromJson(j);
        if (e != null) _map[e.key] = e;
      }
    } catch (_) {}
  }

  static String movieKey(int id) => 'm:$id';
  static String episodeKey(String id) => 'e:$id';

  static WatchEntry? get(String key) => _map[key];

  /// The latest episode watched in a series.
  static WatchEntry? lastOfSeries(int seriesId) {
    WatchEntry? best;
    for (final e in _map.values) {
      if (e.isEpisode && e.seriesId == seriesId && (best == null || e.updated > best.updated)) best = e;
    }
    return best;
  }

  /// "Continue watching": newest first, one entry per series.
  static List<WatchEntry> continueList({int max = 20}) {
    final list = _map.values.where((e) => e.resumable).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    final seenSeries = <int>{};
    final out = <WatchEntry>[];
    for (final e in list) {
      if (e.isEpisode) {
        if (!seenSeries.add(e.seriesId)) continue;
        // A newer episode of the same series was started/finished: skip old one.
        final last = lastOfSeries(e.seriesId);
        if (last != null && last.key != e.key) continue;
      }
      out.add(e);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Called by the player while playing (every few seconds) and on close.
  static void report(WatchEntry template, int position, int duration) {
    if (duration <= 0 && position <= 0) return;
    final e = _map[template.key] ?? template;
    e.position = position;
    if (duration > 0) e.duration = duration;
    // Finished: less than 5% (or 2 minutes for long videos) left.
    final left = e.duration - position;
    e.done = e.duration > 0 && (position / e.duration >= 0.95 || (e.duration > 1200 && left < 120));
    if (e.done) e.position = 0;
    e.updated = DateTime.now().millisecondsSinceEpoch;
    _map[e.key] = e;
    _scheduleSave();
  }

  static void remove(String key) {
    if (_map.remove(key) != null) _scheduleSave();
  }

  static void _scheduleSave() {
    changed.value++;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), saveNow);
  }

  static void saveNow() {
    _saveTimer?.cancel();
    try {
      var list = _map.values.toList()..sort((a, b) => b.updated.compareTo(a.updated));
      if (list.length > _maxEntries) {
        for (final e in list.sublist(_maxEntries)) {
          _map.remove(e.key);
        }
        list = list.sublist(0, _maxEntries);
      }
      Storage.setWatchJson(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }
}
