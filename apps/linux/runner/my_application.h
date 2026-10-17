#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

typedef struct {
  const char* name;
  const char* title;
  int width;
  int height;
} DahliaAppInfo;

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 * @app: the dahliaOS application to run.
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #MyApplication.
 */
MyApplication* my_application_new(const DahliaAppInfo* app);

#endif  // FLUTTER_MY_APPLICATION_H_
