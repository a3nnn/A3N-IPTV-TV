import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../utils.dart';

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

class NetImage extends StatelessWidget {
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

  Widget _fallback() => Center(
        child: Icon(fallbackIcon, color: fade(AppConfig.textSecondary, 0.6), size: 22),
      );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty || !url.startsWith('http')) return _fallback();
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => _fallback(),
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
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: edge, width: 3)),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
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
        padding: const EdgeInsets.only(right: 8),
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
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
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
  const TvSearchButton({super.key, required this.hint, required this.controller, required this.onChanged});

  @override
  State<TvSearchButton> createState() => _TvSearchButtonState();
}

class _TvSearchButtonState extends State<TvSearchButton> {
  bool _focused = false;

  Future<void> _open() async {
    final temp = TextEditingController(text: widget.controller.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConfig.surface,
        title: Text(widget.hint),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: temp,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => Navigator.pop(ctx, v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Clear')),
          FilledButton(onPressed: () => Navigator.pop(ctx, temp.text), child: const Text('Search')),
        ],
      ),
    );
    if (result == null) return;
    widget.controller.text = result.trim();
    widget.onChanged(result.trim());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.controller.text;
    return Material(
      color: _focused ? fade(AppConfig.primary, 0.28) : AppConfig.surfaceHigh,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
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
      label: Text(active ? 'Favorited' : 'Favorite',
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
