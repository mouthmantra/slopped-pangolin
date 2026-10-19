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

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/widgets/wallpaper_blur.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

/// Settings > Appearance > accent "From wallpaper": the accent follows the
/// wallpaper's most vivid color whenever the wallpaper changes.
abstract final class WallpaperAccent {
  static final Logger _logger = Logger("WallpaperAccent");

  /// The wallpaper the accent was last taken from.
  static ImageResource? _done;
  static bool _running = false;

  static void follow() {
    void check() => unawaited(_update());
    CustomizationService.current.addListener(check);
    PreferencesService.current.addListener(check);
    check();
  }

  static bool get _enabled =>
      PreferencesService.current.get<bool>(SessionSetting.accentFromWallpaper.key) ??
      SessionSetting.accentFromWallpaper.defaultValue;

  static Future<void> _update() async {
    if (!_enabled) {
      _done = null;
      return;
    }
    final ImageResource wallpaper = CustomizationService.current.wallpaper;
    if (wallpaper == _done || _running) return;
    final ImageProvider? provider = BlurredWallpaper.providerFor(wallpaper);
    if (provider == null) return;
    _running = true;
    try {
      final ui.Image image = await BlurredWallpaper.load(
        ResizeImage(provider, width: 64, policy: ResizeImagePolicy.fit),
      );
      final ByteData? data = await image.toByteData();
      image.dispose();
      _done = wallpaper;
      final Color? color =
          data == null ? null : accentFrom(data.buffer.asUint8List());
      if (color != null && _enabled) {
        final ColorResource accent = ColorResource(
          type: ColorResourceType.hex,
          value: (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0"),
        );
        if (CustomizationService.current.accentColor != accent) {
          CustomizationService.current.accentColor = accent;
        }
      }
    } catch (e) {
      _logger.warning("Couldn't take the accent from the wallpaper: $e");
    } finally {
      _running = false;
    }
    // Changed again meanwhile.
    if (_enabled && CustomizationService.current.wallpaper != _done) {
      unawaited(_update());
    }
  }

  /// The accent for an image given as RGBA bytes: the average of the hue
  /// that covers the most vivid area, made readable on light and dark
  /// surfaces like the built-in accents. Null for a gray image.
  static Color? accentFrom(Uint8List rgba) {
    const int bins = 24;
    final List<double> weight = List.filled(bins, 0);
    final List<double> red = List.filled(bins, 0);
    final List<double> green = List.filled(bins, 0);
    final List<double> blue = List.filled(bins, 0);
    for (int i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final HSVColor hsv =
          HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
      if (hsv.saturation < 0.25 || hsv.value < 0.25) continue;
      final double w = hsv.saturation * hsv.value;
      final int bin = (hsv.hue / 360 * bins).floor() % bins;
      weight[bin] += w;
      red[bin] += rgba[i] * w;
      green[bin] += rgba[i + 1] * w;
      blue[bin] += rgba[i + 2] * w;
    }
    int best = 0;
    for (int b = 1; b < bins; b++) {
      if (weight[b] > weight[best]) best = b;
    }
    final double w = weight[best];
    if (w == 0) return null;
    final HSVColor average = HSVColor.fromColor(
      Color.fromARGB(
        255,
        (red[best] / w).round(),
        (green[best] / w).round(),
        (blue[best] / w).round(),
      ),
    );
    return average
        .withSaturation(average.saturation.clamp(0.5, 0.9))
        .withValue(average.value.clamp(0.6, 0.85))
        .toColor();
  }
}
