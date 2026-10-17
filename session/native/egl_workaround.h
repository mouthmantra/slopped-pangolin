// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0
//
// Works around Flutter's GTK embedder aborting in libepoxy: it destroys EGL
// images on the main thread with no EGL context current, and libepoxy, which
// resolves EGL extension functions on their first call by looking at the
// current display, then finds no provider and calls abort(). Shared by the
// Pangolin shell and the dahliaOS apps.

#ifndef PANGOLIN_EGL_WORKAROUND_H_
#define PANGOLIN_EGL_WORKAROUND_H_

#include <gtk/gtk.h>

// Resolves the EGL extension functions Flutter uses, while a GL context of
// [widget]'s (realized) window is current. Only the first call does anything.
void pangolin_prepare_egl(GtkWidget* widget);

#endif  // PANGOLIN_EGL_WORKAROUND_H_
