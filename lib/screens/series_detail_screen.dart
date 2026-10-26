import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import '../data/watch_history.dart';
import 'playback.dart';
import '../l10n.dart';

class SeriesDetailScreen extends StatefulWidget {
  final Series series;
  const SeriesDetailScreen({super.key, required this.series});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  bool _loading = true;
  String? _error;
  SeriesInfo? _info;
  int? _season;
  late bool _fav = Storage.favSeries.contains(widget.series.id);

  // Opens on the last episode watched (or the first one).
  final ScrollController _listScroll = ScrollController();
  final FocusNode _targetNode = FocusNode();
  String? _targetEpisode;

  @override
  void dispose() {
    _listScroll.dispose();
    _targetNode.dispose();
    super.dispose();
  }

  Future<void> _toggleFav() async {
    final added = await Storage.toggleFav('fav_series', widget.series.id);
    if (mounted) setState(() => _fav = added);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await Session.api!.seriesInfo(widget.series.id);
      if (!mounted) return;
      final last = WatchHistory.lastOfSeries(widget.series.id);
      int? season = info.seasons.keys.isEmpty ? null : info.seasons.keys.first;
      String? target;
      if (last != null) {
        for (final entry in info.seasons.entries) {
          final list = entry.value;
          final i = list.indexWhere((e) => e.id == last.id);
          if (i < 0) continue;
          season = entry.key;
          // Finished it? Then the next episode is the one to watch.
          target = (last.done && i + 1 < list.length) ? list[i + 1].id : list[i].id;
          break;
        }
      }
      setState(() {
        _info = info;
        _season = season;
        _targetEpisode = target;
        _loading = false;
      });
      if (target != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _scrollToTarget() {
    final id = _targetEpisode;
    final eps = _info?.seasons[_season] ?? const <Episode>[];
    final i = eps.indexWhere((e) => e.id == id);
    if (i < 0 || !mounted) return;
    if (_listScroll.hasClients) {
      final pos = _listScroll.position;
      pos.jumpTo((8 + i * 109.0 - 120).clamp(0.0, pos.maxScrollExtent));
    }
    void focus(int n) {
      if (!mounted) return;
      if (_targetNode.context != null) {
        _targetNode.requestFocus();
      } else if (n < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => focus(n + 1));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => focus(0));
  }

  Future<void> _play(Episode e) async {
    await playEpisode(context, widget.series, e);
    if (mounted) setState(() {}); // refresh the watched marks
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.series;
    return Scaffold(
      body: Column(
        children: [
          TopBar(
            title: s.name,
            leading: IconButton(
              tooltip: tr('Back', 'رجوع'),
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    final info = _info!;
    final s = widget.series;
    final plot = info.plot.isNotEmpty ? info.plot : s.plot;
    final episodes = _season == null ? <Episode>[] : (info.seasons[_season] ?? <Episode>[]);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: AppConfig.surfaceHigh,
                      child: NetImage(url: s.cover, fallbackIcon: Icons.video_library_outlined, cacheWidth: 500),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                if (s.rating > 0) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.star_rounded, size: 18, color: AppConfig.accent),
                    const SizedBox(width: 4),
                    Text(s.rating.toStringAsFixed(1), style: const TextStyle(color: AppConfig.textSecondary)),
                  ]),
                ],
                const SizedBox(height: 16),
                FavoriteButton(active: _fav, onPressed: _toggleFav),
                if (plot.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(plot, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppConfig.textSecondary)),
                ],
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: info.seasons.isEmpty
              ? Center(child: Text(tr('No episodes available', 'لا توجد حلقات'), style: const TextStyle(color: AppConfig.textSecondary)))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final season in info.seasons.keys)
                            ChoiceChip(
                              label: Text(tr('Season $season', 'الموسم $season')),
                              selected: season == _season,
                              onSelected: (_) => setState(() => _season = season),
                              selectedColor: fade(AppConfig.primary, 0.25),
                              side: BorderSide(color: season == _season ? AppConfig.primary : AppConfig.divider),
                              showCheckmark: false,
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: StayInList(
                        child: ListView.separated(
                        controller: _listScroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: episodes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 24, endIndent: 24),
                        itemBuilder: (context, i) => _EpisodeTile(
                          episode: episodes[i],
                          autofocus: _targetEpisode == null && i == 0,
                          focusNode: episodes[i].id == _targetEpisode ? _targetNode : null,
                          onTap: () => _play(episodes[i]),
                        ),
                      ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  final Episode episode;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  const _EpisodeTile({required this.episode, required this.onTap, this.autofocus = false, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final e = episode;
    final w = WatchHistory.get(WatchHistory.episodeKey(e.id));
    return InkWell(
      onTap: onTap,
      autofocus: autofocus,
      focusNode: focusNode,
      hoverColor: fade(AppConfig.textPrimary, 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 150,
              height: 84,
              decoration: BoxDecoration(color: AppConfig.surfaceHigh, borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(url: e.image, fallbackIcon: Icons.play_circle_outline_rounded, cacheWidth: 300),
                  const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 34)),
                  if (w != null && w.resumable)
                    Positioned(left: 0, right: 0, bottom: 0, child: WatchProgressBar(fraction: w.fraction)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${tr('Episode', 'الحلقة')} ${e.episodeNum}${e.title.isNotEmpty ? '  ·  ${e.title}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (w != null && w.done) ...[
                        const SizedBox(width: 10),
                        const WatchedBadge(),
                      ],
                    ],
                  ),
                  if (e.plot.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      e.plot,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.4, color: AppConfig.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
