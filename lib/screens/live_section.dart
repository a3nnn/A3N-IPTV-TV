import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/storage.dart';
import '../data/xtream_api.dart';
import '../player/player_service.dart';
import '../utils.dart';
import '../widgets/category_panel.dart';
import '../widgets/common.dart';

const String _favId = '__fav';
const String _allId = '__all';

class LiveSection extends StatefulWidget {
  const LiveSection({super.key});
  @override
  State<LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends State<LiveSection> {
  static const double _rowHeight = 60;

  final PlayerService _svc = PlayerService.instance;
  final ScrollController _channelScroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _fsFocus = FocusNode();
  // Keeps ONE video surface alive when moving between preview and full screen
  // (re-creating it is what caused the freeze when enlarging).
  final GlobalKey _videoKey = GlobalKey();
  // Bumped when leaving full screen so the playing channel's row takes focus again.
  int _refocusTick = 0;

  bool _loading = true;
  String? _error;
  List<Category> _categories = [];
  List<LiveChannel> _all = [];
  Map<String, int> _counts = {};
  Set<int> _favorites = {};
  String _categoryId = _allId;
  String _query = '';
  List<LiveChannel> _visible = [];

  LiveChannel? _current;
  List<EpgEntry> _epg = [];
  bool _epgLoading = false;

  Timer? _ticker;
  Timer? _zapTimer;
  final ValueNotifier<int> _clock = ValueNotifier<int>(0);
  int _favCount = 0;
  Timer? _overlayTimer;
  bool _overlay = true;

  bool get _fullscreen => _svc.fullscreen.value;

  @override
  void initState() {
    super.initState();
    _favorites = Storage.favorites;
    _svc.exitFullscreen.addListener(_onExitRequest);
    // Only the program-guide parts listen to this, not the whole screen.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _clock.value++);
    _load();
  }

  @override
  void dispose() {
    _svc.exitFullscreen.removeListener(_onExitRequest);
    _ticker?.cancel();
    _zapTimer?.cancel();
    _clock.dispose();
    _overlayTimer?.cancel();
    _channelScroll.dispose();
    _searchCtrl.dispose();
    _fsFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ data

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = Session.api!;
      final results = await Future.wait<Object>([api.liveCategories(), api.liveStreams()]);
      final cats = results[0] as List<Category>;
      final chans = results[1] as List<LiveChannel>;
      final counts = <String, int>{};
      for (final c in chans) {
        counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _all = chans;
        _counts = counts;
        _favCount = chans.where((c) => _favorites.contains(c.id)).length;
        _loading = false;
      });
      _restoreLast();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _restoreLast() {
    final lastCat = Storage.lastCategory;
    if (lastCat != null &&
        (lastCat == _favId || lastCat == _allId || _categories.any((c) => c.id == lastCat))) {
      _categoryId = lastCat;
    }
    _applyFilter();

    final lastId = Storage.lastChannel;
    LiveChannel? channel;
    if (lastId != null) {
      for (final c in _all) {
        if (c.id == lastId) {
          channel = c;
          break;
        }
      }
    }
    if (channel != null) {
      _select(channel, scroll: true, play: Storage.previewEnabled);
    } else {
      setState(() {});
    }
  }

  void _applyFilter() {
    Iterable<LiveChannel> list;
    if (_categoryId == _favId) {
      list = _all.where((c) => _favorites.contains(c.id));
    } else if (_categoryId == _allId) {
      list = _all;
    } else {
      list = _all.where((c) => c.categoryId == _categoryId);
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) list = list.where((c) => c.name.toLowerCase().contains(q));
    _visible = list.toList();
  }

  void _selectCategory(String id) {
    setState(() {
      _categoryId = id;
      _applyFilter();
    });
    if (_channelScroll.hasClients) _channelScroll.jumpTo(0);
  }

  /// [delay] > 0 is used while zapping: the name/logo change at once, the
  /// stream only opens when the user stops on a channel.
  Future<void> _select(LiveChannel ch,
      {bool scroll = false, bool play = true, Duration delay = Duration.zero}) async {
    setState(() {
      _current = ch;
      _epg = [];
      _epgLoading = true;
    });
    if (scroll) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(ch));
    _showOverlay();
    _zapTimer?.cancel();
    if (delay > Duration.zero) {
      _zapTimer = Timer(delay, () => _start(ch, play));
    } else {
      await _start(ch, play);
    }
  }

  Future<void> _start(LiveChannel ch, bool play) async {
    if (!mounted || _current?.id != ch.id) return;
    Storage.setLastChannel(ch.id);
    Storage.setLastCategory(_categoryId);
    if (play) _svc.play(Session.api!.liveUrl(ch));
    try {
      final epg = await Session.api!.shortEpg(ch.id);
      if (!mounted || _current?.id != ch.id) return;
      setState(() {
        _epg = epg;
        _epgLoading = false;
      });
    } catch (_) {
      if (!mounted || _current?.id != ch.id) return;
      setState(() => _epgLoading = false);
    }
  }

  void _scrollTo(LiveChannel ch) {
    final i = _visible.indexWhere((c) => c.id == ch.id);
    if (i < 0 || !_channelScroll.hasClients) return;
    final max = _channelScroll.position.maxScrollExtent;
    _channelScroll.jumpTo((i * _rowHeight - 140).clamp(0.0, max));
  }

  void _zap(int delta) {
    if (_visible.isEmpty) return;
    var i = _current == null ? -1 : _visible.indexWhere((c) => c.id == _current!.id);
    i = (i + delta) % _visible.length;
    if (i < 0) i += _visible.length;
    _select(_visible[i], scroll: true, delay: const Duration(milliseconds: 450));
  }

  void _toggleFavorite(LiveChannel c) {
    setState(() {
      if (_favorites.remove(c.id)) {
        _favCount--;
      } else {
        _favorites.add(c.id);
        _favCount++;
      }
      if (_categoryId == _favId) _applyFilter();
    });
    Storage.setFavorites(_favorites);
  }

  EpgEntry? get _now {
    final t = DateTime.now();
    for (final e in _epg) {
      if (e.isLiveAt(t)) return e;
    }
    return null;
  }

  List<EpgEntry> get _upcoming {
    final t = DateTime.now();
    return _epg.where((e) => e.start.isAfter(t)).toList();
  }

  // ------------------------------------------------------------ fullscreen

  Future<void> _setFullscreen(bool value) async {
    if (_current == null && value) return;
    if (!value && !Storage.previewEnabled) _svc.stop();
    _svc.fullscreen.value = value;
    setState(() {});
    if (value) {
      _showOverlay();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fsFocus.requestFocus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current != null) _scrollTo(_current!);
        if (mounted) setState(() => _refocusTick++);
      });
    }
  }

  void _onExitRequest() {
    if (mounted && _fullscreen) _setFullscreen(false);
  }

  void _showOverlay() {
    _overlayTimer?.cancel();
    if (!_overlay && mounted) setState(() => _overlay = true);
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _overlay = false);
    });
  }

  KeyEventResult _onFullscreenKey(FocusNode node, KeyEvent event) {
    final k = event.logicalKey;
    // BACK: swallow the whole press and act when the button is RELEASED.
    // (Acting on press let Android see the release as a second BACK = app closed.)
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.backspace) {
      if (event is KeyUpEvent && _fullscreen) _setFullscreen(false);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp || k == LogicalKeyboardKey.pageUp) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown || k == LogicalKeyboardKey.pageDown) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.space) {
      _showOverlay();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    // Remote BACK in full screen returns to the list instead of leaving the app.
    return Container(
      child: _fullscreen
          ? _buildFullscreen()
          : LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth;
                return Row(
                  children: [
                    SizedBox(width: (w * 0.24).clamp(180.0, 250.0), child: RepaintBoundary(child: _buildCategories())),
                    const VerticalDivider(width: 1),
                    SizedBox(width: (w * 0.38).clamp(260.0, 390.0), child: RepaintBoundary(child: _buildChannels())),
                    const VerticalDivider(width: 1),
                    Expanded(child: RepaintBoundary(child: _buildPreview())),
                  ],
                );
              },
            ),
    );
  }

  Widget _video() => Video(key: _videoKey, controller: _svc.controller, controls: NoVideoControls, fill: Colors.black);

  Widget _buildCategories() {
    final favCount = _favCount;
    return CategoryPanel(
      section: 'live',
      autofocusSelected: _current == null,
      selectedId: _categoryId,
      onSelect: _selectCategory,
      entries: [
        CategoryEntry(
            id: _favId, name: 'Favorites', count: favCount, fixed: true,
            icon: Icons.star_rounded, iconColor: AppConfig.accent),
        CategoryEntry(id: _allId, name: 'All Channels', count: _all.length, fixed: true),
        ..._categories.map((c) => CategoryEntry(id: c.id, name: c.name, count: _counts[c.id] ?? 0)),
      ],
    );
  }

  Widget _buildChannels() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TvSearchButton(
            hint: 'Search channels',
            controller: _searchCtrl,
            onChanged: (v) => setState(() {
              _query = v;
              _applyFilter();
            }),
          ),
        ),
        Expanded(
          child: _visible.isEmpty
              ? Center(
                  child: Text(
                    _categoryId == _favId
                        ? 'No favorites yet.\nHold OK on a channel to add it.'
                        : 'No channels found',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppConfig.textSecondary),
                  ),
                )
              : Scrollbar(
                  controller: _channelScroll,
                  child: ListView.builder(
                    controller: _channelScroll,
                    itemExtent: _rowHeight,
                    cacheExtent: _rowHeight * 8,
                    itemCount: _visible.length,
                    itemBuilder: (context, i) => _channelRow(_visible[i], i),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _channelRow(LiveChannel c, int index) {
    final selected = c.id == _current?.id;
    final fav = _favorites.contains(c.id);
    return SelectableRow(
      key: ValueKey('ch-${c.id}'),
      height: _rowHeight,
      selected: selected,
      autofocus: selected,
      refocusTick: selected ? _refocusTick : null,
      onTap: () {
        if (!Storage.previewEnabled) {
          // Light mode: no preview, open the channel full screen right away.
          _select(c).then((_) => _setFullscreen(true));
        } else if (selected) {
          _setFullscreen(true);
        } else {
          _select(c);
        }
      },
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            child: selected
                ? const Icon(Icons.play_arrow_rounded, size: 22, color: AppConfig.primary)
                : Text(
                    '${c.number > 0 ? c.number : index + 1}',
                    style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary),
                  ),
          ),
          ChannelLogo(url: c.logo, size: 40),
          const SizedBox(width: 12),
        ],
      ),
      title: c.name,
      subtitle: selected ? _now?.title : null,
      onLongPress: () {
        _toggleFavorite(c);
        showToast(context, _favorites.contains(c.id) ? '★  ${c.name} added to favorites' : '${c.name} removed from favorites');
      },
      trailing: fav
          ? const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(Icons.star_rounded, size: 18, color: AppConfig.accent),
            )
          : null,
    );
  }

  Widget _buildPreview() {
    final ch = _current;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, box) {
          var w = box.maxWidth;
          var h = w * 9 / 16;
          final maxH = box.maxHeight * 0.58;
          if (h > maxH) {
            h = maxH;
            w = h * 16 / 9;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: w,
                height: h,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: ch == null
                        ? _emptyPreview()
                        : (Storage.previewEnabled ? _previewPlayer() : _previewOff(ch)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (ch != null) ...[
                Row(
                  children: [
                    ChannelLogo(url: ch.logo, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _clock,
                    builder: (_, __, ___) => _buildEpg(),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _previewOff(LiveChannel ch) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelLogo(url: ch.logo, size: 72),
            const SizedBox(height: 12),
            const Text('Press OK to watch', style: TextStyle(color: AppConfig.textSecondary)),
          ],
        ),
      );

  Widget _emptyPreview() => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv_rounded, size: 48, color: AppConfig.textSecondary),
            SizedBox(height: 10),
            Text('Select a channel', style: TextStyle(color: AppConfig.textSecondary)),
          ],
        ),
      );

  Widget _previewPlayer() {
    return GestureDetector(
      onDoubleTap: () => _setFullscreen(true),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _video(),
          _bufferingIndicator(),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoundIconButton(
                  icon: Icons.fullscreen_rounded,
                  tooltip: 'Full screen',
                  onTap: () => _setFullscreen(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bufferingIndicator() => StreamBuilder<bool>(
        stream: _svc.player.stream.buffering,
        initialData: _svc.player.state.buffering,
        builder: (context, snap) => snap.data == true
            ? const Center(child: CircularProgressIndicator())
            : const SizedBox.shrink(),
      );

  Widget _buildEpg() {
    if (_epgLoading) {
      return const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final now = _now;
    final next = _upcoming;
    if (now == null && next.isEmpty) {
      return const Text('No program guide for this channel', style: TextStyle(color: AppConfig.textSecondary));
    }
    return ListView(
      children: [
        if (now != null) _NowCard(entry: now),
        for (final e in next.take(8)) _EpgRow(entry: e),
      ],
    );
  }

  Widget _buildFullscreen() {
    final ch = _current;
    final now = _now;
    final next = _upcoming;
    return Focus(
      focusNode: _fsFocus,
      autofocus: true,
      onKeyEvent: _onFullscreenKey,
      child: MouseRegion(
        onHover: (_) => _showOverlay(),
        child: GestureDetector(
          onTap: _showOverlay,
          onDoubleTap: () => _setFullscreen(false),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              _video(),
              _bufferingIndicator(),
              AnimatedOpacity(
                opacity: _overlay ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: IgnorePointer(
                  ignoring: !_overlay,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [fade(Colors.black, 0.75), Colors.transparent],
                            ),
                          ),
                          child: Row(
                            children: [
                              const SignatureBadge(),
                              const Spacer(),
                              const ClockText(),
                              const SizedBox(width: 18),
                              Text(
                                '▲ ▼  channel     OK  info     BACK  exit',
                                style: TextStyle(fontSize: 12, color: fade(Colors.white, 0.6)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (ch != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(28, 60, 28, 26),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [fade(Colors.black, 0.88), Colors.transparent],
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                ChannelLogo(url: ch.logo, size: 64),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${ch.number > 0 ? '${ch.number}   ' : ''}${ch.name}',
                                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                      if (now != null) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          '${fmtTime(now.start)} - ${fmtTime(now.end)}   ${now.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 15, color: Colors.white),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: 420,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: now.progressAt(DateTime.now()),
                                              minHeight: 4,
                                              backgroundColor: fade(Colors.white, 0.2),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (next.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          'Next  ${fmtTime(next.first.start)}   ${next.first.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 13, color: fade(Colors.white, 0.7)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  final EpgEntry entry;
  const _NowCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConfig.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppConfig.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppConfig.primary, borderRadius: BorderRadius.circular(4)),
                child: const Text('NOW',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black)),
              ),
              const SizedBox(width: 10),
              Text('${fmtTime(entry.start)} - ${fmtTime(entry.end)}',
                  style: const TextStyle(fontSize: 13, color: AppConfig.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: entry.progressAt(DateTime.now()),
              minHeight: 4,
              backgroundColor: AppConfig.surfaceHigh,
            ),
          ),
          if (entry.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppConfig.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _EpgRow extends StatelessWidget {
  final EpgEntry entry;
  const _EpgRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(fmtTime(entry.start), style: const TextStyle(fontSize: 13, color: AppConfig.textSecondary)),
          ),
          Expanded(
            child: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
