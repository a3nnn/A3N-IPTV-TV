import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'home_screen.dart';
import 'player_page.dart';

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
      setState(() {
        _info = info;
        _season = info.seasons.keys.isEmpty ? null : info.seasons.keys.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _play(Episode e) {
    final api = Session.api!;
    final label = 'S${two(e.season)}E${two(e.episodeNum)}';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        url: api.episodeUrl(e),
        title: '${widget.series.name}  ·  $label${e.title.isNotEmpty ? '  ·  ${e.title}' : ''}',
      ),
    ));
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
              tooltip: 'Back',
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
              ? const Center(child: Text('No episodes available', style: TextStyle(color: AppConfig.textSecondary)))
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
                              label: Text('Season $season'),
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
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: episodes.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 24, endIndent: 24),
                        itemBuilder: (context, i) => _EpisodeTile(episode: episodes[i], onTap: () => _play(episodes[i])),
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
  const _EpisodeTile({required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = episode;
    return InkWell(
      onTap: onTap,
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
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Episode ${e.episodeNum}${e.title.isNotEmpty ? '  ·  ${e.title}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
