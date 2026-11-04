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

  /// Episode added by itself after the one before it was finished
  /// ("Next episode" in Continue watching, even before it is started).
  bool upNext;

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
    this.upNext = false,
  });

  double get fraction => duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

  /// Worth offering "continue": started (over a minute in) and not finished.
  bool get resumable => !done && position >= 60;

  /// Shown in "Continue watching".
  bool get inContinue => !done && (position >= 60 || upNext);

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
        if (upNext) 'n': true,
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
        upNext: j['n'] == true,
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
  /// For a series: the newest episode left half-way or the next episode
  /// after a finished one. An episode only opened for a few seconds doesn't
  /// hide the one left half-way. A series is dropped once its last episode
  /// is finished.
  static List<WatchEntry> continueList({int max = 20}) {
    final list = _map.values.where((e) => e.inContinue).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    final seenSeries = <int>{};
    final out = <WatchEntry>[];
    for (final e in list) {
      if (e.isEpisode) {
        // A later episode was finished after this one (and there is no next one).
        final last = lastOfSeries(e.seriesId);
        if (last != null && last.done && last.updated > e.updated) continue;
        if (!seenSeries.add(e.seriesId)) continue;
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
    if (e.done || position >= 60) e.upNext = false;
    e.updated = DateTime.now().millisecondsSinceEpoch;
    _map[e.key] = e;
    _scheduleSave();
  }

  /// [next] follows an episode that was just finished: it goes to the front
  /// of "Continue watching" as "Next episode".
  static void queueNext(WatchEntry next) {
    final now = DateTime.now().millisecondsSinceEpoch + 1;
    final cur = _map[next.key];
    if (cur != null && !cur.done) {
      cur.updated = now;
      if (!cur.resumable) cur.upNext = true;
    } else {
      next
        ..position = 0
        ..done = false
        ..upNext = true
        ..updated = now;
      _map[next.key] = next;
    }
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
