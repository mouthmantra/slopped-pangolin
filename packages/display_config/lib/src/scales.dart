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

import 'dart:math' as math;

const double _minScale = 1;
const double _maxScale = 3;

/// Smallest logical desktop worth offering a scale for.
const int _minLogicalArea = 800 * 480;

/// Scales offered for a [width] × [height] mode: quarters and thirds from 100%
/// to 400% (100, 125, 133, 150, 167, 175, 200, ...), each moved, like GNOME
/// does, to the nearest value that keeps the logical size whole pixels so
/// nothing is drawn between two pixels.
List<double> supportedScales(int width, int height) {
  if (width <= 0 || height <= 0) return const [1];
  final Set<double> nominal = {
    for (int i = 4; i <= 16; i++) i / 4,
    for (int i = 3; i <= 12; i++) i / 3,
  };
  final List<double> sorted = nominal.toList()..sort();
  final List<double> result = [];
  for (int i = 0; i < sorted.length; i++) {
    final double scale = sorted[i];
    // Never further than halfway to the neighbouring steps.
    final double below = i > 0 ? scale - sorted[i - 1] : 0.25;
    final double above = i < sorted.length - 1 ? sorted[i + 1] - scale : 0.25;
    final double? snapped =
        closestScaleForResolution(width, height, scale, math.min(below, above) / 2);
    if (snapped == null) continue;
    final double area = (width / snapped) * (height / snapped);
    if (area < _minLogicalArea) continue;
    if (result.any((s) => (s - snapped).abs() < 0.001)) continue;
    result.add(snapped);
  }
  return result.isEmpty ? const [1] : result;
}

/// The scale closest to [scale] (within [threshold]) for which both the
/// logical width and height of the mode are whole numbers, as GNOME's
/// get_closest_scale_factor_for_resolution().
double? closestScaleForResolution(
  int width,
  int height,
  double scale,
  double threshold,
) {
  if (width % scale == 0 && height % scale == 0) return scale;
  final int baseWidth = (width / scale).floor();
  double? best;
  for (int i = 0; i < width; i++) {
    bool inRange = false;
    for (final int offset in [-i, i]) {
      final int logicalWidth = baseWidth + offset;
      if (logicalWidth <= 0) continue;
      final double current = width / logicalWidth;
      if ((current - scale).abs() >= threshold ||
          current < _minScale ||
          current > _maxScale) {
        continue;
      }
      inRange = true;
      final double logicalHeight = height / current;
      if ((logicalHeight - logicalHeight.round()).abs() < 1e-6) {
        if (best == null || (current - scale).abs() < (best - scale).abs()) {
          best = current;
        }
      }
    }
    if (best != null || !inRange) break;
  }
  return best;
}

/// The scale that makes a monitor comfortable to read, from its pixel
/// density (GNOME's approach: a lower target density for large monitors
/// seen from further away than laptop panels).
double recommendedScale(
  int width,
  int height,
  int physicalWidthMm,
  int physicalHeightMm,
) {
  final List<double> scales = supportedScales(width, height);
  if (physicalWidthMm <= 0 || physicalHeightMm <= 0) return scales.first;
  // Projectors and some TVs report their aspect ratio as their size.
  if ((physicalWidthMm == 160 && physicalHeightMm == 90) ||
      (physicalWidthMm == 160 && physicalHeightMm == 100) ||
      (physicalWidthMm == 16 && physicalHeightMm == 9) ||
      (physicalWidthMm == 16 && physicalHeightMm == 10)) {
    return scales.first;
  }
  final double diagonalInches =
      math.sqrt(physicalWidthMm * physicalWidthMm + physicalHeightMm * physicalHeightMm) /
          25.4;
  final double dpi = width / (physicalWidthMm / 25.4);
  final double target = diagonalInches >= 20 ? 110 : 135;
  final double ideal = dpi / target;
  double best = scales.first;
  for (final double scale in scales) {
    if ((scale - ideal).abs() < (best - ideal).abs()) best = scale;
  }
  return best;
}

/// "133%".
String scaleLabel(double scale) => "${(scale * 100).round()}%";
