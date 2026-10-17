import 'package:flutter/material.dart';
import 'package:zenit_ui/src/constants/constants.dart';

class ZenitSection extends StatelessWidget {
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final Widget child;

  const ZenitSection({
    super.key,
    this.color,
    this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Material(
        // A filled card set apart from the page by its tint, not a frame.
        color: color ?? sectionColor(Theme.of(context)),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius ?? kCardBorderRadius,
        ),
        child: child,
      ),
    );
  }
}

/// Fill of cards and side panes: a step away from the page background.
Color sectionColor(ThemeData theme) => Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.06 : 0.04,
      ),
      theme.colorScheme.background,
    );
