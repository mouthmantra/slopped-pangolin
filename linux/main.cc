#include <cstring>

#include "check_password.h"
#include "my_application.h"

int main(int argc, char** argv) {
  // The lock screen's password check (session/native/check_password.cc).
  if (argc == 4 && strcmp(argv[1], "--check-password") == 0) {
    return pangolin_check_password(argv[2], argv[3]);
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
