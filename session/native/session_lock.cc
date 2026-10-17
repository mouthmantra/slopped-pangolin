// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

#include "session_lock.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#include <wayland-client.h>

#include <cstring>

// Protocol tables, as wayland-scanner would generate them for
// ext-session-lock-v1.xml.
extern "C" {
extern const struct wl_interface wl_surface_interface;
extern const struct wl_interface wl_output_interface;
extern const struct wl_interface ext_session_lock_v1_interface;
extern const struct wl_interface ext_session_lock_surface_v1_interface;

static const struct wl_interface* session_lock_types[] = {
    nullptr,
    nullptr,
    nullptr,
    &ext_session_lock_v1_interface,
    &ext_session_lock_surface_v1_interface,
    &wl_surface_interface,
    &wl_output_interface,
};

static const struct wl_message ext_session_lock_manager_v1_requests[] = {
    {"destroy", "", session_lock_types + 0},
    {"lock", "n", session_lock_types + 3},
};

static const struct wl_message ext_session_lock_v1_requests[] = {
    {"destroy", "", session_lock_types + 0},
    {"get_lock_surface", "noo", session_lock_types + 4},
    {"unlock_and_destroy", "", session_lock_types + 0},
};

static const struct wl_message ext_session_lock_v1_events[] = {
    {"locked", "", session_lock_types + 0},
    {"finished", "", session_lock_types + 0},
};

static const struct wl_message ext_session_lock_surface_v1_requests[] = {
    {"destroy", "", session_lock_types + 0},
    {"ack_configure", "u", session_lock_types + 0},
};

static const struct wl_message ext_session_lock_surface_v1_events[] = {
    {"configure", "uuu", session_lock_types + 0},
};

const struct wl_interface ext_session_lock_manager_v1_interface = {
    "ext_session_lock_manager_v1", 1, 2, ext_session_lock_manager_v1_requests,
    0, nullptr,
};

const struct wl_interface ext_session_lock_v1_interface = {
    "ext_session_lock_v1", 1, 3, ext_session_lock_v1_requests,
    2, ext_session_lock_v1_events,
};

const struct wl_interface ext_session_lock_surface_v1_interface = {
    "ext_session_lock_surface_v1", 1, 2, ext_session_lock_surface_v1_requests,
    1, ext_session_lock_surface_v1_events,
};
}

namespace {

constexpr uint32_t kManagerLock = 1;
constexpr uint32_t kLockDestroy = 0;
constexpr uint32_t kLockGetLockSurface = 1;
constexpr uint32_t kLockUnlockAndDestroy = 2;
constexpr uint32_t kSurfaceDestroy = 0;
constexpr uint32_t kSurfaceAckConfigure = 1;

struct LockOutput {
  GdkMonitor* monitor = nullptr;
  GtkWindow* window = nullptr;
  FlView* view = nullptr;
  struct wl_proxy* lock_surface = nullptr;
  bool shown = false;
};

struct State {
  bool initialized = false;
  struct wl_display* display = nullptr;
  struct wl_event_queue* queue = nullptr;
  struct wl_proxy* manager = nullptr;

  struct wl_proxy* lock = nullptr;
  bool locked = false;
  GtkApplication* application = nullptr;
  FlEngine* engine = nullptr;
  SessionLockDelegate delegate = {};
  std::vector<LockOutput*> outputs;
  guint dispatch_source = 0;
  gulong monitor_added = 0;
  gulong monitor_removed = 0;
};

State state;

void handle_global(void* data, struct wl_registry* registry, uint32_t name,
                   const char* interface, uint32_t version) {
  if (strcmp(interface, ext_session_lock_manager_v1_interface.name) == 0) {
    state.manager = static_cast<struct wl_proxy*>(wl_registry_bind(
        registry, name, &ext_session_lock_manager_v1_interface, 1));
  }
}

void handle_global_remove(void*, struct wl_registry*, uint32_t) {}

const struct wl_registry_listener registry_listener = {
    handle_global,
    handle_global_remove,
};

// Binds the manager on GTK's connection, on a private queue that this file
// dispatches itself.
void ensure_manager() {
  if (state.initialized) return;
  state.initialized = true;
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (gdk_display == nullptr || !GDK_IS_WAYLAND_DISPLAY(gdk_display)) return;
  state.display = gdk_wayland_display_get_wl_display(gdk_display);
  state.queue = wl_display_create_queue(state.display);
  auto* wrapper =
      static_cast<struct wl_display*>(wl_proxy_create_wrapper(state.display));
  wl_proxy_set_queue(reinterpret_cast<struct wl_proxy*>(wrapper), state.queue);
  struct wl_registry* registry = wl_display_get_registry(wrapper);
  wl_registry_add_listener(registry, &registry_listener, nullptr);
  wl_display_roundtrip_queue(state.display, state.queue);
  wl_registry_destroy(registry);
  wl_proxy_wrapper_destroy(wrapper);
}

// GTK reads the connection; the events for the private queue are handled
// here.
gboolean dispatch_cb(gpointer) {
  if (state.display == nullptr) return G_SOURCE_REMOVE;
  wl_display_dispatch_queue_pending(state.display, state.queue);
  return G_SOURCE_CONTINUE;
}

void notify_views() {
  if (state.delegate.views_changed != nullptr) {
    state.delegate.views_changed(state.delegate.user_data);
  }
}

void notify_state(const char* name) {
  if (state.delegate.state_changed != nullptr) {
    state.delegate.state_changed(name, state.delegate.user_data);
  }
}

void destroy_output(LockOutput* output) {
  if (output->lock_surface != nullptr) {
    wl_proxy_marshal_flags(output->lock_surface, kSurfaceDestroy, nullptr,
                           wl_proxy_get_version(output->lock_surface),
                           WL_MARSHAL_FLAG_DESTROY);
    output->lock_surface = nullptr;
  }
  if (output->window != nullptr) {
    gtk_widget_destroy(GTK_WIDGET(output->window));
    output->window = nullptr;
  }
  delete output;
}

void surface_configure(void* data, struct wl_proxy* surface, uint32_t serial,
                       uint32_t width, uint32_t height) {
  auto* output = static_cast<LockOutput*>(data);
  wl_proxy_marshal_flags(surface, kSurfaceAckConfigure, nullptr,
                         wl_proxy_get_version(surface), 0, serial);
  if (output->window == nullptr) return;
  if (width > 0 && height > 0) {
    gtk_widget_set_size_request(GTK_WIDGET(output->window), width, height);
    gtk_window_resize(output->window, width, height);
  }
  if (!output->shown) {
    output->shown = true;
    gtk_widget_show(GTK_WIDGET(output->window));
    gtk_widget_grab_focus(GTK_WIDGET(output->view));
  }
  wl_display_flush(state.display);
}

const void* surface_listener[] = {
    reinterpret_cast<const void*>(surface_configure),
};

void add_output(GdkMonitor* monitor) {
  if (state.lock == nullptr) return;
  struct wl_output* wl_output = gdk_wayland_monitor_get_wl_output(monitor);
  if (wl_output == nullptr) return;

  auto* output = new LockOutput();
  output->monitor = monitor;
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(state.application));
  gtk_window_set_title(window, "pangolin-lock");
  gtk_window_set_decorated(window, FALSE);
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  gtk_window_set_default_size(window, geometry.width, geometry.height);

  FlView* view = fl_view_new_for_engine(state.engine);
  GdkRGBA black = {0, 0, 0, 1};
  fl_view_set_background_color(view, &black);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  output->window = window;
  output->view = view;

  // The surface gets the lock surface role instead of an xdg_toplevel one.
  gtk_widget_realize(GTK_WIDGET(window));
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  gdk_wayland_window_set_use_custom_surface(gdk_window);
  gtk_widget_realize(GTK_WIDGET(view));
  struct wl_surface* surface = gdk_wayland_window_get_wl_surface(gdk_window);
  if (surface == nullptr) {
    destroy_output(output);
    return;
  }
  output->lock_surface = wl_proxy_marshal_flags(
      state.lock, kLockGetLockSurface, &ext_session_lock_surface_v1_interface,
      wl_proxy_get_version(state.lock), 0, nullptr, surface, wl_output);
  wl_proxy_add_listener(output->lock_surface,
                        reinterpret_cast<void (**)(void)>(
                            const_cast<void**>(surface_listener)),
                        output);
  state.outputs.push_back(output);
  // The window is shown (and draws) once the size is known.
  wl_display_roundtrip_queue(state.display, state.queue);
  notify_views();
}

void monitor_added_cb(GdkDisplay*, GdkMonitor* monitor, gpointer) {
  add_output(monitor);
}

void monitor_removed_cb(GdkDisplay*, GdkMonitor* monitor, gpointer) {
  for (auto it = state.outputs.begin(); it != state.outputs.end(); ++it) {
    if ((*it)->monitor == monitor) {
      destroy_output(*it);
      state.outputs.erase(it);
      notify_views();
      return;
    }
  }
}

void finish(const char* state_name) {
  for (LockOutput* output : state.outputs) destroy_output(output);
  state.outputs.clear();
  GdkDisplay* gdk_display = gdk_display_get_default();
  if (state.monitor_added != 0) {
    g_signal_handler_disconnect(gdk_display, state.monitor_added);
    state.monitor_added = 0;
  }
  if (state.monitor_removed != 0) {
    g_signal_handler_disconnect(gdk_display, state.monitor_removed);
    state.monitor_removed = 0;
  }
  if (state.dispatch_source != 0) {
    g_source_remove(state.dispatch_source);
    state.dispatch_source = 0;
  }
  state.locked = false;
  wl_display_flush(state.display);
  notify_views();
  notify_state(state_name);
}

void lock_locked(void*, struct wl_proxy*) {
  state.locked = true;
  notify_state("locked");
}

// The compositor won't lock (or no longer keeps this lock): the protocol
// asks for a plain destroy then.
void lock_finished(void*, struct wl_proxy* lock) {
  if (state.lock != lock) return;
  wl_proxy_marshal_flags(lock, kLockDestroy, nullptr,
                         wl_proxy_get_version(lock), WL_MARSHAL_FLAG_DESTROY);
  state.lock = nullptr;
  finish(state.locked ? "unlocked" : "denied");
}

const void* lock_listener[] = {
    reinterpret_cast<const void*>(lock_locked),
    reinterpret_cast<const void*>(lock_finished),
};

}  // namespace

bool session_lock_supported() {
  ensure_manager();
  return state.manager != nullptr;
}

bool session_lock_active() { return state.lock != nullptr; }

bool session_lock_lock(GtkApplication* application, FlEngine* engine,
                       const SessionLockDelegate& delegate) {
  ensure_manager();
  if (state.manager == nullptr || state.lock != nullptr) return false;
  state.application = application;
  state.engine = engine;
  state.delegate = delegate;
  state.locked = false;
  state.lock = wl_proxy_marshal_flags(
      state.manager, kManagerLock, &ext_session_lock_v1_interface,
      wl_proxy_get_version(state.manager), 0, nullptr);
  wl_proxy_add_listener(
      state.lock,
      reinterpret_cast<void (**)(void)>(const_cast<void**>(lock_listener)),
      nullptr);
  state.dispatch_source = g_timeout_add(16, dispatch_cb, nullptr);

  GdkDisplay* gdk_display = gdk_display_get_default();
  for (int i = 0; i < gdk_display_get_n_monitors(gdk_display); i++) {
    add_output(gdk_display_get_monitor(gdk_display, i));
  }
  state.monitor_added = g_signal_connect(
      gdk_display, "monitor-added", G_CALLBACK(monitor_added_cb), nullptr);
  state.monitor_removed = g_signal_connect(
      gdk_display, "monitor-removed", G_CALLBACK(monitor_removed_cb), nullptr);
  wl_display_flush(state.display);
  return true;
}

void session_lock_unlock() {
  if (state.lock == nullptr) return;
  wl_proxy_marshal_flags(state.lock,
                         state.locked ? kLockUnlockAndDestroy : kLockDestroy,
                         nullptr, wl_proxy_get_version(state.lock),
                         WL_MARSHAL_FLAG_DESTROY);
  state.lock = nullptr;
  // Make sure river unlocks before the lock surfaces go away (river would
  // show a solid color in their place for a frame otherwise).
  wl_display_roundtrip_queue(state.display, state.queue);
  finish("unlocked");
}

std::vector<int64_t> session_lock_view_ids() {
  std::vector<int64_t> ids;
  for (LockOutput* output : state.outputs) {
    if (output->view != nullptr) ids.push_back(fl_view_get_id(output->view));
  }
  return ids;
}

#else

bool session_lock_supported() { return false; }
bool session_lock_lock(GtkApplication*, FlEngine*, const SessionLockDelegate&) {
  return false;
}
void session_lock_unlock() {}
bool session_lock_active() { return false; }
std::vector<int64_t> session_lock_view_ids() { return {}; }

#endif
