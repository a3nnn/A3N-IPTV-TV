import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../utils.dart';
import '../l10n.dart';

const _en = ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'];
const _ar = ['1234567890', 'ضصثقفغعهخحج', 'شسيبلاتنمكط', 'ئءؤرىةوزظدذ'];

/// Search box with the app's own on-screen keyboard, moved with the remote.
/// (Works on every TV, whatever keyboard the TV itself has.)
/// Returns the text when Search / Clear is pressed, null on BACK.
class TvKeyboardDialog extends StatefulWidget {
  final String title;
  final String initial;
  final ValueChanged<String> onChanged;
  const TvKeyboardDialog({super.key, required this.title, required this.initial, required this.onChanged});

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  late String _text = widget.initial;
  late bool _arabic = widget.initial.isEmpty ? L.isAr : RegExp('[؀-ۿ]').hasMatch(widget.initial);

  void _set(String v) {
    setState(() => _text = v);
    widget.onChanged(v);
  }

  void _type(String c) {
    if (_text.length >= 60) return;
    _set(_text + c);
  }

  void _backspace() {
    if (_text.isEmpty) return;
    final chars = _text.characters;
    _set(chars.take(chars.length - 1).toString());
  }

  /// A real keyboard (Bluetooth / USB) also works.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace || e.logicalKey == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 32 && ch.codeUnitAt(0) != 127) {
      _type(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _arabic ? _ar : _en;
    return Dialog(
      backgroundColor: AppConfig.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppConfig.surfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppConfig.primary, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: AppConfig.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _text.isEmpty ? tr('Type with the keys below', 'اكتب باستخدام الأزرار تحت') : '$_text|',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            color: _text.isEmpty ? AppConfig.textSecondary : AppConfig.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var r = 0; r < rows.length; r++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      textDirection: TextDirection.ltr,
                      children: [
                        for (final c in rows[r].characters)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: _Key(
                              label: c,
                              width: 48,
                              autofocus: r == 1 && c == rows[1].characters.first,
                              onTap: () => _type(c),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    _Key(label: _arabic ? 'ABC' : 'عربي', width: 80, onTap: () => setState(() => _arabic = !_arabic)),
                    const SizedBox(width: 6),
                    Expanded(child: _Key(icon: Icons.space_bar_rounded, onTap: () => _type(' '))),
                    const SizedBox(width: 6),
                    _Key(icon: Icons.backspace_outlined, width: 70, onTap: _backspace),
                    const SizedBox(width: 6),
                    _Key(label: tr('Clear', 'مسح'), width: 80, onTap: () => _set('')),
                    const SizedBox(width: 6),
                    _Key(
                      label: tr('Search', 'بحث'),
                      width: 110,
                      primary: true,
                      onTap: () => Navigator.of(context).pop(_text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final double? width;
  final bool autofocus;
  final bool primary;
  final VoidCallback onTap;
  const _Key({this.label, this.icon, this.width, this.autofocus = false, this.primary = false, required this.onTap});

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bg = _focused
        ? AppConfig.primary
        : (widget.primary ? fade(AppConfig.primary, 0.35) : AppConfig.surfaceHigh);
    final fg = _focused ? Colors.black : AppConfig.textPrimary;
    return SizedBox(
      width: widget.width,
      height: 44,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          autofocus: widget.autofocus,
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          onFocusChange: (f) => setState(() => _focused = f),
          onTap: widget.onTap,
          child: Center(
            child: widget.icon != null
                ? Icon(widget.icon, size: 22, color: fg)
                : Text(widget.label ?? '',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg)),
          ),
        ),
      ),
    );
  }
}
