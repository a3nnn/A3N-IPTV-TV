import 'package:flutter/material.dart';

import '../config.dart';
import '../data/storage.dart';
import '../utils.dart';
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
  String? _hoverId;
  String? _focusId;

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

    final rows = <Widget>[
      for (final e in fixed) _row(e, pinned: false),
      if (pinned.isNotEmpty) _label('PINNED'),
      for (final e in pinned) _row(e, pinned: true),
      if (pinned.isNotEmpty && rest.isNotEmpty) const Divider(height: 9, indent: 12, endIndent: 12),
      for (final e in rest) _row(e, pinned: false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('CATEGORIES', top: 16),
        Expanded(child: ListView(children: rows)),
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
    final hover = _hoverId == e.id || _focusId == e.id;
    final showPin = !e.fixed && (pinned || hover);

    return Focus(
      key: ValueKey('cat-${e.id}'),
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() {
        if (f) {
          _focusId = e.id;
        } else if (_focusId == e.id) {
          _focusId = null;
        }
      }),
      child: MouseRegion(
      onEnter: (_) => setState(() => _hoverId = e.id),
      onExit: (_) => setState(() {
        if (_hoverId == e.id) _hoverId = null;
      }),
      child: SizedBox(
        height: 48,
        child: SelectableRow(
          selected: e.id == widget.selectedId,
          autofocus: widget.autofocusSelected && e.id == widget.selectedId,
          onTap: () => widget.onSelect(e.id),
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
              CountLabel(e.count),
              if (!e.fixed)
                SizedBox(
                  width: 30,
                  child: showPin
                      ? IconButton(
                          tooltip: pinned ? 'Unpin' : 'Pin to top',
                          padding: EdgeInsets.zero,
                          iconSize: 17,
                          onPressed: () => _togglePin(e.id),
                          icon: Icon(
                            pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            color: pinned ? AppConfig.primary : fade(AppConfig.textSecondary, 0.8),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
