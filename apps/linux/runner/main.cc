#include <cstring>

#include "my_application.h"

// dahlia_apps is a multi-call binary: the first argument selects the
// application, e.g. `dahlia_apps files`. Each one runs as its own process with
// its own application id (io.dahliaos.<name>), which becomes the Wayland
// app_id the Pangolin taskbar uses to match windows with desktop entries.
static const DahliaAppInfo kApps[] = {
    {"settings", "Settings", 1100, 720},
    {"files", "Files", 1040, 660},
    {"store", "App Store", 1120, 740},
    {"clock", "Clock", 760, 560},
    {"welcome", "Welcome", 900, 620},
    {"terminal", "Terminal", 900, 560},
    {"calculator", "Calculator", 400, 620},
    {"activity_monitor", "Activity Monitor", 1000, 640},
    {"gallery", "Gallery", 1040, 680},
    {"text_editor", "Text Editor", 960, 660},
    {"logs", "Logs", 1080, 680},
    {"disks", "Disks", 1100, 720},
    // Dialogs of the desktop portal (session/portal) for other apps.
    {"file_chooser", "Choose a File", 940, 620},
    {"app_chooser", "Open With", 460, 580},
};

int main(int argc, char** argv) {
  const DahliaAppInfo* app = &kApps[4];  // welcome
  if (argc > 1) {
    app = nullptr;
    for (const DahliaAppInfo& candidate : kApps) {
      if (strcmp(argv[1], candidate.name) == 0) app = &candidate;
    }
    if (app == nullptr) {
      g_printerr("Unknown dahliaOS application '%s'. Available:", argv[1]);
      for (const DahliaAppInfo& candidate : kApps) {
        g_printerr(" %s", candidate.name);
      }
      g_printerr("\n");
      return 2;
    }
  }

  g_autoptr(MyApplication) application = my_application_new(app);
  return g_application_run(G_APPLICATION(application), argc, argv);
}
