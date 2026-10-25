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
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/gtk_theme.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

/// Makes other applications follow Pangolin's look, through the settings
/// every toolkit reads (in Pangolin's own dconf database, see DCONF_PROFILE
/// in pangolin-session, so GNOME sessions keep theirs):
/// org.gnome.desktop.interface
/// color-scheme (served to GTK 4/libadwaita, Firefox, Chromium, Electron and
/// Qt 6 by the settings portal) and the GTK theme: Pangolin's dahliaOS theme
/// for the accent color (GtkTheme), or with the Adwaita app style Adwaita /
/// Adwaita-dark (or the -dark variant of another installed theme).
abstract final class SystemTheme {
  static final Logger _logger = Logger("SystemTheme");
  static _Look? _applied;
  static Future<void> _queue = Future.value();
  static bool _available = true;

  /// Zenit's accent when none is set.
  static const Color _defaultAccent = Color(0xFF0073CF);

  static void follow() {
    // A nested session must not restyle the host desktop's apps.
    if (Platform.environment["PANGOLIN_NESTED"] == "1") return;
    final CustomizationService service = CustomizationService.current;
    final PreferencesService prefs = PreferencesService.current;
    // One at a time: the theme files are rewritten in place.
    void apply() => _queue = _queue.then(
          (_) => _apply(
            _Look(
              dark: service.darkMode,
              dahlia: (prefs.get<String>(SessionSetting.appStyle.key) ??
                      SessionSetting.appStyle.defaultValue) !=
                  "adwaita",
              accent: service.accentColor.resolve() ?? _defaultAccent,
              tint: prefs.get<bool>(SessionSetting.titlebarAccentTint.key) ??
                  SessionSetting.titlebarAccentTint.defaultValue,
            ),
          ),
        );
    service.addListener(apply);
    prefs.addListener(apply);
    apply();
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
            dahlia: (prefs.get<String>(SessionSetting.appStyle.key) ??
                    SessionSetting.appStyle.defaultValue) !=
                "adwaita",
          ),
        );
    prefs.addListener(applyFonts);
    applyFonts();
  }

  static (String, String, bool)? _fonts;

  /// The interface and monospace fonts for GTK, libadwaita, Qt (through
  /// the settings portal), Firefox and the terminal apps too. The default
  /// (empty) is Inter with the dahliaOS app style, as in Pangolin's own apps
  /// (when it's installed), and the toolkits' own otherwise.
  static Future<void> _applyFonts(String ui, String mono, {required bool dahlia}) async {
    if (!_available || _fonts == (ui, mono, dahlia)) return;
    _fonts = (ui, mono, dahlia);
    final String interface = ui.isEmpty && dahlia && await _hasFont("Inter") ? "Inter" : ui;
    try {
      for (final (String key, String family) in [
        ("font-name", interface),
        ("document-font-name", interface),
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

  static Future<bool> _hasFont(String family) async {
    try {
      final ProcessResult r = await Process.run("fc-list", [family, "family"]);
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } on ProcessException {
      return false;
    }
  }

  static Future<void> _apply(_Look look) async {
    if (!_available || _applied == look) return;
    final _Look? before = _applied;
    _applied = look;
    try {
      // Minimize, maximize and close in apps drawing their own title bars
      // (GTK, libadwaita, Firefox), like Pangolin's own windows.
      await _setIn(
        "org.gnome.desktop.wm.preferences",
        "button-layout",
        "appmenu:minimize,maximize,close",
      );
      await _set("color-scheme", look.dark ? "prefer-dark" : "default");
      if (look.dahlia) {
        String name = GtkTheme.nameFor(look.accent, tint: look.tint);
        // Only the accent or the tint change the files.
        if (before == null ||
            !before.dahlia ||
            before.accent != look.accent ||
            before.tint != look.tint) {
          name = await GtkTheme.write(look.accent, tint: look.tint);
        }
        await GtkTheme.setLibadwaitaImport(true);
        await _set("gtk-theme", look.dark ? "$name-dark" : name);
      } else {
        await GtkTheme.setLibadwaitaImport(false);
        String? theme = await _get("gtk-theme");
        // Leaving the dahliaOS style: back to Adwaita.
        if (theme != null && theme.startsWith("${GtkTheme.family}-")) theme = "Adwaita";
        if (theme != null) {
          final String? wanted = _gtk3Theme(theme, look.dark);
          if (wanted != null && wanted != theme) await _set("gtk-theme", wanted);
        }
      }
    } on ProcessException {
      _available = false;
      _logger.info("gsettings isn't available: other apps keep their theme");
    } on FileSystemException catch (e) {
      _logger.warning("Couldn't write the GTK theme: $e");
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

/// What the GTK theme depends on.
class _Look {
  const _Look({
    required this.dark,
    required this.dahlia,
    required this.accent,
    required this.tint,
  });

  final bool dark;

  /// The dahliaOS app style (Settings > Appearance > Other apps).
  final bool dahlia;
  final Color accent;
  final bool tint;

  @override
  bool operator ==(Object other) =>
      other is _Look &&
      other.dark == dark &&
      other.dahlia == dahlia &&
      other.accent == accent &&
      other.tint == tint;

  @override
  int get hashCode => Object.hash(dark, dahlia, accent, tint);
}
