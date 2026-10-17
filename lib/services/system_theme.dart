/*
Copyright 2026 The dahliaOS Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:async';
import 'dart:io';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:logging/logging.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

/// Makes other applications follow Pangolin's light/dark setting, through
/// the settings every toolkit reads (in Pangolin's own dconf database, see
/// DCONF_PROFILE in pangolin-session, so GNOME sessions keep theirs):
/// org.gnome.desktop.interface
/// color-scheme (served to GTK 4/libadwaita, Firefox, Chromium, Electron and
/// Qt 6 by the settings portal) and the GTK 3 theme (Adwaita / Adwaita-dark,
/// or the -dark variant of another installed theme).
abstract final class SystemTheme {
  static final Logger _logger = Logger("SystemTheme");
  static bool? _applied;
  static bool _available = true;

  static void follow() {
    // A nested session must not restyle the host desktop's apps.
    if (Platform.environment["PANGOLIN_NESTED"] == "1") return;
    final CustomizationService service = CustomizationService.current;
    void apply() => unawaited(_apply(service.darkMode));
    service.addListener(apply);
    apply();
    final PreferencesService prefs = PreferencesService.current;
    void applyCursor() => unawaited(
          _applyCursor(
            prefs.get<String>(SessionSetting.cursorTheme.key) ??
                SessionSetting.cursorTheme.defaultValue,
            prefs.get<int>(SessionSetting.cursorSize.key) ??
                SessionSetting.cursorSize.defaultValue,
          ),
        );
    prefs.addListener(applyCursor);
    applyCursor();
    void applyFonts() => unawaited(
          _applyFonts(
            prefs.get<String>(SessionSetting.interfaceFont.key) ?? "",
            prefs.get<String>(SessionSetting.monospaceFont.key) ?? "",
          ),
        );
    prefs.addListener(applyFonts);
    applyFonts();
  }

  static (String, String)? _fonts;

  /// The interface and monospace fonts for GTK, libadwaita, Qt (through
  /// the settings portal), Firefox and the terminal apps too. The default
  /// (empty) leaves the toolkits' own.
  static Future<void> _applyFonts(String ui, String mono) async {
    if (!_available || _fonts == (ui, mono)) return;
    _fonts = (ui, mono);
    try {
      for (final (String key, String family) in [
        ("font-name", ui),
        ("document-font-name", ui),
        ("monospace-font-name", mono),
      ]) {
        if (family.isEmpty) {
          await Process.run(
            "gsettings",
            ["reset", "org.gnome.desktop.interface", key],
          );
        } else {
          await _set(key, "$family 11");
        }
      }
    } on ProcessException {
      _available = false;
    }
  }

  static (String, int)? _cursor;

  /// GTK 3 and Flutter apps draw their own pointer: same theme as river's.
  static Future<void> _applyCursor(String theme, int size) async {
    if (!_available || _cursor == (theme, size)) return;
    _cursor = (theme, size);
    try {
      await _set("cursor-theme", theme);
      await _setInt("cursor-size", size);
    } on ProcessException {
      _available = false;
    }
  }

  static Future<void> _setIn(String schema, String key, String value) async {
    final ProcessResult result =
        await Process.run("gsettings", ["set", schema, key, value]);
    if (result.exitCode != 0) {
      _logger.info("Couldn't set $schema $key: ${result.stderr}".trim());
    }
  }

  static Future<void> _setInt(String key, int value) async {
    await Process.run(
      "gsettings",
      ["set", "org.gnome.desktop.interface", key, "$value"],
    );
  }

  static Future<void> _apply(bool dark) async {
    if (!_available || _applied == dark) return;
    _applied = dark;
    try {
      // Minimize, maximize and close in apps drawing their own title bars
      // (GTK, libadwaita, Firefox), like Pangolin's own windows.
      await _setIn(
        "org.gnome.desktop.wm.preferences",
        "button-layout",
        "appmenu:minimize,maximize,close",
      );
      await _set("color-scheme", dark ? "prefer-dark" : "default");
      final String? theme = await _get("gtk-theme");
      if (theme != null) {
        final String? wanted = _gtk3Theme(theme, dark);
        if (wanted != null && wanted != theme) await _set("gtk-theme", wanted);
      }
    } on ProcessException {
      _available = false;
      _logger.info("gsettings isn't available: other apps keep their theme");
    }
  }

  /// The light or dark variant of [theme], if it has one.
  static String? _gtk3Theme(String theme, bool dark) {
    final String base = theme.endsWith("-dark")
        ? theme.substring(0, theme.length - "-dark".length)
        : theme;
    if (!dark) return base;
    final String variant = "$base-dark";
    // Adwaita-dark is built into GTK 3.
    if (base == "Adwaita" || _themeExists(variant)) return variant;
    return null;
  }

  static bool _themeExists(String name) {
    final Map<String, String> env = Platform.environment;
    final String home = env["HOME"] ?? "";
    final String dataHome = env["XDG_DATA_HOME"] ?? "$home/.local/share";
    final List<String> dirs = [
      "$home/.themes",
      "$dataHome/themes",
      for (final String d
          in (env["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share").split(":"))
        if (d.isNotEmpty) "$d/themes",
    ];
    return dirs.any((d) => Directory("$d/$name/gtk-3.0").existsSync());
  }

  static Future<String?> _get(String key) async {
    final ProcessResult result = await Process.run(
      "gsettings",
      ["get", "org.gnome.desktop.interface", key],
    );
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim().replaceAll("'", "");
  }

  static Future<void> _set(String key, String value) async {
    final ProcessResult result = await Process.run(
      "gsettings",
      ["set", "org.gnome.desktop.interface", key, value],
    );
    if (result.exitCode != 0) {
      _logger.info("Couldn't set $key: ${result.stderr}".trim());
    }
  }
}
