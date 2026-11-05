import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../data/catalog_db.dart';
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
import '../lite.dart';

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

  static CatalogItem _item(Object o) {
    final m = o as Movie;
    return CatalogItem(
      id: m.id,
      title: m.name,
      image: m.poster,
      categoryId: m.categoryId,
      rating: m.rating,
      onOpen: (ctx) => playMovie(ctx, m),
    );
  }

  @override
  Widget build(BuildContext context) => CatalogSection(
      section: 'movies',
      sec: 'vod',
      favKey: 'fav_movies',
      toItem: _item,
      allLabel: tr('All Movies', 'كل الأفلام'),
      searchHint: tr('Search movies', 'ابحث في الأفلام'));
}

// ------------------------------------------------------------ Series

class SeriesSection extends StatelessWidget {
  const SeriesSection({super.key});

  static CatalogItem _item(Object o) {
    final s = o as Series;
    return CatalogItem(
      id: s.id,
      title: s.name,
      image: s.cover,
      categoryId: s.categoryId,
      rating: s.rating,
      isSeries: true,
      onOpen: (ctx) => Navigator.of(ctx).push(
        MaterialPageRoute(builder: (_) => SeriesDetailScreen(series: s)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CatalogSection(
      section: 'series',
      sec: 'series',
      favKey: 'fav_series',
      toItem: _item,
      allLabel: tr('All Series', 'كل المسلسلات'),
      searchHint: tr('Search series', 'ابحث في المسلسلات'));
}

// ------------------------------------------------------------ shared grid

class CatalogSection extends StatefulWidget {
  final String allLabel;
  final String searchHint;
  final String section; // 'movies' / 'series' (saved places, hidden categories)
  final String sec; // 'vod' / 'series' (database)
  final String favKey;
  final CatalogItem Function(Object model) toItem;

  const CatalogSection(
      {super.key,
      required this.section,
      required this.sec,
      required this.favKey,
      required this.toItem,
      required this.allLabel,
      required this.searchHint});

  /// Set by the home screen when a page kept in the background is shown
  /// again ('movies' / 'series'): the remote goes back where it was.
  static final ValueNotifier<String?> reshown = ValueNotifier<String?>(null);
  static void reshow(String section) {
    reshown.value = null;
    reshown.value = section;
  }

  @override
  State<CatalogSection> createState() => _CatalogSectionState();
}

class _CatalogSectionState extends State<CatalogSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _gridScroll = ScrollController();

  bool _loading = true;
  String? _error;

  // Only what is on screen is read from the database (one page at a time),
  // so a section with 100 000 titles opens at once.
  List<Category> _categories = [];
  Map<String, int> _counts = {};
  int _total = 0;
  List<String> _hidden = [];
  String _categoryId = _allId;
  String _query = '';
  List<CatalogItem> _visible = [];
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _querying = false;
  int _token = 0;
  Timer? _searchDebounce;
  static const int _page = 300;

  @override
  void initState() {
    super.initState();
    _load();
    XtreamApi.listsChanged.addListener(_reloadQuietly);
    CatalogSection.reshown.addListener(_onReshown);
    FocusManager.instance.addListener(_trackFocus);
  }

  // Remembers what had the remote's focus on this page.
  final FocusNode _root = FocusNode(canRequestFocus: false, skipTraversal: true);
  FocusNode? _lastFocus;
  void _trackFocus() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && _root.hasFocus) _lastFocus = f;
  }

  void _onReshown() {
    if (CatalogSection.reshown.value != widget.section || !mounted || _loading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final f = _lastFocus;
      if (f != null && f.context != null && f.canRequestFocus) {
        f.requestFocus();
      } else if (_focusItemId != null) {
        _scrollToTarget();
      }
    });
  }

  /// A fresh list arrived in the background: show the new titles without a
  /// loading screen, staying on the same category / search.
  Future<void> _reloadQuietly() async {
    if (_loading || _error != null) return;
    try {
      await _readSummary();
      if (!mounted) return;
      if (_categoryId != _allId && _categoryId != _favId && !_categories.any((c) => c.id == _categoryId)) {
        _categoryId = _allId;
      }
      await _runQuery(keep: true);
    } catch (_) {}
  }

  @override
  void dispose() {
    XtreamApi.listsChanged.removeListener(_reloadQuietly);
    CatalogSection.reshown.removeListener(_onReshown);
    FocusManager.instance.removeListener(_trackFocus);
    _root.dispose();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _gridScroll.dispose();
    _targetNode.dispose();
    _searchNode.dispose();
    super.dispose();
  }

  String get _acc => Session.api?.account ?? '';

  Future<void> _readSummary() async {
    final sum = await CatalogReads.summary(_acc, widget.sec);
    final hidden = await CategoryFilter.hiddenIds(widget.section, sum.categories);
    _hidden = hidden.toList();
    _categories = sum.categories.where((c) => !hidden.contains(c.id)).toList();
    _counts = {for (final e in sum.counts.entries) if (!hidden.contains(e.key)) e.key: e.value};
    _total = _counts.values.fold(0, (a, b) => a + b);
    await _refreshFavCount();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await loadWithLimit(() async {
        final api = Session.api!;
        await api.ensureSaved(widget.sec); // first time: download (with %)
        XtreamApi.loadStatus.value = tr('Opening the list...', 'جاري فتح القائمة...');
        try {
          await _readSummary();
        } finally {
          XtreamApi.loadStatus.value = null;
        }
      }());
      if (!mounted) return;
      final cat = Storage.lastCatalogCategory(widget.section);
      if (cat != null && (cat == _allId || cat == _favId || _categories.any((c) => c.id == cat))) {
        _categoryId = cat;
      }
      await _runQuery(focusId: Storage.lastCatalogItem(widget.section));
      if (!mounted) return;
      setState(() => _loading = false);
      if (_focusItemId != null) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  CatalogQuery _queryFor({int offset = 0, int limit = _page}) => CatalogQuery(
        CatalogReads.path ?? '',
        _acc,
        widget.sec,
        cat: (_categoryId == _allId || _categoryId == _favId) ? null : _categoryId,
        ids: _categoryId == _favId ? _favs.toList() : null,
        search: searchNorm(_query.trim()),
        hidden: _hidden,
        offset: offset,
        limit: limit,
      );

  /// Reads the first page of what is selected. [focusId]: also make sure that
  /// poster is loaded (to put the remote on it). [keep]: keep as many
  /// posters as now (quiet refresh).
  Future<void> _runQuery({int? focusId, bool keep = false}) async {
    final token = ++_token;
    if (mounted) setState(() => _querying = true);
    try {
      var limit = keep ? (_visible.length > _page ? _visible.length : _page) : _page;
      var index = -1;
      if (focusId != null) {
        index = await CatalogReads.indexOf(_queryFor(), focusId);
        if (index >= limit) limit = index + 60;
      }
      final rows = await CatalogReads.query(_queryFor(limit: limit));
      if (!mounted || token != _token) return;
      setState(() {
        _visible = [for (final r in rows) widget.toItem(r)];
        _hasMore = rows.length >= limit;
        _focusItemId = index >= 0 ? focusId : null;
        _querying = false;
      });
    } catch (_) {
      if (mounted && token == _token) setState(() => _querying = false);
    }
  }

  /// The next page, when the remote gets near the end of what is loaded.
  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    _loadingMore = true;
    final token = _token;
    try {
      final rows = await CatalogReads.query(_queryFor(offset: _visible.length));
      if (!mounted || token != _token) return;
      setState(() {
        _visible = [..._visible, for (final r in rows) widget.toItem(r)];
        _hasMore = rows.length >= _page;
      });
    } catch (_) {
    } finally {
      _loadingMore = false;
    }
  }

  // Read once and kept in memory (re-reading it per item was very slow).
  late Set<int> _favs = _readFavs();
  int _favCount = 0;

  Set<int> _readFavs() => widget.favKey == 'fav_movies' ? Storage.favMovies : Storage.favSeries;

  Future<void> _refreshFavCount() async {
    _favs = _readFavs();
    if (_favs.isEmpty) {
      _favCount = 0;
      return;
    }
    try {
      _favCount = await CatalogReads.count(CatalogQuery(CatalogReads.path ?? '', _acc, widget.sec,
          ids: _favs.toList(), hidden: _hidden));
    } catch (_) {}
  }

  // ------------------------------------------------ back to the last place

  /// Poster to put the remote's focus on when the section opens.
  int? _focusItemId;
  final FocusNode _targetNode = FocusNode();
  final FocusNode _searchNode = FocusNode();
  double _gridWidth = 800;

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
    await _refreshFavCount();
    if (!mounted) return;
    if (_categoryId == _favId) {
      await _runQuery(keep: true);
    } else {
      setState(() {});
    }
  }

  Future<void> _toggleFav(CatalogItem item) async {
    final added = await Storage.toggleFav(widget.favKey, item.id);
    if (!mounted) return;
    showToast(context, added ? tr('★  ${item.title} added to favorites', '★  تمت إضافة ${item.title} للمفضلة') : tr('${item.title} removed from favorites', 'تمت إزالة ${item.title} من المفضلة'));
    await _refreshFavCount();
    if (!mounted) return;
    if (_categoryId == _favId) {
      await _runQuery(keep: true);
    } else {
      setState(() {});
    }
  }

  void _selectCategory(String id) {
    Storage.setLastCatalogCategory(widget.section, id);
    _focusItemId = null;
    setState(() {
      _categoryId = id;
      _visible = [];
      _hasMore = false;
    });
    if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
    _runQuery();
  }

  @override
  Widget build(BuildContext context) {
    final favs = _favs;
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    return Focus(
      focusNode: _root,
      child: Row(
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
              CategoryEntry(id: _allId, name: widget.allLabel, count: _total, fixed: true),
              ..._categories.map((c) => CategoryEntry(id: c.id, name: c.name, count: _counts[c.id] ?? 0)),
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
                    onChanged: (v) {
                      _query = v;
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                        if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
                        _runQuery();
                      });
                    },
                  ),
                ),
              ),
              Expanded(
                child: _visible.isEmpty && _querying
                    ? const Center(child: CircularProgressIndicator())
                    : _visible.isEmpty
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
                            if (i >= _visible.length - 60) _loadMore();
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
    ),
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
                duration: Lite.anim(140),
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
