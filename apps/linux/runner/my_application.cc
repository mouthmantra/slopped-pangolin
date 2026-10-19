#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "egl_workaround.h"
#include "river_blur.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  const DahliaAppInfo* app;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* blur_channel;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  // The human-readable name (window lists, GNOME's overview and window
  // switcher); plugins hooking the window reset it to the program name
  // (io.dahliaos.<app>).
  if (GTK_IS_WINDOW(toplevel)) {
    gtk_window_set_title(GTK_WINDOW(toplevel), self->app->title);
  }
  gtk_widget_show(toplevel);
}

// dahliaOS windows have a soft shadow and, when Settings asks for it, a
// hairline around them as macOS draws (Dart sends its color: setBorder).
// libhandy/Adwaita's own ring and top highlight are turned off. The radius is
// the dahliaOS windows' (DahliaTitlebar.windowRadius).
static const char* kWindowCssFormat =
    // GTK rounds the window itself (its theme's default is 8px).
    "window.csd, window.unified, window.solid-csd {"
    "  border: none; outline: none; border-radius: 12px; }"
    "decoration, decoration:backdrop {"
    "  border: none; border-radius: 12px;"
    "  box-shadow: %s; }"
    "window.maximized, window.fullscreen, window.tiled, window.tiled-top,"
    "window.tiled-left, window.tiled-right, window.tiled-bottom,"
    "window.maximized decoration, window.fullscreen decoration,"
    "window.tiled decoration, window.tiled-top decoration,"
    "window.tiled-left decoration, window.tiled-right decoration,"
    "window.tiled-bottom decoration {"
    "  box-shadow: none; border-radius: 0; }"
    "decoration-overlay, window.unified > decoration-overlay {"
    "  box-shadow: none; border: none; }"
    // Translucent title bars show what river blurs behind the window.
    "window.background, window.csd, window.unified {"
    "  background-color: transparent; }";

static GtkCssProvider* window_css = nullptr;

// [ring]: the hairline's CSS color, empty for none.
static void load_window_css(const gchar* ring) {
  if (window_css == nullptr) return;
  g_autofree gchar* shadow =
      ring != nullptr && *ring != '\0'
          ? g_strdup_printf("0 0 0 1px %s, 0 4px 18px rgba(0, 0, 0, 0.28)", ring)
          : g_strdup("0 4px 18px rgba(0, 0, 0, 0.28)");
  g_autofree gchar* css = g_strdup_printf(kWindowCssFormat, shadow);
  gtk_css_provider_load_from_data(window_css, css, -1, nullptr);
}

static void install_window_css() {
  GdkScreen* screen = gdk_screen_get_default();
  if (screen == nullptr || window_css != nullptr) return;
  window_css = gtk_css_provider_new();
  load_window_css(nullptr);
  gtk_style_context_add_provider_for_screen(
      screen, GTK_STYLE_PROVIDER(window_css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
}

// PANGOLIN_RENDERER=skia|impeller picks Flutter's renderer (see
// apply_renderer_choice's caller for the default).
static void apply_renderer_choice(FlDartProject* project, gboolean impeller) {
  const gchar* choice = g_getenv("PANGOLIN_RENDERER");
  if (choice != nullptr && g_strcmp0(choice, "skia") == 0) impeller = FALSE;
  if (choice != nullptr && g_strcmp0(choice, "impeller") == 0) impeller = TRUE;
  fl_dart_project_set_enable_impeller(project, impeller);
}

// io.dahliaos.apps/blur: frosted glass behind parts of the window, drawn by
// river (see session/native/river_blur.h).
static void blur_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "blurSupported") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(river_blur_supported())));
  } else if (strcmp(method, "setBlurRegions") == 0) {
    FlValue* regions = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                           ? fl_value_lookup_string(args, "regions")
                           : nullptr;
    river_blur_set_regions(self->window, GTK_WIDGET(self->view),
                           river_blur_regions_from_value(regions));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// io.dahliaos.apps/window: the desktop portal's dialogs (file chooser,
// open with) belong to the window of the app that asked: setParent takes
// that window's exported handle ("wayland:<handle>", xdg-foreign), and the
// window manager keeps the dialog above it, centered on it.
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "setParent") == 0) {
    gboolean done = FALSE;
#ifdef GDK_WINDOWING_WAYLAND
    const gchar* handle = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING
                              ? fl_value_get_string(args)
                              : nullptr;
    if (handle != nullptr && g_str_has_prefix(handle, "wayland:")) {
      gtk_widget_realize(GTK_WIDGET(self->window));
      GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->window));
      if (gdk_window != nullptr && GDK_IS_WAYLAND_WINDOW(gdk_window)) {
        g_autofree gchar* exported = g_strdup(handle + strlen("wayland:"));
        done = gdk_wayland_window_set_transient_for_exported(gdk_window, exported);
      }
    }
#endif
    response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(done)));
  } else if (strcmp(method, "setBorder") == 0) {
    load_window_css(args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING
                        ? fl_value_get_string(args)
                        : nullptr);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  install_window_css();
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // dahliaOS applications draw their own title bar (ZenitWindowTitlebar) and
  // rely on handy_window for rounded corners, shadows and resize borders.
  gtk_window_set_title(window, self->app->title);
  g_autofree gchar* icon = g_strdup_printf("io.dahliaos.%s", self->app->name);
  gtk_window_set_icon_name(window, icon);
  gtk_window_set_default_size(window, self->app->width, self->app->height);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  apply_renderer_choice(project, TRUE);
  // Dart on its own thread: there each frame starts on time (this thread's
  // task runner wakes in whole milliseconds, 1.7 ms late on average, a third
  // of a 165 Hz frame) and builds while GTK draws the previous one.
  fl_dart_project_set_ui_thread_policy(
      project, FL_UI_THREAD_POLICY_RUN_ON_SEPARATE_THREAD);
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Known before Dart starts, so the app doesn't have to ask over a channel
  // (whose answer waits for this thread, busy showing the window then).
  g_setenv("PANGOLIN_RIVER_BLUR", river_blur_supported() ? "1" : "0", TRUE);

  FlView* view = fl_view_new(project);
  // Transparent so the rounded window corners don't show a black background.
  GdkRGBA background_color = {0, 0, 0, 0};
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  self->window = window;
  self->view = view;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->blur_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.dahliaos.apps/blur", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->blur_channel,
                                            blur_method_call_cb, self, nullptr);
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "io.dahliaos.apps/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, self, nullptr);

  // handy_window has to hook the window before it is shown.
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  gtk_window_set_title(window, self->app->title);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));
  pangolin_prepare_egl(GTK_WIDGET(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Pass the application name and its arguments on to Dart.
  gchar** args = *arguments;
  if (args[0] != nullptr && args[1] != nullptr) {
    self->dart_entrypoint_arguments = g_strdupv(args + 1);
  } else {
    const gchar* fallback[] = {self->app->name, nullptr};
    self->dart_entrypoint_arguments = g_strdupv(const_cast<gchar**>(fallback));
  }

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
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new(const DahliaAppInfo* app) {
  g_autofree gchar* application_id = g_strdup_printf("io.dahliaos.%s", app->name);

  // The program name becomes the Wayland app_id and lets desktops map the
  // window to its desktop entry (io.dahliaos.<name>.desktop).
  g_set_prgname(application_id);

  MyApplication* self = MY_APPLICATION(
      g_object_new(my_application_get_type(), "application-id", application_id,
                   "flags", G_APPLICATION_NON_UNIQUE, nullptr));
  self->app = app;
  return self;
}
