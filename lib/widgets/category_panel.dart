import 'package:flutter/material.dart';

import '../config.dart';
import '../data/storage.dart';
import 'common.dart';

class CategoryEntry {
  final String id;
  final String name;
  final int count;
  final IconData? icon;
  final Color? iconColor;

  /// Fixed entries (Favorites / All) stay on top and can't be pinned.
  final bool fixed;

  const CategoryEntry({
    required this.id,
    required this.name,
    required this.count,
    this.icon,
    this.iconColor,
    this.fixed = false,
  });
}

/// Category list with pinning. Pinned categories move to the top (under the
/// fixed entries) and are remembered per [section].
class CategoryPanel extends StatefulWidget {
  final String section;
  final List<CategoryEntry> entries;
  final String selectedId;
  final ValueChanged<String> onSelect;

  /// Put the remote's focus on the selected category when the screen opens.
  final bool autofocusSelected;

  const CategoryPanel({
    super.key,
    required this.section,
    this.autofocusSelected = true,
    required this.entries,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  State<CategoryPanel> createState() => _CategoryPanelState();
}

class _CategoryPanelState extends State<CategoryPanel> {
  late List<String> _pinned = List.of(Storage.pinned(widget.section));

  void _togglePin(String id) {
    setState(() {
      if (!_pinned.remove(id)) _pinned.add(id);
    });
    Storage.setPinned(widget.section, _pinned);
  }

  @override
  Widget build(BuildContext context) {
    final fixed = widget.entries.where((e) => e.fixed).toList();
    final byId = {for (final e in widget.entries.where((e) => !e.fixed)) e.id: e};
    final pinned = [for (final id in _pinned) if (byId.containsKey(id)) byId[id]!];
    final rest = widget.entries.where((e) => !e.fixed && !_pinned.contains(e.id)).toList();

    // Only the rows on screen are built (there can be hundreds of categories).
    final items = <Object>[
      for (final e in fixed) (e, false),
      if (pinned.isNotEmpty) 'PINNED',
      for (final e in pinned) (e, true),
      if (pinned.isNotEmpty && rest.isNotEmpty) 'DIVIDER',
      for (final e in rest) (e, false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('CATEGORIES', top: 16),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            cacheExtent: 48 * 6,
            findChildIndexCallback: (key) {
              if (key is ValueKey<String> && key.value.startsWith('cat-')) {
                final id = key.value.substring(4);
                final i = items.indexWhere((it) => it is (CategoryEntry, bool) && it.$1.id == id);
                return i < 0 ? null : i;
              }
              return null;
            },
            itemBuilder: (context, i) {
              final it = items[i];
              if (it == 'PINNED') return _label('PINNED');
              if (it == 'DIVIDER') return const Divider(height: 9, indent: 12, endIndent: 12);
              final (e, isPinned) = it as (CategoryEntry, bool);
              return _row(e, pinned: isPinned);
            },
          ),
        ),
      ],
    );
  }

  Widget _label(String text, {double top = 10}) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, letterSpacing: 1.4, color: AppConfig.textSecondary, fontWeight: FontWeight.w700)),
      );

  Widget _row(CategoryEntry e, {required bool pinned}) {
    return SizedBox(
      key: ValueKey('cat-${e.id}'),
      height: 48,
      child: SelectableRow(
        selected: e.id == widget.selectedId,
        autofocus: widget.autofocusSelected && e.id == widget.selectedId,
        onTap: () => widget.onSelect(e.id),
        onLongPress: e.fixed
            ? null
            : () {
                _togglePin(e.id);
                showToast(context, _pinned.contains(e.id) ? '📌  ${e.name} pinned to top' : '${e.name} unpinned');
              },
        leading: e.icon != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(e.icon, size: 18, color: e.iconColor ?? AppConfig.textSecondary),
              )
            : null,
        title: e.name,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pinned)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.push_pin_rounded, size: 15, color: AppConfig.primary),
              ),
            CountLabel(e.count),
          ],
        ),
      ),
    );
  }
}
