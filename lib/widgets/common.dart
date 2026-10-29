import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../data/disk_cache.dart';
import '../utils.dart';
import 'tv_keyboard.dart';
import '../l10n.dart';


/// "Made by A3N" — shown top-left on every screen.
class SignatureBadge extends StatelessWidget {
  const SignatureBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fade(AppConfig.primary, 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fade(AppConfig.primary, 0.55)),
      ),
      child: const Text(
        AppConfig.signature,
        style: TextStyle(
          color: AppConfig.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class NetImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final IconData fallbackIcon;
  final int? cacheWidth;

  const NetImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.image_not_supported_outlined,
    this.cacheWidth,
  });

  @override
  State<NetImage> createState() => _NetImageState();
}

/// Image saved on the TV after the first download (see DiskCache).
class _NetImageState extends State<NetImage> {
  File? _file;
  bool _failed = false;

  bool get _valid => widget.url.isNotEmpty && widget.url.startsWith('http');

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    _failed = false;
    _file = null;
    if (!_valid) return;
    final url = widget.url;
    final saved = DiskCache.cachedImage(url);
    if (saved != null) {
      _file = saved;
      return;
    }
    DiskCache.image(url).then((f) {
      if (!mounted || widget.url != url) return;
      setState(() {
        _file = f;
        _failed = f == null;
      });
    });
  }

  Widget _fallback() => Center(
        child: Icon(widget.fallbackIcon, color: fade(AppConfig.textSecondary, 0.6), size: 22),
      );

  @override
  Widget build(BuildContext context) {
    if (!_valid || _failed) return _fallback();
    final file = _file;
    if (file == null) return const SizedBox.expand();
    return Image.file(
      file,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      // Soft fade-in instead of popping in.
      frameBuilder: (context, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 180),
          child: child,
        );
      },
      errorBuilder: (_, __, ___) {
        DiskCache.forgetImage(widget.url);
        return _fallback();
      },
    );
  }
}

class ChannelLogo extends StatelessWidget {
  final String url;
  final double size;
  const ChannelLogo({super.key, required this.url, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppConfig.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: NetImage(url: url, fit: BoxFit.contain, fallbackIcon: Icons.tv_rounded, cacheWidth: (size * 2).round()),
    );
  }
}

class SelectableRow extends StatefulWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double height;
  final bool autofocus;
  final VoidCallback? onLongPress;

  /// Long names (categories) can use a second line instead of being cut.
  final int titleMaxLines;
  final double titleSize;

  /// Change this number to pull the remote's focus back onto this row.
  final int? refocusTick;

  const SelectableRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.height = 48,
    this.autofocus = false,
    this.onLongPress,
    this.refocusTick,
    this.titleMaxLines = 1,
    this.titleSize = 14,
  });

  @override
  State<SelectableRow> createState() => _SelectableRowState();
}

class _SelectableRowState extends State<SelectableRow> {
  // Each row owns its focus node for its whole life, so the focus never jumps
  // to another row when the playing channel changes.
  final FocusNode _node = FocusNode();
  bool _focused = false;

  @override
  void didUpdateWidget(covariant SelectableRow old) {
    super.didUpdateWidget(old);
    if (widget.refocusTick != null && widget.refocusTick != old.refocusTick) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final edge = _focused ? AppConfig.textPrimary : (selected ? AppConfig.primary : Colors.transparent);
    return RemoteLongPress(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Material(
      color: _focused
          ? fade(AppConfig.primary, 0.34)
          : (selected ? fade(AppConfig.primary, 0.08) : Colors.transparent),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        focusNode: _node,
        autofocus: widget.autofocus,
        onFocusChange: (f) => setState(() => _focused = f),
        focusColor: Colors.transparent,
        hoverColor: fade(AppConfig.textPrimary, 0.05),
        child: Container(
          height: widget.height,
          padding: const EdgeInsetsDirectional.only(start: 12, end: 6),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: edge, width: 3)),
          ),
          child: Row(
            children: [
              if (widget.leading != null) widget.leading!,
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: widget.titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.titleSize,
                        height: widget.titleMaxLines > 1 ? 1.2 : null,
                        color: selected || _focused ? AppConfig.textPrimary : fade(AppConfig.textPrimary, 0.88),
                        fontWeight: selected || _focused ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppConfig.primary),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class CountLabel extends StatelessWidget {
  final int count;
  const CountLabel(this.count, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Text('$count', style: const TextStyle(fontSize: 12, color: AppConfig.textSecondary)),
      );
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  const RoundIconButton({super.key, required this.icon, required this.tooltip, required this.onTap, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: fade(Colors.black, 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 46, color: AppConfig.textSecondary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppConfig.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Retry', 'إعادة المحاولة'))),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const SearchField({super.key, required this.hint, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

class ClockText extends StatefulWidget {
  const ClockText({super.key});
  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        fmtTime(DateTime.now()),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppConfig.textPrimary),
      );
}

/// Search for the TV: a focusable button that opens the on-screen keyboard in
/// a dialog, so moving through the list with the remote never pops a keyboard.
class TvSearchButton extends StatefulWidget {
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  const TvSearchButton({super.key, required this.hint, required this.controller, required this.onChanged, this.focusNode});

  @override
  State<TvSearchButton> createState() => _TvSearchButtonState();
}

class _TvSearchButtonState extends State<TvSearchButton> {
  bool _focused = false;

  Future<void> _open() async {
    final before = widget.controller.text;
    var latest = before;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TvKeyboardDialog(
        title: widget.hint,
        initial: before,
        // Results update behind the dialog while typing.
        onChanged: (v) {
          latest = v;
          widget.onChanged(v.trim());
        },
      ),
    );
    // BACK keeps what was typed; Search / Clear return it.
    final text = (result ?? latest).trim();
    widget.controller.text = text;
    widget.onChanged(text);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.controller.text;
    // ▲ on the search box (top of its column) stays here.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) => e.logicalKey == LogicalKeyboardKey.arrowUp ? KeyEventResult.handled : KeyEventResult.ignored,
      child: Material(
      color: _focused ? fade(AppConfig.primary, 0.28) : AppConfig.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        focusNode: widget.focusNode,
        borderRadius: BorderRadius.circular(10),
        focusColor: Colors.transparent,
        onFocusChange: (f) => setState(() => _focused = f),
        onTap: _open,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _focused ? AppConfig.textPrimary : Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, size: 20, color: AppConfig.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.isEmpty ? widget.hint : q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: q.isEmpty ? AppConfig.textSecondary : AppConfig.textPrimary),
                ),
              ),
              if (q.isNotEmpty) const Icon(Icons.filter_alt_rounded, size: 18, color: AppConfig.primary),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// ☆ Favorite / ★ Favorited — outlined button with a clear focus ring for the remote.
class FavoriteButton extends StatelessWidget {
  final bool active;
  final VoidCallback onPressed;
  const FavoriteButton({super.key, required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(active ? Icons.star_rounded : Icons.star_outline_rounded,
          color: active ? AppConfig.accent : AppConfig.textPrimary),
      label: Text(active ? tr('Favorited', 'في المفضلة') : tr('Favorite', 'أضف للمفضلة'),
          style: TextStyle(color: active ? AppConfig.accent : AppConfig.textPrimary)),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(150, 50)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.focused) ? AppConfig.textPrimary : AppConfig.divider,
            width: s.contains(WidgetState.focused) ? 3 : 1.5,
          ),
        ),
        overlayColor: WidgetStatePropertyAll(fade(AppConfig.primary, 0.18)),
      ),
    );
  }
}


/// Short press of OK = [onTap], hold OK for ~0.6 s = [onLongPress].
/// Works with the TV remote (and with touch / mouse via the child InkWell).
class RemoteLongPress extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  const RemoteLongPress({super.key, required this.onTap, required this.onLongPress, required this.child});

  static bool _swallow = false;

  /// Placed around the whole app (main.dart): eats the rest of a held OK
  /// press after a long press fired.
  static KeyEventResult guard(FocusNode node, KeyEvent e) {
    if (!_swallow) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.select &&
        k != LogicalKeyboardKey.enter &&
        k != LogicalKeyboardKey.numpadEnter &&
        k != LogicalKeyboardKey.gameButtonA) {
      return KeyEventResult.ignored;
    }
    // A new press: the old one is over (its release may have gone elsewhere).
    if (e is KeyDownEvent) {
      _swallow = false;
      return KeyEventResult.ignored;
    }
    if (e is KeyUpEvent) _swallow = false;
    return KeyEventResult.handled;
  }

  @override
  State<RemoteLongPress> createState() => _RemoteLongPressState();
}

class _RemoteLongPressState extends State<RemoteLongPress> {
  static final _keys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };
  Timer? _timer;
  bool _down = false;
  bool _fired = false;

  // After a long press, ignore OK until the button is let go. Otherwise, when
  // the item disappears (e.g. removed from Favorites), the still-held button
  // would "press" the next item that gets the focus.
  static void _swallowUntilRelease() => RemoteLongPress._swallow = true;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (widget.onLongPress == null || !_keys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _down = true;
      _fired = false;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 600), () {
        if (_down && !_fired) {
          _fired = true;
          _swallowUntilRelease();
          HapticFeedback.mediumImpact();
          widget.onLongPress?.call();
        }
      });
      return KeyEventResult.handled;
    }
    if (e is KeyRepeatEvent) return _down ? KeyEventResult.handled : KeyEventResult.ignored;
    if (e is KeyUpEvent) {
      if (!_down) return KeyEventResult.ignored;
      _timer?.cancel();
      RemoteLongPress._swallow = false; // released on the same item
      final tap = !_fired;
      _down = false;
      if (tap) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: widget.child,
      );
}

/// Small confirmation at the bottom of the screen.
void showToast(BuildContext context, String text) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(text), duration: const Duration(milliseconds: 1600)));
}

/// Keeps the remote's focus inside a list / grid: pressing ▼ on the last item
/// does nothing instead of jumping to another panel.
class StayInList extends StatelessWidget {
  final Widget child;

  /// Where ▲ goes from the top of the list (e.g. the search box above it).
  final FocusNode? upTarget;

  /// ▲ on the first item stays there (lists side by side, like categories).
  /// Off by default, so ▲ can still reach things above (e.g. seasons).
  final bool stopAtTop;
  const StayInList({super.key, required this.child, this.upTarget, this.stopAtTop = false});

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, e) {
          if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
            return (stopAtTop || upTarget != null) ? _up(node, e) : KeyEventResult.ignored;
          }
          if (e.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
          final cur = FocusManager.instance.primaryFocus;
          final ctx = cur?.context;
          if (cur == null || ctx == null) return KeyEventResult.ignored;
          try {
            final r = cur.rect;
            // Another item further down (already built)? Then move normally.
            final below = node.traversalDescendants.any((d) => d != cur && d.canRequestFocus && d.rect.top >= r.bottom - 2);
            if (below) return KeyEventResult.ignored;
            // More items still to come when scrolling? Then move normally.
            final pos = Scrollable.maybeOf(ctx)?.position;
            if (pos != null && pos.pixels < pos.maxScrollExtent - 1) return KeyEventResult.ignored;
          } catch (_) {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled; // last item: stay here
        },
        child: child,
      );

  /// ▲ on the first item: go to [upTarget] or stay, never jump to another list.
  KeyEventResult _up(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final cur = FocusManager.instance.primaryFocus;
    final ctx = cur?.context;
    if (cur == null || ctx == null) return KeyEventResult.ignored;
    try {
      final r = cur.rect;
      // Another item further up (already built)? Then move normally.
      final above = node.traversalDescendants.any((d) => d != cur && d.canRequestFocus && d.rect.bottom <= r.top + 2);
      if (above) return KeyEventResult.ignored;
      // More items above when scrolling back? Then move normally.
      final pos = Scrollable.maybeOf(ctx)?.position;
      if (pos != null && pos.pixels > pos.minScrollExtent + 1) return KeyEventResult.ignored;
    } catch (_) {
      return KeyEventResult.ignored;
    }
    final t = upTarget;
    if (e is KeyDownEvent && t != null && t.canRequestFocus) t.requestFocus();
    return KeyEventResult.handled;
  }
}

/// Thin bar at the bottom of a poster / thumbnail: how much was watched.
class WatchProgressBar extends StatelessWidget {
  final double fraction;
  const WatchProgressBar({super.key, required this.fraction});

  @override
  Widget build(BuildContext context) => Container(
        height: 5,
        color: fade(Colors.black, 0.55),
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.03, 1.0),
          heightFactor: 1,
          child: const ColoredBox(color: AppConfig.primary),
        ),
      );
}

/// "✓ Watched" mark.
class WatchedBadge extends StatelessWidget {
  final bool compact;
  const WatchedBadge({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 3),
        decoration: BoxDecoration(
          color: fade(Colors.black, 0.72),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: fade(AppConfig.primary, 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 14, color: AppConfig.primary),
            if (!compact) ...[
              const SizedBox(width: 3),
              Text(tr('Watched', 'تمت المشاهدة'),
                  style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );
}

/// Clear white frame around whatever inside has the remote's focus
/// (for list tiles, chips and buttons whose own highlight is too faint).
class FocusRing extends StatefulWidget {
  final Widget child;
  final double radius;
  const FocusRing({super.key, required this.child, this.radius = 10});

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          if (f != _focused) setState(() => _focused = f);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _focused ? fade(AppConfig.primary, 0.20) : Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: _focused ? AppConfig.textPrimary : Colors.transparent, width: 2.5),
          ),
          child: widget.child,
        ),
      );
}
