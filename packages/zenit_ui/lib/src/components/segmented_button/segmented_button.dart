import 'package:flutter/material.dart';

/// One choice out of a few, as a pill: a track with the selected choice
/// filled in the accent color, as Files' view switcher.
///
/// Material's [SegmentedButton] clips its segments to its outline, a path,
/// and Impeller on desktop OpenGL (no multisampling) draws path clips
/// without antialiasing: jagged ends at 100% scale. This draws only rounded
/// rectangles with one radius, which it antialiases. Same parameters as
/// [SegmentedButton] for a single selection.
class ZenitSegmentedButton<T> extends StatelessWidget {
  const ZenitSegmentedButton({
    required this.segments,
    required this.selected,
    this.onSelectionChanged,
    this.height = 32,
    super.key,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onSelectionChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface
            .withValues(alpha: theme.brightness == Brightness.dark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ButtonSegment<T> segment in segments)
            _Segment<T>(
              segment: segment,
              height: height,
              selected: selected.contains(segment.value),
              onPressed: onSelectionChanged == null || !segment.enabled
                  ? null
                  : () => onSelectionChanged!({segment.value}),
            ),
        ],
      ),
    );
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.segment,
    required this.height,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final ButtonSegment<T> segment;
  final double height;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool enabled = widget.onPressed != null;
    final Color foreground = widget.selected
        ? colors.onPrimary
        : colors.onSurface.withValues(alpha: enabled ? 0.87 : 0.38);
    final Color fill = widget.selected
        ? colors.primary
        : colors.onSurface.withValues(
            alpha: _pressed
                ? 0.12
                : _hovered
                    ? 0.06
                    : 0,
          );
    final BorderRadius radius = BorderRadius.circular(widget.height / 2);

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.segment.icon != null) ...[
          IconTheme.merge(
            data: IconThemeData(size: 16, color: foreground),
            child: widget.segment.icon!,
          ),
          if (widget.segment.label != null) const SizedBox(width: 6),
        ],
        if (widget.segment.label != null)
          DefaultTextStyle.merge(
            style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            child: widget.segment.label!,
          ),
      ],
    );
    if (widget.segment.tooltip != null) {
      content = Tooltip(message: widget.segment.tooltip, child: content);
    }

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: enabled,
      child: InkWell(
        onTap: widget.onPressed,
        onHover: (hovered) => setState(() => _hovered = hovered),
        onFocusChange: (focused) => setState(() => _focused = focused),
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        // Its own highlight and splash would be clipped to a path.
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: widget.height,
          padding: EdgeInsets.symmetric(
            horizontal: widget.segment.label == null ? 10 : 14,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: _focused
                ? Border.all(color: colors.primary.withValues(alpha: 0.6), width: 2)
                : null,
          ),
          child: content,
        ),
      ),
    );
  }
}
