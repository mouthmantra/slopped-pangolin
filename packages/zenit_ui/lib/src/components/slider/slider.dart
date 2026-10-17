import 'package:flutter/material.dart';
import 'package:zenit_ui/src/theme/theme.dart';

class ZenitSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// Called with the final value when the user lets go after a tap or a drag.
  final ValueChanged<double>? onChangeEnd;

  final Color? activeColor;

  /// When non-null the slider snaps to `divisions + 1` discrete values and
  /// paints a tick for each of them.
  final int? divisions;
  final Color? trackColor;
  final MouseCursor? mouseCursor;
  final Color? thumbColor;

  const ZenitSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.divisions,
    this.trackColor,
    this.mouseCursor,
    this.thumbColor,
  })  : assert(value >= 0.0 && value <= 1.0),
        assert(divisions == null || divisions > 0);

  @override
  State<ZenitSlider> createState() => _ZenitSliderState();
}

class _ZenitSliderState extends State<ZenitSlider> {
  bool hover = false;
  double? _last;

  double _snap(double value) {
    final double clamped = value.clamp(0.0, 1.0);
    final int? divisions = widget.divisions;
    if (divisions == null) return clamped;
    return (clamped * divisions).round() / divisions;
  }

  void _emit(double value) {
    final double snapped = _snap(value);
    _last = snapped;
    if (snapped != widget.value) widget.onChanged(snapped);
  }

  void _end() => widget.onChangeEnd?.call(_last ?? widget.value);
  @override
  Widget build(BuildContext context) {
    final sliderTheme = ZenitTheme.sliderTheme(context);
    double newValue = widget.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: widget.mouseCursor ?? SystemMouseCursors.click,
          onEnter: (_) => setState(() => hover = true),
          onExit: (_) => setState(() => hover = false),
          child: Listener(
            onPointerPanZoomStart: (details) {
              newValue = details.localPosition.dx / (constraints.maxWidth);
              _emit(newValue);
            },
            child: GestureDetector(
              onTapDown: (details) {
                newValue = details.localPosition.dx / (constraints.maxWidth);
                _emit(newValue);
              },
              onTapUp: (_) => _end(),
              onHorizontalDragUpdate: (details) {
                newValue = details.localPosition.dx / constraints.maxWidth;
                _emit(newValue);
              },
              onHorizontalDragEnd: (_) => _end(),
              child: CustomPaint(
                painter: _SliderPainter(
                  trackColor: widget.trackColor ?? sliderTheme.trackColor,
                  activeColor: widget.activeColor ?? sliderTheme.activeTrackColor,
                  thumbColor: widget.thumbColor ?? sliderTheme.thumbColor,
                  hover: hover,
                  hoverColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                  outlineColor: sliderTheme.outlineColor,
                  value: widget.value,
                  divisions: widget.divisions,
                ),
                size: Size(constraints.maxWidth, 48),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  final Color trackColor;
  final Color activeColor;
  final double value;
  final bool hover;
  final Color hoverColor;
  final Color thumbColor;
  final Color outlineColor;
  final int? divisions;

  _SliderPainter({
    required this.trackColor,
    required this.activeColor,
    required this.value,
    required this.hover,
    required this.hoverColor,
    required this.thumbColor,
    required this.outlineColor,
    this.divisions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;

    final Paint activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final Paint thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;

    final Paint outlinePaint = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final RRect track = RRect.fromLTRBR(0.0, 12.0, size.width, size.height - 12, const Radius.circular(12.0));
    final RRect active = RRect.fromLTRBR(
      0.0,
      12.0,
      (size.width * value) > 24 ? (size.width * value) : 24.0,
      size.height - 12.0,
      const Radius.circular(12.0),
    );

    final Offset thumbPosition = Offset(
      (size.width * value) > 24 ? (size.width * value) - ((size.height - 26) / 3) - 6 : 24 - 12,
      size.height / 2,
    );

    canvas.drawRRect(track, trackPaint);
    canvas.drawRRect(track, outlinePaint);

    canvas.drawRRect(active, activePaint);

    if (divisions != null && divisions! > 1) {
      final double inset = 12.0;
      final double usable = size.width - inset * 2;
      for (int i = 1; i < divisions!; i++) {
        final double x = inset + usable * i / divisions!;
        final bool covered = x <= size.width * value;
        canvas.drawCircle(
          Offset(x, size.height / 2),
          1.5,
          Paint()..color = (covered ? thumbColor : outlineColor).withOpacity(0.6),
        );
      }
    }

    if (hover) {
      final Paint hoverPaint = Paint()
        ..color = hoverColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(thumbPosition, 20, hoverPaint);
    }

    canvas.drawCircle(thumbPosition, (size.height - 24) / 3, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) {
    return old.value != value ||
        old.activeColor != activeColor ||
        old.trackColor != trackColor ||
        old.hover != hover ||
        old.hoverColor != hoverColor ||
        old.thumbColor != thumbColor ||
        old.outlineColor != outlineColor ||
        old.divisions != divisions;
  }
}
