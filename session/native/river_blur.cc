// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

#include "river_blur.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>

std::vector<RiverBlurRegion> river_blur_regions_from_value(FlValue* list) {
  std::vector<RiverBlurRegion> regions;
  if (list == nullptr || fl_value_get_type(list) != FL_VALUE_TYPE_LIST) {
    return regions;
  }
  for (size_t i = 0; i < fl_value_get_length(list); i++) {
    FlValue* entry = fl_value_get_list_value(list, i);
    if (fl_value_get_type(entry) != FL_VALUE_TYPE_LIST ||
        fl_value_get_length(entry) != 9) {
      continue;
    }
    int32_t v[9];
    bool valid = true;
    for (size_t j = 0; j < 9; j++) {
      FlValue* value = fl_value_get_list_value(entry, j);
      if (fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
        valid = false;
        break;
      }
      v[j] = static_cast<int32_t>(fl_value_get_int(value));
    }
    if (valid) {
      regions.push_back({v[0], v[1], v[2], v[3], {v[4], v[5], v[6], v[7]}, v[8]});
    }
  }
  return regions;
}

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client.h>

// Protocol tables, as wayland-scanner would generate them for
// river-river-blur-v1.xml (no events, so no listeners).
extern "C" {
extern const struct wl_interface wl_surface_interface;
extern const struct wl_interface river_blur_v1_interface;

static const struct wl_interface* river_blur_types[] = {
    &river_blur_v1_interface,
    &wl_surface_interface,
    nullptr,
};

static const struct wl_message river_blur_manager_v1_requests[] = {
    {"destroy", "", river_blur_types + 2},
    {"get_blur", "no", river_blur_types + 0},
};

static const struct wl_interface* river_blur_no_types[] = {
    nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
};

static const struct wl_message river_blur_v1_requests[] = {
    {"destroy", "", river_blur_types + 2},
    {"set_regions", "a", river_blur_types + 2},
    {"reveal", "2iiiiiiiiuiiii", river_blur_no_types},
    {"conceal", "2iiiiiiiiuiiii", river_blur_no_types},
    {"set_cutouts", "3a", river_blur_types + 2},
    {"set_visible_area", "4iiii", river_blur_no_types},
    {"set_tint", "4uiiiiuiiii", river_blur_no_types},
};

const struct wl_interface river_blur_manager_v1_interface = {
    "river_blur_manager_v1", 4, 2, river_blur_manager_v1_requests, 0, nullptr,
};

const struct wl_interface river_blur_v1_interface = {
    "river_blur_v1", 4, 7, river_blur_v1_requests, 0, nullptr,
};
}

namespace {

constexpr uint32_t kGetBlur = 1;
constexpr uint32_t kSetRegions = 1;
constexpr uint32_t kReveal = 2;
constexpr uint32_t kConceal = 3;
constexpr uint32_t kSetVisibleArea = 5;
constexpr uint32_t kSetTint = 6;

struct wl_proxy* manager = nullptr;
bool initialized = false;

void handle_global(void* data, struct wl_registry* registry, uint32_t name,
                   const char* interface, uint32_t version) {
  if (strcmp(interface, river_blur_manager_v1_interface.name) == 0) {
    // Version 2 animates parts of surfaces, 4 sets visible areas and tints;
    // older rivers only blur.
    const uint32_t bound = version < 4 ? version : 4;
    *static_cast<struct wl_proxy**>(data) = static_cast<struct wl_proxy*>(
        wl_registry_bind(registry, name, &river_blur_manager_v1_interface,
                         bound));
  }
}

void handle_global_remove(void*, struct wl_registry*, uint32_t) {}

const struct wl_registry_listener registry_listener = {
    handle_global,
    handle_global_remove,
};

struct wl_display* wayland_display() {
  GdkDisplay* display = gdk_display_get_default();
  if (display == nullptr || !GDK_IS_WAYLAND_DISPLAY(display)) return nullptr;
  return gdk_wayland_display_get_wl_display(display);
}

// Binds the manager on GTK's connection, through a private queue so that
// GTK's own event dispatching is not involved.
void ensure_manager() {
  if (initialized) return;
  initialized = true;
  struct wl_display* display = wayland_display();
  if (display == nullptr) return;

  struct wl_event_queue* queue = wl_display_create_queue(display);
  auto* wrapper =
      static_cast<struct wl_display*>(wl_proxy_create_wrapper(display));
  wl_proxy_set_queue(reinterpret_cast<struct wl_proxy*>(wrapper), queue);
  struct wl_registry* registry = wl_display_get_registry(wrapper);
  wl_registry_add_listener(registry, &registry_listener, &manager);
  wl_display_roundtrip_queue(display, queue);
  wl_registry_destroy(registry);
  wl_proxy_wrapper_destroy(wrapper);
  // The queue stays: the manager and the blur objects are assigned to it
  // (they have no events).
}

// The blur object of a window, for the wl_surface it was made for: GTK
// destroys a window's wl_surface when it's hidden and makes a new one when
// it's shown again (gtk-layer-shell does that to move a shell surface to
// another monitor), and river forgets the blur along with the old surface.
struct WindowBlur {
  struct wl_proxy* blur = nullptr;
  struct wl_surface* surface = nullptr;
  // The regions last set, in surface coordinates (9 values each), sent
  // again to a new surface.
  std::vector<int32_t> regions;
  bool has_regions = false;
  // The visible area last set (x, y, width, height; a zero size for all).
  int32_t area[4] = {0, 0, 0, 0};
};

constexpr const char* kStateKey = "pangolin-river-blur";

void destroy_proxy(struct wl_proxy* blur) {
  // river_blur_v1.destroy (opcode 0).
  wl_proxy_marshal_flags(blur, 0, nullptr, wl_proxy_get_version(blur),
                         WL_MARSHAL_FLAG_DESTROY);
}

void free_state(gpointer data) {
  auto* state = static_cast<WindowBlur*>(data);
  if (state->blur != nullptr) destroy_proxy(state->blur);
  delete state;
}

void send_regions(WindowBlur* state) {
  struct wl_array array;
  wl_array_init(&array);
  void* values = wl_array_add(&array, state->regions.size() * sizeof(int32_t));
  if (values != nullptr && !state->regions.empty()) {
    memcpy(values, state->regions.data(),
           state->regions.size() * sizeof(int32_t));
  }
  wl_proxy_marshal_flags(state->blur, kSetRegions, nullptr,
                         wl_proxy_get_version(state->blur), 0, &array);
  wl_array_release(&array);
}

void on_window_mapped(GtkWidget* widget, gpointer data);
void on_window_unmapped(GtkWidget* widget, gpointer data);

WindowBlur* state_for(GtkWindow* window) {
  auto* state = static_cast<WindowBlur*>(
      g_object_get_data(G_OBJECT(window), kStateKey));
  if (state != nullptr) return state;
  state = new WindowBlur();
  g_object_set_data_full(G_OBJECT(window), kStateKey, state, free_state);
  g_signal_connect_after(window, "map", G_CALLBACK(on_window_mapped),
                         nullptr);
  // Before GTK destroys the surface (a new one might reuse its address).
  g_signal_connect(window, "unmap", G_CALLBACK(on_window_unmapped), nullptr);
  return state;
}

// The blur object for the window's current surface, made anew (with the
// regions set before) when the surface changed.
struct wl_proxy* blur_for(GtkWindow* window, GdkWindow* gdk_window) {
  WindowBlur* state = state_for(window);
  struct wl_surface* surface = gdk_wayland_window_get_wl_surface(gdk_window);
  if (surface == nullptr) return nullptr;
  if (state->blur != nullptr && state->surface == surface) return state->blur;
  if (state->blur != nullptr) destroy_proxy(state->blur);
  state->blur = wl_proxy_marshal_flags(
      manager, kGetBlur, &river_blur_v1_interface,
      wl_proxy_get_version(manager), 0, nullptr, surface);
  state->surface = surface;
  if (state->has_regions) send_regions(state);
  if (state->area[2] > 0 && wl_proxy_get_version(state->blur) >= 4) {
    wl_proxy_marshal_flags(state->blur, kSetVisibleArea, nullptr,
                           wl_proxy_get_version(state->blur), 0, state->area[0],
                           state->area[1], state->area[2], state->area[3]);
  }
  return state->blur;
}

void on_window_unmapped(GtkWidget* widget, gpointer) {
  auto* state = static_cast<WindowBlur*>(
      g_object_get_data(G_OBJECT(widget), kStateKey));
  if (state == nullptr || state->blur == nullptr) return;
  destroy_proxy(state->blur);
  state->blur = nullptr;
  state->surface = nullptr;
}

void on_window_mapped(GtkWidget* widget, gpointer) {
  auto* state = static_cast<WindowBlur*>(
      g_object_get_data(G_OBJECT(widget), kStateKey));
  if (state == nullptr || !state->has_regions || manager == nullptr) return;
  GdkWindow* gdk_window = gtk_widget_get_window(widget);
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  if (gdk_wayland_window_get_wl_surface(gdk_window) == state->surface) return;
  // A new surface: blur_for sends it the regions.
  if (blur_for(GTK_WINDOW(widget), gdk_window) == nullptr) return;
  wl_display_flush(wayland_display());
  gtk_widget_queue_draw(widget);
}

}  // namespace

bool river_blur_supported() {
  ensure_manager();
  return manager != nullptr;
}

bool river_blur_animations_supported() {
  ensure_manager();
  return manager != nullptr && wl_proxy_get_version(manager) >= 2;
}

void river_blur_animate_part(GtkWindow* window, GtkWidget* widget, bool reveal,
                             int32_t x, int32_t y, int32_t width,
                             int32_t height, RiverPartState state,
                             uint32_t duration_ms, const int32_t curve[4]) {
  if (!river_blur_animations_supported()) return;
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  struct wl_proxy* blur = blur_for(window, gdk_window);
  if (blur == nullptr) return;

  int dx = 0, dy = 0;
  if (widget != nullptr && widget != GTK_WIDGET(window)) {
    gtk_widget_translate_coordinates(widget, GTK_WIDGET(window), 0, 0, &dx,
                                     &dy);
  }
  wl_proxy_marshal_flags(blur, reveal ? kReveal : kConceal, nullptr,
                         wl_proxy_get_version(blur), 0, x + dx, y + dy, width,
                         height, state.dx, state.dy, state.scale,
                         state.opacity, duration_ms, curve[0], curve[1],
                         curve[2], curve[3]);
  // Takes effect right away, before the next frame is committed.
  wl_display_flush(wayland_display());
}

bool river_blur_tints_supported() {
  ensure_manager();
  return manager != nullptr && wl_proxy_get_version(manager) >= 4;
}

void river_blur_set_visible_area(GtkWindow* window, int32_t x, int32_t y,
                                 int32_t width, int32_t height) {
  if (!river_blur_tints_supported()) return;
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  WindowBlur* state = state_for(window);
  state->area[0] = x;
  state->area[1] = y;
  state->area[2] = width > 0 && height > 0 ? width : 0;
  state->area[3] = width > 0 && height > 0 ? height : 0;
  struct wl_proxy* blur = blur_for(window, gdk_window);
  if (blur == nullptr) return;
  wl_proxy_marshal_flags(blur, kSetVisibleArea, nullptr,
                         wl_proxy_get_version(blur), 0, state->area[0],
                         state->area[1], state->area[2], state->area[3]);
  // Takes effect right away, before the next frame is committed.
  wl_display_flush(wayland_display());
}

void river_blur_set_tint(GtkWindow* window, uint32_t argb,
                         const int32_t area[4], uint32_t duration_ms,
                         const int32_t curve[4]) {
  if (!river_blur_tints_supported()) return;
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  struct wl_proxy* blur = blur_for(window, gdk_window);
  if (blur == nullptr) return;
  wl_proxy_marshal_flags(blur, kSetTint, nullptr, wl_proxy_get_version(blur),
                         0, argb, area[0], area[1], area[2], area[3],
                         duration_ms, curve[0], curve[1], curve[2], curve[3]);
  wl_display_flush(wayland_display());
}

void river_blur_set_regions(GtkWindow* window, GtkWidget* widget,
                            const std::vector<RiverBlurRegion>& regions) {
  ensure_manager();
  if (manager == nullptr) return;
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr || !GDK_IS_WAYLAND_WINDOW(gdk_window)) return;
  // From widget to surface coordinates (client side decorations put the
  // window's content after its shadow).
  int dx = 0, dy = 0;
  if (widget != nullptr && widget != GTK_WIDGET(window)) {
    gtk_widget_translate_coordinates(widget, GTK_WIDGET(window), 0, 0, &dx,
                                     &dy);
  }

  WindowBlur* state = state_for(window);
  std::vector<int32_t> values;
  for (const RiverBlurRegion& region : regions) {
    values.insert(values.end(),
                  {region.x + dx, region.y + dy, region.width, region.height,
                   region.radii[0], region.radii[1], region.radii[2],
                   region.radii[3], region.alpha});
  }
  // Unchanged (Flutter reports them after every layout): nothing to send.
  if (state->has_regions && values == state->regions &&
      state->blur != nullptr &&
      state->surface == gdk_wayland_window_get_wl_surface(gdk_window)) {
    return;
  }
  state->regions = std::move(values);
  state->has_regions = true;
  struct wl_proxy* blur = blur_for(window, gdk_window);
  if (blur == nullptr) return;
  send_regions(state);
  wl_display_flush(wayland_display());
  // The regions apply with the next commit of the surface: a repaint of one
  // pixel makes one (of the whole window, it costs a full 4K repaint).
  gtk_widget_queue_draw_area(GTK_WIDGET(window), 0, 0, 1, 1);
}

#else

bool river_blur_supported() { return false; }

bool river_blur_animations_supported() { return false; }

void river_blur_animate_part(GtkWindow*, GtkWidget*, bool, int32_t, int32_t,
                             int32_t, int32_t, RiverPartState, uint32_t,
                             const int32_t[4]) {}

void river_blur_set_regions(GtkWindow*, GtkWidget*,
                            const std::vector<RiverBlurRegion>&) {}

bool river_blur_tints_supported() { return false; }

void river_blur_set_visible_area(GtkWindow*, int32_t, int32_t, int32_t,
                                 int32_t) {}

void river_blur_set_tint(GtkWindow*, uint32_t, const int32_t[4], uint32_t,
                         const int32_t[4]) {}

#endif
