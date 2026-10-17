// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

#include "egl_workaround.h"

#ifdef GDK_WINDOWING_WAYLAND
#include <epoxy/egl.h>
#include <gdk/gdkwayland.h>

void pangolin_prepare_egl(GtkWidget* widget) {
  static bool done = false;
  if (done) return;
  GdkDisplay* gdk_display = gtk_widget_get_display(widget);
  if (gdk_display == nullptr || !GDK_IS_WAYLAND_DISPLAY(gdk_display)) return;
  GdkWindow* window = gtk_widget_get_window(widget);
  if (window == nullptr) return;

  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context = gdk_window_create_gl_context(window, &error);
  if (context == nullptr || !gdk_gl_context_realize(context, &error)) {
    g_warning("Cannot prepare EGL: %s", error != nullptr ? error->message : "?");
    return;
  }
  gdk_gl_context_make_current(context);
  EGLDisplay display = eglGetCurrentDisplay();
  if (display != EGL_NO_DISPLAY) {
    done = true;
    // Calls with invalid arguments: they fail harmlessly, but libepoxy
    // resolves each function for good on the way.
    if (epoxy_has_egl_extension(display, "EGL_KHR_image_base")) {
      eglDestroyImageKHR(display, EGL_NO_IMAGE_KHR);
      eglCreateImageKHR(display, EGL_NO_CONTEXT, 0, nullptr, nullptr);
    }
    if (epoxy_has_egl_extension(display, "EGL_KHR_fence_sync")) {
      eglDestroySyncKHR(display, EGL_NO_SYNC_KHR);
      eglClientWaitSyncKHR(display, EGL_NO_SYNC_KHR, 0, 0);
      eglCreateSyncKHR(display, 0, nullptr);
    }
    if (epoxy_has_egl_extension(display, "EGL_KHR_wait_sync")) {
      eglWaitSyncKHR(display, EGL_NO_SYNC_KHR, 0);
    }
    if (epoxy_has_egl_extension(display, "EGL_ANDROID_native_fence_sync")) {
      eglDupNativeFenceFDANDROID(display, EGL_NO_SYNC_KHR);
    }
    // Leave no error behind for whoever checks eglGetError() next.
    eglGetError();
  }
  gdk_gl_context_clear_current();
}

#else

void pangolin_prepare_egl(GtkWidget*) {}

#endif
