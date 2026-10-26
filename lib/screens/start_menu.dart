import 'package:flutter/material.dart';

import '../config.dart';
import '../data/watch_history.dart';
import '../l10n.dart';
import '../utils.dart';
import '../widgets/common.dart';
import 'playback.dart';

/// First screen: Live TV (wide) on top, then Series / Movies / Settings,
/// plus "Continue watching" for movies and episodes left half-way.
class StartMenu extends StatefulWidget {
  final ValueChanged<int> onSelect;
  const StartMenu({super.key, required this.onSelect});

  @override
  State<StartMenu> createState() => _StartMenuState();
}

class _StartMenuState extends State<StartMenu> {
  List<WatchEntry> _continue = WatchHistory.continueList();

  Future<void> _resume(WatchEntry e) async {
    await resumeEntry(context, e);
    if (mounted) setState(() => _continue = WatchHistory.continueList());
  }

  void _remove(WatchEntry e) {
    WatchHistory.remove(e.key);
    setState(() => _continue = WatchHistory.continueList());
    showToast(context, tr('Removed from Continue watching', 'تمت الإزالة من تابع المشاهدة'));
  }

  @override
  Widget build(BuildContext context) {
    // Live TV on its own wide row; under it Series, Movies, Settings
    // (right → left in Arabic, left → right in English).
    final small = [
      (2, Icons.video_library_rounded, tr('Series', 'المسلسلات')),
      (1, Icons.movie_rounded, tr('Movies', 'الأفلام')),
      (3, Icons.settings_rounded, tr('Settings', 'الإعدادات')),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 22, 40, 24),
      children: [
        _MenuTile(
          icon: Icons.live_tv_rounded,
          label: tr('Live TV', 'البث المباشر'),
          height: 150,
          big: true,
          autofocus: true, // the remote always starts on Live TV
          onTap: () => widget.onSelect(0),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (var i = 0; i < small.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(
                child: _MenuTile(
                  icon: small[i].$2,
                  label: small[i].$3,
                  height: 104,
                  onTap: () => widget.onSelect(small[i].$1),
                ),
              ),
            ],
          ],
        ),
        if (_continue.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(tr('Continue watching', 'تابع المشاهدة'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: _continue.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) => _ContinueCard(
                entry: _continue[i],
                onTap: () => _resume(_continue[i]),
                onLongPress: () => _remove(_continue[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MenuTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool autofocus;
  final VoidCallback onTap;
  final double height;
  final bool big;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.height = 160,
    this.big = false,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _focused && !widget.big ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: _focused ? fade(AppConfig.primary, 0.22) : AppConfig.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          autofocus: widget.autofocus,
          focusColor: Colors.transparent,
          onFocusChange: (f) => setState(() => _focused = f),
          onTap: widget.onTap,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _focused ? AppConfig.primary : AppConfig.divider, width: _focused ? 3 : 1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: widget.big ? 64 : 40, color: _focused ? AppConfig.primary : AppConfig.textPrimary),
                SizedBox(height: widget.big ? 12 : 8),
                Text(widget.label,
                    style: TextStyle(fontSize: widget.big ? 24 : 18, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueCard extends StatefulWidget {
  final WatchEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ContinueCard({required this.entry, required this.onTap, required this.onLongPress});

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final image = e.isEpisode && e.seriesCover.isNotEmpty ? e.seriesCover : e.image;
    final title = e.isEpisode ? e.seriesName : e.title;
    final sub = e.isEpisode ? '${tr('S', 'م')}${e.season}  ·  ${tr('E', 'ح')}${e.episodeNum}' : null;
    return SizedBox(
      width: 112,
      child: RemoteLongPress(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          onFocusChange: (f) => setState(() => _focused = f),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _focused ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 140),
                child: Container(
                  height: 156,
                  decoration: BoxDecoration(
                    color: AppConfig.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _focused ? AppConfig.textPrimary : Colors.transparent, width: 3),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(url: image, fallbackIcon: Icons.movie_outlined, cacheWidth: 260),
                        const Center(child: Icon(Icons.play_circle_fill_rounded, size: 40, color: Colors.white70)),
                        Positioned(left: 0, right: 0, bottom: 0, child: WatchProgressBar(fraction: e.fraction)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              if (sub != null)
                Text(sub, style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
