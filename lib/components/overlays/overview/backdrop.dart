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
import 'package:pangolin/services/session.dart';
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
            // river tints the window area (river-blur-v1 version 4).
            tinted: PangolinSession.tints.value,
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
    this.tinted = false,
    super.key,
  });

  final OverviewLayout layout;
  final double progress;
  final ImageResource wallpaper;

  /// river draws the window area (a tint over the wallpaper): only the desk
  /// bar is drawn here.
  final bool tinted;

  /// Desk thumbnails are at most 120 logical pixels high (OverviewLayout).
  static const int _thumbnailWidth = 480;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double t = progress;
    final Offset strip = layout.stripOffset(t);
    final bool frosted = CustomizationService.current.enableEffects;
    final double alpha = frosted ? 0.82 : 1;
    // A small decode, kept in the image cache: the full wallpaper (which
    // nothing else on this surface keeps once river draws it) took a
    // decode and a 4K upload on every opening.
    final ImageProvider? base = BlurredWallpaper.providerFor(wallpaper);
    final ImageProvider? thumbnail = base == null
        ? null
        : ResizeImage(base,
            width: _thumbnailWidth, policy: ResizeImagePolicy.fit);

    return Stack(
      children: [
        // Window area, faded in by drawing each part translucent (an
        // Opacity would render the whole screen to a layer every frame).
        if (frosted && !tinted)
          Positioned.fill(
            child: WallpaperBlur(opacity: t.clamp(0.0, 1.0)),
          ),
        if (!tinted)
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
              child: thumbnail != null
                  ? Image(
                      image: thumbnail,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    )
                  : ResourceImage(
                      resource: wallpaper,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
      ],
    );
  }
}
