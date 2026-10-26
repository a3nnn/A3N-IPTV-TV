import 'package:flutter/material.dart';

import '../config.dart';
import '../data/storage.dart';
import '../l10n.dart';
import '../utils.dart';

/// Subtitle look chosen in Settings (or in the player's ▼ menu).
class SubStyle {
  static const Map<String, Color> colors = {
    'white': Color(0xFFFFFFFF),
    'yellow': Color(0xFFFFE14D),
    'cyan': Color(0xFF5EE7F2),
    'green': Color(0xFF8CF29B),
  };
  static const Map<String, double> sizes = {'s': 32, 'm': 42, 'l': 54};
  static const List<double> opacities = [0.25, 0.5, 0.75];

  /// Bumped on every change so an open player redraws its subtitles.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static TextStyle textStyle() {
    final bg = Storage.subBackground;
    return TextStyle(
      fontSize: sizes[Storage.subSize] ?? 42,
      height: 1.35,
      color: colors[Storage.subColor] ?? Colors.white,
      fontWeight: FontWeight.w600,
      backgroundColor: bg ? fade(Colors.black, Storage.subBgOpacity) : null,
      shadows: bg
          ? null
          : const [Shadow(blurRadius: 6, color: Colors.black), Shadow(blurRadius: 2, color: Colors.black)],
    );
  }

  static String colorName(String k) => switch (k) {
        'yellow' => tr('Yellow', 'أصفر'),
        'cyan' => tr('Cyan', 'سماوي'),
        'green' => tr('Green', 'أخضر'),
        _ => tr('White', 'أبيض'),
      };

  static String sizeName(String k) => switch (k) {
        's' => tr('Small', 'صغير'),
        'l' => tr('Large', 'كبير'),
        _ => tr('Medium', 'متوسط'),
      };
}

/// Color / size / background / opacity choices. Used in Settings and in the
/// player's subtitles menu; [onChanged] is called after every change.
class SubStylePicker extends StatefulWidget {
  final VoidCallback? onChanged;
  final bool compact;
  const SubStylePicker({super.key, this.onChanged, this.compact = false});

  @override
  State<SubStylePicker> createState() => _SubStylePickerState();
}

class _SubStylePickerState extends State<SubStylePicker> {
  void _apply(Future<void> Function() save) async {
    await save();
    if (!mounted) return;
    setState(() {});
    SubStyle.changed.value++;
    widget.onChanged?.call();
  }

  Widget _row(String label, List<Widget> chips) => Padding(
        padding: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: AppConfig.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
      );

  Widget _chip(String text, bool selected, VoidCallback onTap, {Color? dot}) => ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(text),
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        visualDensity: widget.compact ? VisualDensity.compact : null,
        selectedColor: fade(AppConfig.primary, 0.28),
        side: BorderSide(color: selected ? AppConfig.primary : AppConfig.divider),
      );

  @override
  Widget build(BuildContext context) {
    final color = Storage.subColor;
    final size = Storage.subSize;
    final bg = Storage.subBackground;
    final op = Storage.subBgOpacity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(tr('Color', 'اللون'), [
          for (final e in SubStyle.colors.entries)
            _chip(SubStyle.colorName(e.key), color == e.key, () => _apply(() => Storage.setSubColor(e.key)),
                dot: e.value),
        ]),
        _row(tr('Size', 'الحجم'), [
          for (final k in SubStyle.sizes.keys)
            _chip(SubStyle.sizeName(k), size == k, () => _apply(() => Storage.setSubSize(k))),
        ]),
        _row(tr('Background', 'الخلفية'), [
          _chip(tr('Off', 'بدون'), !bg, () => _apply(() => Storage.setSubBackground(false))),
          _chip(tr('On', 'مع خلفية'), bg, () => _apply(() => Storage.setSubBackground(true))),
        ]),
        if (bg)
          _row(tr('Background opacity', 'شفافية الخلفية'), [
            for (final o in SubStyle.opacities)
              _chip('${(o * 100).round()}%', (op - o).abs() < 0.01, () => _apply(() => Storage.setSubBgOpacity(o))),
          ]),
      ],
    );
  }
}
