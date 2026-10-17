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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/overview/layout.dart';
import 'package:pangolin/widgets/resource/image/image.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';

/// What the overview draws below the windows, on the desktop surface: the
/// bar of desks along the top and the area holding the windows, filled like
/// the rest of the shell (frosted over the wallpaper when effects are on).
/// river draws the copies of the windows above it, the shell surface draws
/// labels and buttons above those.
class OverviewBackdrop extends StatelessWidget {
  const OverviewBackdrop({required this.wallpaper, super.key});

  final ImageResource wallpaper;

  @override
  Widget build(BuildContext context) {
    final OverviewModel model = OverviewModel.instance;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([model, model.backdrop]),
        builder: (context, _) {
          final double t = model.backdrop.value;
          final OverviewLayout? layout = model.layout;
          if (t <= 0 || layout == null) return const SizedBox.shrink();
          return OverviewSurfaces(
            layout: layout,
            progress: t,
            wallpaper: wallpaper,
          );
        },
      ),
    );
  }
}

/// The surfaces of the overview: the desk bar sliding down from the top, the
/// window area fading in below it, the desk thumbnails.
class OverviewSurfaces extends StatelessWidget {
  const OverviewSurfaces({
    required this.layout,
    required this.progress,
    required this.wallpaper,
    super.key,
  });

  final OverviewLayout layout;
  final double progress;
  final ImageResource wallpaper;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double t = progress;
    final Offset strip = layout.stripOffset(t);
    final bool frosted = CustomizationService.current.enableEffects;
    final double alpha = frosted ? 0.82 : 1;

    return Stack(
      children: [
        // Window area, faded in by drawing each part translucent (an
        // Opacity would render the whole screen to a layer every frame).
        if (frosted)
          Positioned.fill(
            child: WallpaperBlur(opacity: t.clamp(0.0, 1.0)),
          ),
        Positioned.fill(
          child: ColoredBox(
            color: theme.colorScheme.surface.withValues(
              alpha: alpha * t.clamp(0.0, 1.0),
            ),
          ),
        ),
        // Desk bar.
        Positioned(
          left: 0,
          right: 0,
          top: strip.dy,
          height: layout.stripHeight,
          child: ColoredBox(color: theme.colorScheme.background),
        ),
        for (int d = 0; d < layout.desks.length; d++)
          Positioned.fromRect(
            rect: layout.desks[d].shift(strip),
            child: ClipRRect(
              borderRadius: OverviewLayout.deskRadius,
              child: ResourceImage(
                resource: wallpaper,
                fit: BoxFit.cover,
              ),
            ),
          ),
      ],
    );
  }
}
