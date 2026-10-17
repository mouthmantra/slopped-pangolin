// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0
//
// Client side of river-blur-v1 for GTK windows: asks river to blur what is
// behind rounded parts of a window (frosted glass). Shared by the Pangolin
// shell and the dahliaOS apps.

#ifndef PANGOLIN_RIVER_BLUR_H_
#define PANGOLIN_RIVER_BLUR_H_

#include <gtk/gtk.h>

#include <cstdint>
#include <vector>

// A rounded rectangle in window (widget) logical coordinates.
struct RiverBlurRegion {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  // Top left, top right, bottom right, bottom left.
  int32_t radii[4];
  // 0 to 10000.
  int32_t alpha;
};

// Whether the compositor blurs (river with river-blur-v1).
bool river_blur_supported();

// Sets the blurred parts of [window], given relative to [widget] (e.g. the
// FlView filling it). An empty list removes the blur.
void river_blur_set_regions(GtkWindow* window, GtkWidget* widget,
                            const std::vector<RiverBlurRegion>& regions);

// Whether the compositor animates parts of windows (river-blur-v1 version 2).
bool river_blur_animations_supported();

// How a part of a window is drawn at one end of an animation: scaled around
// its center, moved and faded. Values are multiplied by 10000 where noted.
struct RiverPartState {
  int32_t dx;
  int32_t dy;
  int32_t scale;    // x 10000
  int32_t opacity;  // x 10000
};

// Animates the part [x, y, width, height] of [window] (relative to [widget])
// into view from [from] (reveal) or out of view to [to] (conceal), over
// [duration_ms] following cubic-bezier([curve] / 10000).
void river_blur_animate_part(GtkWindow* window, GtkWidget* widget, bool reveal,
                             int32_t x, int32_t y, int32_t width,
                             int32_t height, RiverPartState state,
                             uint32_t duration_ms, const int32_t curve[4]);

// Decodes a method channel list of [x, y, w, h, top left, top right, bottom
// right, bottom left radius, alpha] integer lists.
typedef struct _FlValue FlValue;
std::vector<RiverBlurRegion> river_blur_regions_from_value(FlValue* list);

#endif  // PANGOLIN_RIVER_BLUR_H_
