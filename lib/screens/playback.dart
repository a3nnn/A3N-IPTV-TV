import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/watch_history.dart';
import '../data/xtream_api.dart';
import '../l10n.dart';
import '../utils.dart';
import 'player_page.dart';

/// Opens a movie: asks "continue / start over" if it was stopped half-way.
Future<void> playMovie(BuildContext context, Movie m) {
  final entry = WatchEntry(
    key: WatchHistory.movieKey(m.id),
    isEpisode: false,
    id: '${m.id}',
    ext: m.ext,
    title: m.name,
    image: m.poster,
  );
  return _play(context, entry, ask: true);
}

WatchEntry _episodeEntry(Series series, Episode e) => WatchEntry(
      key: WatchHistory.episodeKey(e.id),
      isEpisode: true,
      id: e.id,
      ext: e.ext,
      title: e.title,
      image: e.image,
      seriesId: series.id,
      seriesName: series.name,
      seriesCover: series.cover,
      season: e.season,
      episodeNum: e.episodeNum,
    );

/// Opens an episode of [series] (same question as for movies).
/// [all] = every episode of the series in order, for the "Next episode" button.
Future<void> playEpisode(BuildContext context, Series series, Episode e, {List<Episode> all = const []}) {
  return _play(context, _episodeEntry(series, e), ask: true, next: _nextOf(series, all, e));
}

/// The episode after [e] (next in the season, or first of the next season).
NextEpisode? _nextOf(Series series, List<Episode> all, Episode e) {
  final i = all.indexWhere((x) => x.id == e.id);
  if (i < 0 || i + 1 >= all.length) return null;
  final n = all[i + 1];
  return NextEpisode(
    label: 'S${two(n.season)}E${two(n.episodeNum)}',
    open: (ctx) {
      final api = Session.api;
      if (api == null) return;
      final entry = _episodeEntry(series, n);
      final saved = WatchHistory.get(entry.key);
      Navigator.of(ctx).pushReplacement(MaterialPageRoute(
        builder: (_) => PlayerPage(
          url: api.seriesEpisodeUrl(entry.id, entry.ext),
          title: playerTitle(entry),
          watch: entry,
          startAt: Duration(seconds: saved != null && saved.resumable ? saved.position : 0),
          next: _nextOf(series, all, n),
        ),
      ));
    },
  );
}

/// From "Continue watching": goes straight back to where it stopped.
/// For an episode, the series' episode list is loaded first so the
/// "Next episode" button works here too.
Future<void> resumeEntry(BuildContext context, WatchEntry e) async {
  final next = e.isEpisode ? await _nextForEntry(e) : null;
  if (!context.mounted) return;
  await _play(context, e, ask: false, next: next);
}

Future<NextEpisode?> _nextForEntry(WatchEntry e) async {
  final api = Session.api;
  if (api == null) return null;
  try {
    final info = await api.seriesInfo(e.seriesId).timeout(const Duration(seconds: 8));
    final keys = info.seasons.keys.toList()..sort();
    final all = [for (final k in keys) ...info.seasons[k]!];
    final i = all.indexWhere((x) => x.id == e.id);
    if (i < 0) return null;
    final series = Series(
      id: e.seriesId,
      name: e.seriesName,
      cover: e.seriesCover,
      categoryId: '',
      rating: 0,
      plot: '',
    );
    return _nextOf(series, all, all[i]);
  } catch (_) {
    return null; // no internet / server error: play without the button
  }
}

String playerTitle(WatchEntry e) {
  if (!e.isEpisode) return e.title;
  final label = 'S${two(e.season)}E${two(e.episodeNum)}';
  return '${e.seriesName}  ·  $label${e.title.isNotEmpty ? '  ·  ${e.title}' : ''}';
}

Future<void> _play(BuildContext context, WatchEntry entry, {required bool ask, NextEpisode? next}) async {
  final api = Session.api;
  if (api == null) return;
  final saved = WatchHistory.get(entry.key);
  var start = 0;
  if (saved != null && saved.resumable) {
    if (ask) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppConfig.surface,
          title: Text(playerTitle(entry), maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Start over', 'البدء من جديد')),
            ),
            FilledButton.icon(
              autofocus: true,
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('Continue watching', 'استمرار من حيث توقفت')),
            ),
          ],
        ),
      );
      if (resume == null || !context.mounted) return; // closed = cancel
      if (resume) start = saved.position;
    } else {
      start = saved.position;
    }
  }
  final url = entry.isEpisode ? api.seriesEpisodeUrl(entry.id, entry.ext) : api.vodUrl(entry.id, entry.ext);
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PlayerPage(
      url: url,
      title: playerTitle(entry),
      watch: entry,
      startAt: Duration(seconds: start),
      next: next,
    ),
  ));
}
