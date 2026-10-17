/*
Copyright 2021 The dahliaOS Authors

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

import 'package:flutter/material.dart';
import 'package:zenit_ui/zenit_ui.dart';

class SurfaceLayer extends StatelessWidget {
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final OutlinedBorder shape;
  final Widget? child;
  final double? width;
  final double? height;
  /// Ignored: shell surfaces are set apart by their shadow, never a frame.
  final bool outline;

  /// Fill, the theme's background by default.
  final Color? color;
  final bool dropShadow;

  const SurfaceLayer({
    super.key,
    this.child,
    this.shape = const RoundedRectangleBorder(),
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.outline = false,
    this.color,
    this.dropShadow = false,
  });

  /// Opacity of the fill over the blurred background (frosted glass).
  static const double frostedOpacity = ZenitBlur.fillOpacity;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ZenitBlur.state,
      builder: (context, _) {
        final theme = Theme.of(context);
        final bool frosted = ZenitBlur.active && color == null;
        final Color fill = color ??
            (frosted
                ? theme.colorScheme.background.withValues(alpha: frostedOpacity)
                : theme.colorScheme.background);
        final Widget surface = Container(
          width: width,
          height: height,
          padding: padding,
          margin: margin,
          decoration: ShapeDecoration(
            shape: shape,
            color: fill,
            shadows: dropShadow
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: frosted ? 0.18 : 0.25),
                      blurRadius: 20,
                      spreadRadius: -2,
                      blurStyle: BlurStyle.outer,
                    ),
                  ]
                : [],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
        if (!frosted) return surface;
        final OutlinedBorder border = shape;
        return BlurRegion(
          stadium: border is StadiumBorder,
          borderRadius: border is RoundedRectangleBorder
              ? border.borderRadius.resolve(Directionality.of(context))
              : BorderRadius.zero,
          child: surface,
        );
      },
    );
  }
}
