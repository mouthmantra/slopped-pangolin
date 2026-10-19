#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef HAVE_GTK_LAYER_SHELL
#include <gtk-layer-shell/gtk-layer-shell.h>
#endif

#include <dlfcn.h>

#include <cstring>

#include "flutter/generated_plugin_registrant.h"
#include "egl_workaround.h"
#include "river_blur.h"
#include "session_lock.h"

// gtk-layer-shell gets the commit that applies a change (keyboard mode) by
// invalidating the whole window: a full repaint, 59 MB of it at 4K. While
// set, that becomes one pixel, which commits all the same.
static bool commit_with_one_pixel = false;

extern "C" __attribute__((visibility("default"))) void
gdk_window_invalidate_rect(GdkWindow* window,
                           const GdkRectangle* rect,
                           gboolean invalidate_children) {
  using Invalidate = void (*)(GdkWindow*, const GdkRectangle*, gboolean);
  static Invalidate real = reinterpret_cast<Invalidate>(
      dlsym(RTLD_NEXT, "gdk_window_invalidate_rect"));
  static const GdkRectangle pixel = {0, 0, 1, 1};
  real(window, rect == nullptr && commit_with_one_pixel ? &pixel : rect,
       invalidate_children);
}

// Pangolin runs in one of two modes:
//
//  * Session mode: Pangolin is the desktop shell of a Wayland session (river).
//    A single Flutter engine renders two views, each on its own layer-shell
//    surface: the desktop (wallpaper, BACKGROUND layer) and the shell (taskbar,
//    launcher, overlays, notifications; transparent, TOP layer). The window
//    manager itself is implemented in Dart and talks to river directly.
//
//  * Windowed mode: the whole shell lives inside one regular window. Used for
//    development on other desktops and selected with --windowed or whenever
//    the compositor has no layer-shell support.
//
// Dart drives the session surfaces through the io.dahliaos.pangolin/session
// method channel.

static constexpr char kSessionChannel[] = "io.dahliaos.pangolin/session";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean force_windowed;

  FlEngine* engine;
  FlMethodChannel* session_channel;

  // Session mode surfaces, indexed by role.
  GtkWindow* desktop_window;
  GtkWindow* shell_window;
  FlView* desktop_view;
  FlView* shell_view;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean layer_shell_available(MyApplication* self) {
#ifdef HAVE_GTK_LAYER_SHELL
  if (self->force_windowed) return FALSE;
#ifdef GDK_WINDOWING_WAYLAND
  if (!GDK_IS_WAYLAND_DISPLAY(gdk_display_get_default())) return FALSE;
#endif
  return gtk_layer_is_supported();
#else
  return FALSE;
#endif
}

static GtkWindow* window_for_view_id(MyApplication* self, int64_t view_id) {
  if (self->desktop_view != nullptr &&
      fl_view_get_id(self->desktop_view) == view_id) {
    return self->desktop_window;
  }
  if (self->shell_view != nullptr &&
      fl_view_get_id(self->shell_view) == view_id) {
    return self->shell_window;
  }
  return nullptr;
}

static FlMethodResponse* get_session_info(MyApplication* self) {
  g_autoptr(FlValue) result = fl_value_new_map();
  const gboolean session = self->shell_view != nullptr;
  fl_value_set_string_take(result, "mode",
                           fl_value_new_string(session ? "session" : "windowed"));
  if (session) {
    fl_value_set_string_take(result, "desktopView",
                             fl_value_new_int(fl_view_get_id(self->desktop_view)));
    fl_value_set_string_take(result, "shellView",
                             fl_value_new_int(fl_view_get_id(self->shell_view)));
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// Shows a session surface again: GTK makes it a new wl_surface and
// gtk-layer-shell a new layer surface, which river puts on the window
// manager's default output (where the shell should be).
static void remap_layer_window(GtkWindow* window) {
  if (window == nullptr || !gtk_widget_get_visible(GTK_WIDGET(window))) return;
  gtk_widget_hide(GTK_WIDGET(window));
  gtk_widget_show(GTK_WIDGET(window));
}

static gboolean remap_closed_window(gpointer data) {
  // With no monitor left river would close the new surface at once (a busy
  // loop); the shell remaps when one comes back (remapSurfaces).
  if (gdk_display_get_n_monitors(gtk_widget_get_display(GTK_WIDGET(data))) > 0)
    remap_layer_window(GTK_WINDOW(data));
  g_object_unref(data);
  return G_SOURCE_REMOVE;
}

// river closes a layer surface whose output goes away (the monitor it was
// on was unplugged or turned off), and gtk-layer-shell closes its window
// then: keep the window and show it again, on the remaining monitors.
static gboolean layer_window_delete_cb(GtkWidget* widget, GdkEvent*, gpointer) {
  g_idle_add(remap_closed_window, g_object_ref(widget));
  return TRUE;
}

static FlMethodResponse* remap_surfaces(MyApplication* self) {
  remap_layer_window(self->desktop_window);
  remap_layer_window(self->shell_window);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* show_surfaces(MyApplication* self, FlValue* args) {
  // The login screen draws everything on the shell surface: its desktop
  // surface would only be one more full-screen layer to composite.
  FlValue* desktop = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                         ? fl_value_lookup_string(args, "desktop")
                         : nullptr;
  const gboolean show_desktop =
      desktop == nullptr || fl_value_get_type(desktop) != FL_VALUE_TYPE_BOOL ||
      fl_value_get_bool(desktop);
  if (self->desktop_window != nullptr && show_desktop) {
    gtk_widget_show(GTK_WIDGET(self->desktop_window));
  }
  if (self->shell_window != nullptr) {
    gtk_widget_show(GTK_WIDGET(self->shell_window));
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

// Restricts pointer input on a surface to a list of [x, y, w, h] rectangles so
// that the transparent parts of the shell let clicks through to the windows
// below. A null rect list makes the whole surface interactive again.
static FlMethodResponse* set_input_region(MyApplication* self, FlValue* args) {
  FlValue* view_value = fl_value_lookup_string(args, "view");
  FlValue* rects = fl_value_lookup_string(args, "rects");
  if (view_value == nullptr || fl_value_get_type(view_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected an integer 'view'", nullptr));
  }

  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  GdkWindow* gdk_window =
      window != nullptr ? gtk_widget_get_window(GTK_WIDGET(window)) : nullptr;
  if (gdk_window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }

  if (rects == nullptr || fl_value_get_type(rects) != FL_VALUE_TYPE_LIST) {
    gdk_window_input_shape_combine_region(gdk_window, nullptr, 0, 0);
  } else {
    cairo_region_t* region = cairo_region_create();
    for (size_t i = 0; i < fl_value_get_length(rects); i++) {
      FlValue* rect = fl_value_get_list_value(rects, i);
      if (fl_value_get_type(rect) != FL_VALUE_TYPE_LIST ||
          fl_value_get_length(rect) != 4) {
        continue;
      }
      cairo_rectangle_int_t r = {
          static_cast<int>(fl_value_get_int(fl_value_get_list_value(rect, 0))),
          static_cast<int>(fl_value_get_int(fl_value_get_list_value(rect, 1))),
          static_cast<int>(fl_value_get_int(fl_value_get_list_value(rect, 2))),
          static_cast<int>(fl_value_get_int(fl_value_get_list_value(rect, 3))),
      };
      cairo_region_union_rectangle(region, &r);
    }
    gdk_window_input_shape_combine_region(gdk_window, region, 0, 0);
    cairo_region_destroy(region);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

static FlMethodResponse* set_keyboard_mode(MyApplication* self, FlValue* args) {
#ifdef HAVE_GTK_LAYER_SHELL
  FlValue* view_value = fl_value_lookup_string(args, "view");
  FlValue* mode_value = fl_value_lookup_string(args, "mode");
  if (view_value == nullptr || mode_value == nullptr ||
      fl_value_get_type(mode_value) != FL_VALUE_TYPE_STRING) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected 'view' and 'mode'", nullptr));
  }

  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  if (window == nullptr || !gtk_layer_is_layer_window(window)) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }

  const gchar* mode = fl_value_get_string(mode_value);
  GtkLayerShellKeyboardMode keyboard_mode = GTK_LAYER_SHELL_KEYBOARD_MODE_NONE;
  if (strcmp(mode, "exclusive") == 0) {
    keyboard_mode = GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE;
  } else if (strcmp(mode, "on_demand") == 0) {
    keyboard_mode = GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND;
  }
  commit_with_one_pixel = true;
  gtk_layer_set_keyboard_mode(window, keyboard_mode);
  commit_with_one_pixel = false;
  if (keyboard_mode != GTK_LAYER_SHELL_KEYBOARD_MODE_NONE) {
    gtk_window_present(window);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
#else
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
#endif
}

// Frosted glass: river blurs what is below these rounded rectangles of a
// surface (see session/native/river_blur.h).
static FlMethodResponse* set_blur_regions(MyApplication* self, FlValue* args) {
  FlValue* view_value = fl_value_lookup_string(args, "view");
  if (view_value == nullptr || fl_value_get_type(view_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected an integer 'view'", nullptr));
  }
  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  if (window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }
  river_blur_set_regions(
      window, nullptr,
      river_blur_regions_from_value(fl_value_lookup_string(args, "regions")));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

// Session lock: the lock screen views and state go to Dart.
static void lock_state_changed(const char* state, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->session_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "state", fl_value_new_string(state));
  fl_method_channel_invoke_method(self->session_channel, "lockStateChanged",
                                  args, nullptr, nullptr, nullptr);
}

static FlValue* lock_views_value() {
  FlValue* views = fl_value_new_list();
  for (int64_t id : session_lock_view_ids()) {
    fl_value_append_take(views, fl_value_new_int(id));
  }
  return views;
}

static void lock_views_changed(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->session_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "views", lock_views_value());
  fl_method_channel_invoke_method(self->session_channel, "lockViewsChanged",
                                  args, nullptr, nullptr, nullptr);
}

static FlMethodResponse* lock_session(MyApplication* self) {
  SessionLockDelegate delegate = {lock_state_changed, lock_views_changed, self};
  const bool started =
      self->engine != nullptr &&
      session_lock_lock(GTK_APPLICATION(self), self->engine, delegate);
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "started", fl_value_new_bool(started));
  fl_value_set_string_take(result, "views", lock_views_value());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// args: {view, values: [reveal (0/1), x, y, width, height, dx, dy,
// scale x 10000, opacity x 10000, duration ms, curve x1, y1, x2, y2 x 10000]}
static FlMethodResponse* animate_part(MyApplication* self, FlValue* args) {
  FlValue* view_value = fl_value_lookup_string(args, "view");
  FlValue* values = fl_value_lookup_string(args, "values");
  if (view_value == nullptr || fl_value_get_type(view_value) != FL_VALUE_TYPE_INT ||
      values == nullptr || fl_value_get_type(values) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(values) != 14) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected 'view' and 14 'values'", nullptr));
  }
  int32_t v[14];
  for (size_t i = 0; i < 14; i++) {
    FlValue* value = fl_value_get_list_value(values, i);
    if (fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
      return FL_METHOD_RESPONSE(fl_method_error_response_new(
          "bad-args", "'values' must be integers", nullptr));
    }
    v[i] = static_cast<int32_t>(fl_value_get_int(value));
  }
  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  if (window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }
  const int32_t curve[4] = {v[10], v[11], v[12], v[13]};
  river_blur_animate_part(window, nullptr, v[0] != 0, v[1], v[2], v[3], v[4],
                          {v[5], v[6], v[7], v[8]},
                          static_cast<uint32_t>(v[9] < 0 ? 0 : v[9]), curve);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

// Integer values of a list argument, or false.
static gboolean int_values(FlValue* args, const char* key, int32_t* out,
                           size_t count) {
  FlValue* values = fl_value_lookup_string(args, key);
  if (values == nullptr || fl_value_get_type(values) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(values) != count) {
    return FALSE;
  }
  for (size_t i = 0; i < count; i++) {
    FlValue* value = fl_value_get_list_value(values, i);
    if (fl_value_get_type(value) != FL_VALUE_TYPE_INT) return FALSE;
    out[i] = static_cast<int32_t>(fl_value_get_int(value));
  }
  return TRUE;
}

// Only a part of a surface is drawn by river (the shell surface while only
// the taskbar shows): 'area' [x, y, width, height], or null for all of it.
static FlMethodResponse* set_visible_area(MyApplication* self, FlValue* args) {
  FlValue* view_value = fl_value_lookup_string(args, "view");
  if (view_value == nullptr || fl_value_get_type(view_value) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected an integer 'view'", nullptr));
  }
  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  if (window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }
  int32_t area[4] = {0, 0, 0, 0};
  int_values(args, "area", area, 4);
  river_blur_set_visible_area(window, area[0], area[1], area[2], area[3]);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

// A color animated over a part of a surface by river ('values': ARGB
// color, x, y, width, height, duration in ms, cubic-bezier x1, y1, x2, y2
// times 10000).
static FlMethodResponse* set_tint(MyApplication* self, FlValue* args) {
  FlValue* view_value = fl_value_lookup_string(args, "view");
  int32_t v[10];
  if (view_value == nullptr || fl_value_get_type(view_value) != FL_VALUE_TYPE_INT ||
      !int_values(args, "values", v, 10)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "expected 'view' and 10 'values'", nullptr));
  }
  GtkWindow* window = window_for_view_id(self, fl_value_get_int(view_value));
  if (window == nullptr) {
    return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(FALSE)));
  }
  const int32_t area[4] = {v[1], v[2], v[3], v[4]};
  const int32_t curve[4] = {v[6], v[7], v[8], v[9]};
  river_blur_set_tint(window, static_cast<uint32_t>(v[0]), area,
                      static_cast<uint32_t>(v[5] < 0 ? 0 : v[5]), curve);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
}

static void session_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* method_call,
                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "getSessionInfo") == 0) {
    response = get_session_info(self);
  } else if (strcmp(method, "showSurfaces") == 0) {
    response = show_surfaces(self, fl_method_call_get_args(method_call));
  } else if (strcmp(method, "remapSurfaces") == 0) {
    response = remap_surfaces(self);
  } else if (strcmp(method, "setInputRegion") == 0) {
    response = set_input_region(self, args);
  } else if (strcmp(method, "setVisibleArea") == 0) {
    response = set_visible_area(self, args);
  } else if (strcmp(method, "setTint") == 0) {
    response = set_tint(self, args);
  } else if (strcmp(method, "tintsSupported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(river_blur_tints_supported())));
  } else if (strcmp(method, "setKeyboardMode") == 0) {
    response = set_keyboard_mode(self, args);
  } else if (strcmp(method, "blurSupported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(river_blur_supported())));
  } else if (strcmp(method, "setBlurRegions") == 0) {
    response = set_blur_regions(self, args);
  } else if (strcmp(method, "lockSupported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(session_lock_supported())));
  } else if (strcmp(method, "lock") == 0) {
    response = lock_session(self);
  } else if (strcmp(method, "unlock") == 0) {
    session_lock_unlock();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "animationsSupported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(river_blur_animations_supported())));
  } else if (strcmp(method, "animatePart") == 0) {
    response = animate_part(self, args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to %s: %s", method, error->message);
  }
}

static void setup_session_channel(MyApplication* self) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->session_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(self->engine), kSessionChannel,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->session_channel,
                                            session_method_call_cb, self,
                                            nullptr);
}

// PANGOLIN_PROFILE=frames: what GTK repaints of a session surface, on the
// clock of the frame logs.
static gboolean profile_draw_cb(GtkWidget* widget, cairo_t* cr,
                                gpointer name) {
  cairo_rectangle_list_t* rects = cairo_copy_clip_rectangle_list(cr);
  double area = 0;
  double x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  if (rects->status == CAIRO_STATUS_SUCCESS) {
    for (int i = 0; i < rects->num_rectangles; i++) {
      const cairo_rectangle_t& r = rects->rectangles[i];
      area += r.width * r.height;
      x0 = MIN(x0, r.x);
      y0 = MIN(y0, r.y);
      x1 = MAX(x1, r.x + r.width);
      y1 = MAX(y1, r.y + r.height);
    }
  }
  g_printerr("Pangolin: repaint %s at %" G_GINT64_FORMAT
             "ms: %d rects, %.0f px, extents %.0fx%.0f at %.0f,%.0f\n",
             static_cast<const char*>(name), g_get_monotonic_time() / 1000,
             rects->num_rectangles, area, x1 - x0, y1 - y0, x0, y0);
  cairo_rectangle_list_destroy(rects);
  return FALSE;
}

#ifdef HAVE_GTK_LAYER_SHELL
static GtkWindow* create_layer_window(MyApplication* self,
                                      FlView* view,
                                      GtkLayerShellLayer layer,
                                      const gchar* name_space,
                                      gboolean transparent) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_window_set_title(window, name_space);

  gtk_layer_init_for_window(window);
  gtk_layer_set_namespace(window, name_space);
  gtk_layer_set_layer(window, layer);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
  gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
  // Pangolin's own window manager keeps app windows clear of the taskbar, so
  // the surfaces cover the whole output and ignore exclusive zones.
  gtk_layer_set_exclusive_zone(window, -1);
  gtk_layer_set_keyboard_mode(window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);

  if (transparent) {
    GdkScreen* screen = gtk_window_get_screen(window);
    GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
    if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
    gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
    GdkRGBA clear = {0, 0, 0, 0};
    fl_view_set_background_color(view, &clear);
  }

  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // The window's focus widget: keys reach Flutter from the moment the
  // surface has the keyboard (the login screen, the launcher opened with
  // Super), not only after a click on it.
  gtk_widget_grab_focus(GTK_WIDGET(view));
  g_signal_connect(window, "delete-event", G_CALLBACK(layer_window_delete_cb),
                   nullptr);
  if (g_strcmp0(g_getenv("PANGOLIN_PROFILE"), "frames") == 0) {
    g_signal_connect(view, "draw", G_CALLBACK(profile_draw_cb),
                     const_cast<gchar*>(name_space));
  }
  // The window stays unmapped until Dart reports that the window manager is
  // bound: river destroys layer surfaces created before that point. Realizing
  // (without mapping) is enough for the view to start the engine, which only
  // happens once the implicit view's renderer is realized.
  gtk_widget_realize(GTK_WIDGET(window));
  gtk_widget_realize(GTK_WIDGET(view));
  pangolin_prepare_egl(GTK_WIDGET(view));
  return window;
}
#endif

static void activate_session(MyApplication* self, FlDartProject* project) {
#ifdef HAVE_GTK_LAYER_SHELL
  self->desktop_view = fl_view_new(project);
  self->engine = fl_view_get_engine(self->desktop_view);
  self->desktop_window =
      create_layer_window(self, self->desktop_view,
                          GTK_LAYER_SHELL_LAYER_BACKGROUND, "pangolin-desktop",
                          TRUE);

  // Secondary views can only be added once the engine is running.
  self->shell_view = fl_view_new_for_engine(self->engine);
  self->shell_window =
      create_layer_window(self, self->shell_view, GTK_LAYER_SHELL_LAYER_TOP,
                          "pangolin-shell", TRUE);

  // Nothing on the shell surface is interactive until Dart says otherwise.
  GdkWindow* shell_gdk = gtk_widget_get_window(GTK_WIDGET(self->shell_window));
  cairo_region_t* empty = cairo_region_create();
  gdk_window_input_shape_combine_region(shell_gdk, empty, 0, 0);
  cairo_region_destroy(empty);
#endif
}

static void activate_windowed(MyApplication* self, FlDartProject* project) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Pangolin");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Pangolin");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  self->engine = fl_view_get_engine(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// PANGOLIN_RENDERER=skia|impeller picks Flutter's renderer (see
// apply_renderer_choice's caller for the default).
static void apply_renderer_choice(FlDartProject* project, gboolean impeller) {
  const gchar* choice = g_getenv("PANGOLIN_RENDERER");
  if (choice != nullptr && g_strcmp0(choice, "skia") == 0) impeller = FALSE;
  if (choice != nullptr && g_strcmp0(choice, "impeller") == 0) impeller = TRUE;
  fl_dart_project_set_enable_impeller(project, impeller);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  apply_renderer_choice(project, TRUE);
  // Dart on its own thread: there each frame starts on time (this thread's
  // task runner wakes in whole milliseconds, 1.7 ms late on average, a third
  // of a 165 Hz frame) and builds while GTK draws the previous one.
  fl_dart_project_set_ui_thread_policy(
      project, FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD);
  fl_dart_project_set_dart_entrypoint_arguments(project,
                                                self->dart_entrypoint_arguments);

  if (layer_shell_available(self)) {
    activate_session(self, project);
  } else {
    activate_windowed(self, project);
  }

  setup_session_channel(self);
  // Window plugins (window_manager, url_launcher, ...) look up their view's
  // toplevel: give them the shell surface rather than no view at all, which
  // they don't handle. Their channels are per engine either way.
  if (self->shell_view != nullptr) {
    // handy_window would turn the layer window into a decorated toplevel
    // (it bails out, warning, as the view is realized already): GTK_CSD
    // other than 1 makes it stay out of the way quietly. Only for the
    // registration, so that apps started from the shell don't inherit it.
    g_autofree gchar* gtk_csd = g_strdup(g_getenv("GTK_CSD"));
    g_setenv("GTK_CSD", "0", TRUE);
    fl_register_plugins(FL_PLUGIN_REGISTRY(self->shell_view));
    if (gtk_csd != nullptr) {
      g_setenv("GTK_CSD", gtk_csd, TRUE);
    } else {
      g_unsetenv("GTK_CSD");
    }
  } else {
    fl_register_plugins(FL_PLUGIN_REGISTRY(self->engine));
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);

  // Strip out the first argument as it is the binary name, and consume the
  // runner-only --windowed flag.
  GPtrArray* dart_args = g_ptr_array_new();
  for (gchar** arg = *arguments + 1; *arg != nullptr; arg++) {
    if (strcmp(*arg, "--windowed") == 0) {
      self->force_windowed = TRUE;
      continue;
    }
    g_ptr_array_add(dart_args, g_strdup(*arg));
  }
  g_ptr_array_add(dart_args, nullptr);
  self->dart_entrypoint_arguments =
      reinterpret_cast<char**>(g_ptr_array_free(dart_args, FALSE));

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->session_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
