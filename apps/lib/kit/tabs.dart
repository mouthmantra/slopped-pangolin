/*
Copyright 2026 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:flutter/gestures.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// What a [DahliaTabStrip] shows for one tab.
class DahliaTabData {
  const DahliaTabData({required this.id, required this.title, this.icon, this.tooltip});

  /// Stable identity of the tab, so its state follows it when reordered.
  final Object id;
  final String title;
  final IconData? icon;
  final String? tooltip;
}

/// Browser-style tabs, meant for the title slot of a [DahliaTitlebar].
///
/// Tabs share the available width, scroll when they don't fit, close on
/// middle click and can be reordered by dragging them sideways (vertical drags
/// still move the window).
class DahliaTabStrip extends StatefulWidget {
  const DahliaTabStrip({
    required this.tabs,
    required this.current,
    required this.onSelect,
    required this.onClose,
    this.onReorder,
    this.onNew,
    this.newTooltip = "New tab",
    this.onContextMenu,
    this.minTabWidth = 96,
    this.maxTabWidth = 220,
    super.key,
  });

  final List<DahliaTabData> tabs;
  final int current;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  /// Moves the tab at `from` so it ends up at index `to`.
  final void Function(int from, int to)? onReorder;
  final VoidCallback? onNew;
  final String newTooltip;
  final void Function(int index, Offset globalPosition)? onContextMenu;
  final double minTabWidth;
  final double maxTabWidth;

  @override
  State<DahliaTabStrip> createState() => _DahliaTabStripState();
}

class _DahliaTabStripState extends State<DahliaTabStrip> {
  static const double _gap = 4;
  static const double _newButtonWidth = 36;

  final ScrollController _scroll = ScrollController();
  double _tabWidth = 0;

  // Drag-to-reorder state: the dragged tab follows the pointer by [_dragDx]
  // from its current slot, and swaps slots once it crosses half a neighbor.
  int? _dragIndex;
  double _dragDx = 0;

  @override
  void didUpdateWidget(DahliaTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.current != widget.current ||
        oldWidget.tabs.length != widget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealCurrent() {
    if (!mounted || !_scroll.hasClients || _tabWidth == 0) return;
    final double start = widget.current * (_tabWidth + _gap);
    final double end = start + _tabWidth;
    final ScrollPosition position = _scroll.position;
    double? target;
    if (start < position.pixels) {
      target = start;
    } else if (end > position.pixels + position.viewportDimension) {
      target = end - position.viewportDimension;
    }
    if (target != null) {
      _scroll.animateTo(
        target.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final int? index = _dragIndex;
    if (index == null) return;
    double dx = _dragDx + details.delta.dx;
    int to = index;
    final double slot = _tabWidth + _gap;
    while (dx > slot / 2 && to < widget.tabs.length - 1) {
      to++;
      dx -= slot;
    }
    while (dx < -slot / 2 && to > 0) {
      to--;
      dx += slot;
    }
    if (to != index) widget.onReorder?.call(index, to);
    setState(() {
      _dragIndex = to;
      _dragDx = dx;
    });
  }

  void _endDrag() {
    setState(() {
      _dragIndex = null;
      _dragDx = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int count = widget.tabs.length;
        final double reserved = widget.onNew != null ? _newButtonWidth + _gap : 0;
        final double available = constraints.maxWidth - reserved;
        _tabWidth = ((available - _gap * (count - 1)) / count)
            .clamp(widget.minTabWidth, widget.maxTabWidth);

        final Widget newButton = SizedBox(
          width: _newButtonWidth,
          child: IconButton(
            tooltip: widget.newTooltip,
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded),
            onPressed: widget.onNew,
          ),
        );

        return Row(
          children: [
            Flexible(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (int i = 0; i < count; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      KeyedSubtree(
                        key: ValueKey(widget.tabs[i].id),
                        child: _buildTab(context, i),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.onNew != null) ...[
              const SizedBox(width: _gap),
              newButton,
            ],
          ],
        );
      },
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    final bool dragging = _dragIndex == index;
    Widget tab = _Tab(
      data: widget.tabs[index],
      width: _tabWidth,
      selected: index == widget.current,
      dragging: dragging,
      onTap: () => widget.onSelect(index),
      onClose: () => widget.onClose(index),
      onContextMenu: widget.onContextMenu == null
          ? null
          : (position) => widget.onContextMenu!(index, position),
    );
    if (dragging) {
      tab = Transform.translate(offset: Offset(_dragDx, 0), child: tab);
    }
    if (widget.onReorder == null || widget.tabs.length < 2) return tab;

    return RawGestureDetector(
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          HorizontalDragGestureRecognizer.new,
          (recognizer) => recognizer
            ..onStart = (_) {
              widget.onSelect(index);
              setState(() {
                _dragIndex = index;
                _dragDx = 0;
              });
            }
            ..onUpdate = _onDragUpdate
            ..onEnd = ((_) => _endDrag())
            ..onCancel = _endDrag,
        ),
      },
      child: tab,
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.data,
    required this.width,
    required this.selected,
    required this.dragging,
    required this.onTap,
    required this.onClose,
    this.onContextMenu,
  });

  final DahliaTabData data;
  final double width;
  final bool selected;
  final bool dragging;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset>? onContextMenu;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color foreground = theme.colorScheme.onSurface;
    final double backgroundAlpha = widget.selected || widget.dragging
        ? (theme.brightness == Brightness.dark ? 0.14 : 0.09)
        : _hovered
            ? 0.05
            : 0;
    final bool showClose = widget.selected || _hovered;

    Widget tab = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTertiaryTapUp: (_) => widget.onClose(),
        onSecondaryTapUp: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: widget.width,
          height: 34,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: backgroundAlpha),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              if (widget.data.icon != null) ...[
                Icon(
                  widget.data.icon,
                  size: 16,
                  color: widget.selected
                      ? theme.colorScheme.primary
                      : foreground.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground.withValues(alpha: widget.selected ? 1 : 0.75),
                  ),
                ),
              ),
              // The close button keeps its space so titles don't jump around
              // when hovering.
              SizedBox.square(
                dimension: 24,
                child: showClose
                    ? IconButton(
                        tooltip: "Close tab",
                        padding: EdgeInsets.zero,
                        iconSize: 14,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: widget.onClose,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.data.tooltip != null && !widget.dragging) {
      tab = Tooltip(
        message: widget.data.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: tab,
      );
    }
    return tab;
  }
}
