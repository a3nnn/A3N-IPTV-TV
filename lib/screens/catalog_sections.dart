import 'package:flutter/material.dart';

import '../config.dart';
import '../data/category_filter.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../utils.dart';
import '../widgets/category_panel.dart';
import '../widgets/common.dart';
import '../data/watch_history.dart';
import 'playback.dart';
import 'series_detail_screen.dart';
import '../l10n.dart';

const String _allId = '__all';
const String _favId = '__fav';

class CatalogItem {
  final int id;
  final String title;
  final String image;
  final String categoryId;
  final double rating;
  final Future<void> Function(BuildContext context) onOpen;

  /// true = series (progress comes from its latest episode).
  final bool isSeries;

  const CatalogItem({
    this.isSeries = false,
    required this.id,
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
    final allCats = results[0] as List<Category>;
    final hidden = await CategoryFilter.hiddenIds('movies', allCats);
    final cats = allCats.where((c) => !hidden.contains(c.id)).toList();
    final movies = (results[1] as List<Movie>).where((m) => !hidden.contains(m.categoryId)).toList();
    return CatalogData(
      cats,
      movies
          .map((m) => CatalogItem(
                id: m.id,
                title: m.name,
                image: m.poster,
                categoryId: m.categoryId,
                rating: m.rating,
                onOpen: (ctx) => playMovie(ctx, m),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      CatalogSection(section: 'movies', favKey: 'fav_movies', load: _load, allLabel: tr('All Movies', 'كل الأفلام'), searchHint: tr('Search movies', 'ابحث في الأفلام'));
}

// ------------------------------------------------------------ Series

class SeriesSection extends StatelessWidget {
  const SeriesSection({super.key});

  Future<CatalogData> _load() async {
    final api = Session.api!;
    final results = await Future.wait<Object>([api.seriesCategories(), api.series()]);
    final allCats = results[0] as List<Category>;
    final hidden = await CategoryFilter.hiddenIds('series', allCats);
    final cats = allCats.where((c) => !hidden.contains(c.id)).toList();
    final list = (results[1] as List<Series>).where((s) => !hidden.contains(s.categoryId)).toList();
    return CatalogData(
      cats,
      list
          .map((s) => CatalogItem(
                id: s.id,
                title: s.name,
                image: s.cover,
                categoryId: s.categoryId,
                rating: s.rating,
                isSeries: true,
                onOpen: (ctx) => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)),
                ),
              ))
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) =>
      CatalogSection(section: 'series', favKey: 'fav_series', load: _load, allLabel: tr('All Series', 'كل المسلسلات'), searchHint: tr('Search series', 'ابحث في المسلسلات'));
}

// ------------------------------------------------------------ shared grid

class CatalogSection extends StatefulWidget {
  final Future<CatalogData> Function() load;
  final String allLabel;
  final String searchHint;
  final String section;
  final String favKey;

  const CatalogSection({super.key, required this.section, required this.favKey, required this.load, required this.allLabel, required this.searchHint});

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
    _targetNode.dispose();
    _searchNode.dispose();
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
        _refreshFavs();
        _loading = false;
        _restoreLastPlace();
      });
      if (_focusItemId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // Read once and kept in memory (re-reading it per item was very slow).
  late Set<int> _favs = _readFavs();
  int _favCount = 0;

  Set<int> _readFavs() => widget.favKey == 'fav_movies' ? Storage.favMovies : Storage.favSeries;

  void _refreshFavs() {
    _favs = _readFavs();
    _favCount = _data.items.where((i) => _favs.contains(i.id)).length;
  }

  // ------------------------------------------------ back to the last place

  /// Poster to put the remote's focus on when the section opens.
  int? _focusItemId;
  final FocusNode _targetNode = FocusNode();
  final FocusNode _searchNode = FocusNode();
  double _gridWidth = 800;

  void _restoreLastPlace() {
    final cat = Storage.lastCatalogCategory(widget.section);
    if (cat != null && (cat == _allId || cat == _favId || _data.categories.any((c) => c.id == cat))) {
      _categoryId = cat;
    }
    _applyFilter();
    final last = Storage.lastCatalogItem(widget.section);
    _focusItemId = (last != null && _visible.any((i) => i.id == last)) ? last : null;
  }

  /// Scrolls the grid to the last opened poster and focuses it.
  void _scrollToTarget({int attempt = 0}) {
    final id = _focusItemId;
    if (id == null || !mounted) return;
    if (!_gridScroll.hasClients) {
      if (attempt < 5) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget(attempt: attempt + 1));
      return;
    }
    final index = _visible.indexWhere((i) => i.id == id);
    if (index < 0) return;
    // Same maths as SliverGridDelegateWithMaxCrossAxisExtent below.
    final w = (_gridWidth - 40).clamp(100.0, 10000.0);
    final cols = (w / (180 + 16)).ceil().clamp(1, 100);
    final cellW = (w - 16 * (cols - 1)) / cols;
    final rowH = cellW / 0.56 + 18;
    final row = index ~/ cols;
    final pos = _gridScroll.position;
    pos.jumpTo((row * rowH - rowH * 0.6).clamp(0.0, pos.maxScrollExtent));
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

  Future<void> _open(CatalogItem item) async {
    Storage.setLastCatalogItem(widget.section, item.id);
    await item.onOpen(context);
    // Favorites may have changed on the series screen.
    if (!mounted) return;
    setState(() {
      _refreshFavs();
      if (_categoryId == _favId) _applyFilter();
    });
  }

  Future<void> _toggleFav(CatalogItem item) async {
    final added = await Storage.toggleFav(widget.favKey, item.id);
    if (!mounted) return;
    showToast(context, added ? tr('★  ${item.title} added to favorites', '★  تمت إضافة ${item.title} للمفضلة') : tr('${item.title} removed from favorites', 'تمت إزالة ${item.title} من المفضلة'));
    setState(() {
      _refreshFavs();
      if (_categoryId == _favId) _applyFilter();
    });
  }

  void _applyFilter() {
    Iterable<CatalogItem> list;
    if (_categoryId == _allId) {
      list = _data.items;
    } else if (_categoryId == _favId) {
      final favs = _favs;
      list = _data.items.where((i) => favs.contains(i.id));
    } else {
      list = _data.items.where((i) => i.categoryId == _categoryId);
    }
    final q = searchNorm(_query.trim());
    if (q.isNotEmpty) list = list.where((i) => searchNorm(i.title).contains(q));
    _visible = list.toList();
  }

  void _selectCategory(String id) {
    Storage.setLastCatalogCategory(widget.section, id);
    _focusItemId = null;
    setState(() {
      _categoryId = id;
      _applyFilter();
    });
    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final favs = _favs;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return Row(
      children: [
        SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.28).clamp(220.0, 330.0),
          child: CategoryPanel(
            section: widget.section,
            autofocusSelected: _focusItemId == null,
            selectedId: _categoryId,
            onSelect: _selectCategory,
            entries: [
              CategoryEntry(
                  id: _favId,
                  name: tr('Favorites', 'المفضلة'),
                  count: _favCount,
                  fixed: true,
                  icon: Icons.star_rounded,
                  iconColor: AppConfig.accent),
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
                    focusNode: _searchNode,
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
                    ? Center(
                        child: Text(
                          _categoryId == _favId ? tr('No favorites yet.\nHold OK on a poster to add it.', 'ما فيه مفضلة للحين.\nاضغط مطوّل على OK فوق البوستر عشان تضيفه.') : tr('Nothing here', 'لا يوجد محتوى'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppConfig.textSecondary),
                        ),
                      )
                    : LayoutBuilder(builder: (context, box) {
                        _gridWidth = box.maxWidth;
                        return Scrollbar(
                        controller: _gridScroll,
                        child: StayInList(
                          upTarget: _searchNode,
                          child: GridView.builder(
                          controller: _gridScroll,
                          padding: const EdgeInsets.all(20),
                          cacheExtent: 500,
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 180,
                            mainAxisSpacing: 18,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.56,
                          ),
                          itemCount: _visible.length,
                          itemBuilder: (context, i) {
                            final item = _visible[i];
                            return PosterCard(
                              item: item,
                              focusNode: item.id == _focusItemId ? _targetNode : null,
                              favorite: favs.contains(item.id),
                              onOpen: () => _open(item),
                              onLongPress: () => _toggleFav(item),
                            );
                          },
                        ),
                        ),
                      );
                      }),
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
  final VoidCallback onOpen;
  final VoidCallback onLongPress;
  final bool favorite;
  final bool autofocus;
  final FocusNode? focusNode;
  const PosterCard({
    this.focusNode,
    super.key,
    required this.item,
    required this.onOpen,
    required this.onLongPress,
    this.favorite = false,
    this.autofocus = false,
  });

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
      child: RemoteLongPress(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        child: InkWell(
        onTap: widget.onOpen,
        onLongPress: widget.onLongPress,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focus = f),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedScale(
                scale: _focus ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: Container(
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
                      NetImage(url: item.image, fallbackIcon: Icons.movie_outlined, cacheWidth: 300),
                      ..._watchMarks(item),
                      if (widget.favorite)
                        const Positioned(
                          top: 6,
                          left: 6,
                          child: Icon(Icons.star_rounded, size: 22, color: AppConfig.accent),
                        ),
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
    ),
    );
  }
}

/// ✓ when finished, or a thin bar showing how far it was watched.
List<Widget> _watchMarks(CatalogItem item) {
  final e = item.isSeries ? WatchHistory.lastOfSeries(item.id) : WatchHistory.get(WatchHistory.movieKey(item.id));
  if (e == null) return const [];
  return [
    if (!item.isSeries && e.done)
      const PositionedDirectional(bottom: 6, start: 6, child: WatchedBadge()),
    if (e.resumable || (item.isSeries && !e.done && e.fraction > 0))
      Positioned(left: 0, right: 0, bottom: 0, child: WatchProgressBar(fraction: e.fraction)),
  ];
}
