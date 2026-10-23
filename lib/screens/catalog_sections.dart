import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/category_panel.dart';
import '../widgets/common.dart';
import 'player_page.dart';
import 'series_detail_screen.dart';

const String _allId = '__all';

class CatalogItem {
  final String title;
  final String image;
  final String categoryId;
  final double rating;
  final void Function(BuildContext context) onOpen;

  const CatalogItem({
    required this.title,
    required this.image,
    required this.categoryId,
    required this.rating,
    required this.onOpen,
  });
}

class CatalogData {
  final List<Category> categories;
  final List<CatalogItem> items;
  const CatalogData(this.categories, this.items);
}

// ------------------------------------------------------------ Movies

class MoviesSection extends StatelessWidget {
  const MoviesSection({super.key});

  Future<CatalogData> _load() async {
    final api = Session.api!;
    final results = await Future.wait<Object>([api.vodCategories(), api.vodStreams()]);
    final cats = results[0] as List<Category>;
    final movies = results[1] as List<Movie>;
    return CatalogData(
      cats,
      movies
          .map((m) => CatalogItem(
                title: m.name,
                image: m.poster,
                categoryId: m.categoryId,
                rating: m.rating,
                onOpen: (ctx) => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => PlayerPage(url: api.movieUrl(m), title: m.name)),
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      CatalogSection(section: 'movies', load: _load, allLabel: 'All Movies', searchHint: 'Search movies');
}

// ------------------------------------------------------------ Series

class SeriesSection extends StatelessWidget {
  const SeriesSection({super.key});

  Future<CatalogData> _load() async {
    final api = Session.api!;
    final results = await Future.wait<Object>([api.seriesCategories(), api.series()]);
    final cats = results[0] as List<Category>;
    final list = results[1] as List<Series>;
    return CatalogData(
      cats,
      list
          .map((s) => CatalogItem(
                title: s.name,
                image: s.cover,
                categoryId: s.categoryId,
                rating: s.rating,
                onOpen: (ctx) => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)),
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      CatalogSection(section: 'series', load: _load, allLabel: 'All Series', searchHint: 'Search series');
}

// ------------------------------------------------------------ shared grid

class CatalogSection extends StatefulWidget {
  final Future<CatalogData> Function() load;
  final String allLabel;
  final String searchHint;
  final String section;

  const CatalogSection({super.key, required this.section, required this.load, required this.allLabel, required this.searchHint});

  @override
  State<CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<CatalogSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _gridScroll = ScrollController();

  bool _loading = true;
  String? _error;
  CatalogData _data = const CatalogData([], []);
  Map<String, int> _counts = {};
  String _categoryId = _allId;
  String _query = '';
  List<CatalogItem> _visible = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.load();
      final counts = <String, int>{};
      for (final it in data.items) {
        counts[it.categoryId] = (counts[it.categoryId] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _counts = counts;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyFilter() {
    Iterable<CatalogItem> list =
        _categoryId == _allId ? _data.items : _data.items.where((i) => i.categoryId == _categoryId);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) list = list.where((i) => i.title.toLowerCase().contains(q));
    _visible = list.toList();
  }

  void _selectCategory(String id) {
    setState(() {
      _categoryId = id;
      _applyFilter();
    });
    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return Row(
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.22).clamp(180.0, 250.0),
          child: CategoryPanel(
            section: widget.section,
            selectedId: _categoryId,
            onSelect: _selectCategory,
            entries: [
              CategoryEntry(id: _allId, name: widget.allLabel, count: _data.items.length, fixed: true),
              ..._data.categories.map((c) => CategoryEntry(id: c.id, name: c.name, count: _counts[c.id] ?? 0)),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: SizedBox(
                  width: 420,
                  child: TvSearchButton(
                    hint: widget.searchHint,
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() {
                      _query = v;
                      _applyFilter();
                    }),
                  ),
                ),
              ),
              Expanded(
                child: _visible.isEmpty
                    ? const Center(child: Text('Nothing here', style: TextStyle(color: AppConfig.textSecondary)))
                    : Scrollbar(
                        controller: _gridScroll,
                        child: GridView.builder(
                          controller: _gridScroll,
                          padding: const EdgeInsets.all(20),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: 18,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.56,
                          ),
                          itemCount: _visible.length,
                          itemBuilder: (context, i) => PosterCard(item: _visible[i]),
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

class PosterCard extends StatefulWidget {
  final CatalogItem item;
  const PosterCard({super.key, required this.item});

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: () => item.onOpen(context),
        onFocusChange: (f) => setState(() => _focus = f),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: AppConfig.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _focus ? AppConfig.textPrimary : (_hover ? AppConfig.primary : Colors.transparent),
                    width: _focus ? 3 : 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(url: item.image, fallbackIcon: Icons.movie_outlined, cacheWidth: 360),
                      if (item.rating > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: fade(Colors.black, 0.7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 12, color: AppConfig.accent),
                                const SizedBox(width: 2),
                                Text(item.rating.toStringAsFixed(1),
                                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.25,
                color: _hover || _focus ? AppConfig.textPrimary : fade(AppConfig.textPrimary, 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
