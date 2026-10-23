import '../utils.dart';

String _ext(dynamic v, String fallback) {
  final s = asString(v).trim();
  return s.isEmpty ? fallback : s;
}

class Category {
  final String id;
  final String name;
  const Category(this.id, this.name);

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(asString(j['category_id']), asString(j['category_name']).trim());
}

class LiveChannel {
  final int id;
  final int number;
  final String name;
  final String logo;
  final String categoryId;

  const LiveChannel({
    required this.id,
    required this.number,
    required this.name,
    required this.logo,
    required this.categoryId,
  });

  factory LiveChannel.fromJson(Map<String, dynamic> j) => LiveChannel(
        id: asInt(j['stream_id']),
        number: asInt(j['num']),
        name: asString(j['name']).trim(),
        logo: asString(j['stream_icon']).trim(),
        categoryId: asString(j['category_id']),
      );
}

class Movie {
  final int id;
  final String name;
  final String poster;
  final String categoryId;
  final double rating;
  final String ext;

  const Movie({
    required this.id,
    required this.name,
    required this.poster,
    required this.categoryId,
    required this.rating,
    required this.ext,
  });

  factory Movie.fromJson(Map<String, dynamic> j) => Movie(
        id: asInt(j['stream_id']),
        name: asString(j['name']).trim(),
        poster: asString(j['stream_icon']).trim(),
        categoryId: asString(j['category_id']),
        rating: asDouble(j['rating']),
        ext: _ext(j['container_extension'], 'mp4'),
      );
}

class Series {
  final int id;
  final String name;
  final String cover;
  final String categoryId;
  final double rating;
  final String plot;

  const Series({
    required this.id,
    required this.name,
    required this.cover,
    required this.categoryId,
    required this.rating,
    required this.plot,
  });

  factory Series.fromJson(Map<String, dynamic> j) => Series(
        id: asInt(j['series_id']),
        name: asString(j['name']).trim(),
        cover: asString(j['cover']).trim(),
        categoryId: asString(j['category_id']),
        rating: asDouble(j['rating']),
        plot: asString(j['plot']).trim(),
      );
}

class Episode {
  final String id;
  final String title;
  final int season;
  final int episodeNum;
  final String ext;
  final String plot;
  final String image;

  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.episodeNum,
    required this.ext,
    required this.plot,
    required this.image,
  });

  factory Episode.fromJson(Map<String, dynamic> j, {int fallbackSeason = 1}) {
    final info = j['info'] is Map ? Map<String, dynamic>.from(j['info'] as Map) : <String, dynamic>{};
    return Episode(
      id: asString(j['id']),
      title: asString(j['title']).trim(),
      season: asInt(j['season'], fallbackSeason),
      episodeNum: asInt(j['episode_num']),
      ext: _ext(j['container_extension'], 'mp4'),
      plot: asString(info['plot']).trim(),
      image: asString(info['movie_image']).trim(),
    );
  }
}

class SeriesInfo {
  final String plot;
  final Map<int, List<Episode>> seasons;

  const SeriesInfo({required this.plot, required this.seasons});

  factory SeriesInfo.fromJson(dynamic data) {
    final Map map = data is Map ? data : {};
    final Map info = map['info'] is Map ? map['info'] as Map : {};
    final seasons = <int, List<Episode>>{};

    void addList(dynamic list, int? seasonKey) {
      if (list is! List) return;
      for (final e in list.whereType<Map>()) {
        final ep = Episode.fromJson(Map<String, dynamic>.from(e), fallbackSeason: seasonKey ?? 1);
        seasons.putIfAbsent(ep.season, () => []).add(ep);
      }
    }

    final eps = map['episodes'];
    if (eps is Map) {
      eps.forEach((k, v) => addList(v, int.tryParse(k.toString())));
    } else if (eps is List) {
      for (final item in eps) {
        if (item is List) {
          addList(item, null);
        } else if (item is Map) {
          addList([item], null);
        }
      }
    }

    for (final list in seasons.values) {
      list.sort((a, b) => a.episodeNum.compareTo(b.episodeNum));
    }
    final sorted = seasons.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return SeriesInfo(
      plot: asString(info['plot']).trim(),
      seasons: Map.fromEntries(sorted),
    );
  }
}

class EpgEntry {
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  const EpgEntry({required this.title, required this.description, required this.start, required this.end});

  bool isLiveAt(DateTime t) => !start.isAfter(t) && end.isAfter(t);

  double progressAt(DateTime t) {
    final total = end.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (t.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  factory EpgEntry.fromJson(Map<String, dynamic> j) {
    DateTime parse(dynamic ts, dynamic text) {
      final n = asInt(ts);
      if (n > 0) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      return DateTime.tryParse(asString(text)) ?? DateTime.now();
    }

    return EpgEntry(
      title: decodeB64(asString(j['title'])).trim(),
      description: decodeB64(asString(j['description'])).trim(),
      start: parse(j['start_timestamp'], j['start']),
      end: parse(j['stop_timestamp'], j['end'] ?? j['stop']),
    );
  }
}

class AccountInfo {
  final String username;
  final String status;
  final DateTime? expDate;
  final int maxConnections;
  final int activeConnections;

  const AccountInfo({
    required this.username,
    required this.status,
    required this.expDate,
    required this.maxConnections,
    required this.activeConnections,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) {
    final ts = asInt(j['exp_date']);
    return AccountInfo(
      username: asString(j['username']),
      status: asString(j['status']),
      expDate: ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts * 1000) : null,
      maxConnections: asInt(j['max_connections']),
      activeConnections: asInt(j['active_cons']),
    );
  }
}
