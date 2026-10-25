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

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// The colors of a dahliaOS app (Zenit's theme, the title bar and rail of
/// the app kit) as GTK named colors, for one brightness.
class GtkPalette {
  GtkPalette({required this.dark, required this.accent, required this.tint});

  final bool dark;
  final Color accent;

  /// Settings > Appearance > Tint title bars.
  final bool tint;

  static const Color _lightBg = Color(0xFFFFFFFF);
  static const Color _lightFg = Color(0xFF000000);
  static const Color _darkBg = Color(0xFF1A1A1A);
  static const Color _darkFg = Color(0xFFFAFAFA);

  Color get bg => dark ? _darkBg : _lightBg;
  Color get fg => dark ? _darkFg : _lightFg;
  Color get surface => dark ? const Color(0xFF272727) : const Color(0xFFE6E6E6);

  /// Lighter in dark mode, darker in light mode (Zenit's themedLightness).
  Color _themed(Color c, double amount) {
    final HSLColor hsl = HSLColor.fromColor(c);
    final double l = dark ? hsl.lightness + amount : hsl.lightness - amount;
    return hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
  }

  static Color _over(Color top, double alpha, Color below) =>
      Color.alphaBlend(top.withValues(alpha: alpha), below);

  /// Title bars and sidebars: DahliaRail.colorOf.
  Color get header => tint ? _over(accent, dark ? 0.16 : 0.09, bg) : _themed(surface, 0.05);

  /// Cards and grouped lists: sectionColor.
  Color get card => _over(fg, dark ? 0.06 : 0.04, bg);

  Color get onAccent => (accent.computeLuminance() > 0.3) != dark ? fg : bg;

  /// The accent as text and icons on the window background.
  Color get accentText {
    final HSLColor hsl = HSLColor.fromColor(accent);
    return hsl
        .withLightness(dark ? hsl.lightness.clamp(0.7, 1.0) : hsl.lightness.clamp(0.0, 0.45))
        .toColor();
  }

  Map<String, String> get colors => {
        "pangolin_accent": _css(accent),
        "pangolin_accent_hover": _css(_over(onAccent, 0.1, accent)),
        "pangolin_accent_active": _css(_over(onAccent, 0.2, accent)),
        "pangolin_on_accent": _css(onAccent),
        "pangolin_accent_text": _css(accentText),
        "pangolin_bg": _css(bg),
        "pangolin_fg": _css(fg),
        "pangolin_fg_dim": _css(Color.lerp(fg, bg, 0.38)!),
        "pangolin_surface": _css(surface),
        "pangolin_surface_hover": _css(_themed(surface, 0.04)),
        "pangolin_surface_active": _css(_themed(surface, 0.08)),
        "pangolin_header": _css(header),
        "pangolin_card": _css(card),
        "pangolin_popover": _css(dark ? card : bg),
        "pangolin_field": _css(fg.withValues(alpha: dark ? 0.08 : 0.05)),
        "pangolin_hover": _css(fg.withValues(alpha: dark ? 0.08 : 0.05)),
        "pangolin_active": _css(fg.withValues(alpha: dark ? 0.14 : 0.10)),
        "pangolin_selected": _css(accent.withValues(alpha: dark ? 0.32 : 0.2)),
        "pangolin_selection": _css(accent.withValues(alpha: 0.3)),
        "pangolin_track": _css(accent.withValues(alpha: 0.2)),
        // Off switches, unchecked boxes and slider tracks: translucent, so
        // they show on cards as well as on the page (the surface color
        // nearly matches a card in dark mode).
        "pangolin_control": _css(fg.withValues(alpha: dark ? 0.14 : 0.10)),
        "pangolin_control_hover": _css(fg.withValues(alpha: dark ? 0.2 : 0.15)),
        "pangolin_thumb_off": _css(_over(fg, 0.35, surface)),
        "pangolin_line": _css(fg.withValues(alpha: 0.08)),
        "pangolin_shadow": _css(const Color(0xFF000000).withValues(alpha: dark ? 0.5 : 0.16)),
        "pangolin_tooltip_bg": _css(fg),
        "pangolin_tooltip_fg": _css(bg),
        "pangolin_destructive": dark ? "#c01c28" : "#e01b24",
        "pangolin_error": dark ? "#ff7b63" : "#c30000",
        "pangolin_warning": dark ? "#f8e45c" : "#9c6e03",
        "pangolin_success": dark ? "#78e9ab" : "#1b8553",
      };

  /// `@define-color` lines for [colors].
  String get defines =>
      colors.entries.map((e) => "@define-color ${e.key} ${e.value};").join("\n");

  static String _css(Color c) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    final int a = ch(c.a);
    String hex(double v) => ch(v).toRadixString(16).padLeft(2, "0");
    if (a == 255) return "#${hex(c.r)}${hex(c.g)}${hex(c.b)}";
    return "rgba(${ch(c.r)}, ${ch(c.g)}, ${ch(c.b)}, ${(a / 255).toStringAsFixed(3)})";
  }
}

/// Pangolin's dahliaOS theme for GTK apps ("Adwaita edits"): GTK's own
/// Adwaita with dahliaOS' colors, shapes and controls on top, generated for
/// the current accent color.
///
/// - GTK 3 and plain GTK 4 apps: a theme in $XDG_DATA_HOME/themes, picked
///   through gtk-theme in Pangolin's own dconf database, so GNOME keeps its
///   theme. Its name carries the accent (GTK 3 keeps a theme it loaded once
///   for the app's lifetime, so a new accent needs a new name); "-dark" is
///   the dark variant, as with Adwaita-dark.
/// - libadwaita apps ignore gtk-theme: they get named colors and a few
///   rules through ~/.config/gtk-4.0/gtk.css, which imports Pangolin's file
///   only while a Pangolin session runs (pangolin-river-init removes the
///   line when it ends), since GNOME reads that file too. They pick up a new
///   accent when they start; light and dark follow at once.
abstract final class GtkTheme {
  static const String family = "dahliaOS";
  static const String _marker = ".pangolin-generated";
  static const String libadwaitaFile = "pangolin-dahlia.css";
  static const String importLine =
      '@import url("$libadwaitaFile"); /* Pangolin, only while its session runs */';

  static String _home() => Platform.environment["HOME"] ?? "";
  static String dataHome() =>
      Platform.environment["XDG_DATA_HOME"] ?? "${_home()}/.local/share";
  static String configHome() =>
      Platform.environment["XDG_CONFIG_HOME"] ?? "${_home()}/.config";

  /// The theme's name for this accent and tint (light; "-dark" appended
  /// for the dark one).
  static String nameFor(Color accent, {required bool tint}) {
    final String hex = (accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0");
    return "$family-$hex${tint ? "t" : ""}";
  }

  /// Writes the GTK 3/4 themes and the libadwaita stylesheet for [accent].
  /// Returns the light theme's name. The folders default to the XDG ones.
  static Future<String> write(
    Color accent, {
    required bool tint,
    String? dataDir,
    String? configDir,
  }) async {
    final String name = nameFor(accent, tint: tint);
    final GtkPalette light = GtkPalette(dark: false, accent: accent, tint: tint);
    final GtkPalette dark = GtkPalette(dark: true, accent: accent, tint: tint);
    final String gtk3 = await rootBundle.loadString("assets/gtk/gtk-3.0.css");
    final String gtk4 = await rootBundle.loadString("assets/gtk/gtk-4.0.css");
    final String adw = await rootBundle.loadString("assets/gtk/libadwaita.css");

    String gtk3Css(GtkPalette p) =>
        '@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained${p.dark ? "-dark" : ""}.css");\n'
        "${p.defines}\n$gtk3";
    String gtk4Css(GtkPalette p) =>
        '@import url("resource:///org/gtk/libgtk/theme/Default/Default-${p.dark ? "dark" : "light"}.css");\n'
        "${p.defines}\n$gtk4";

    final String themes = "${dataDir ?? dataHome()}/themes";
    for (final (String dir, GtkPalette normal) in [
      ("$themes/$name", light),
      ("$themes/$name-dark", dark),
    ]) {
      await _writeFile("$dir/index.theme", _indexTheme(dir.split("/").last));
      await _writeFile("$dir/$_marker", "");
      await _writeFile("$dir/gtk-3.0/gtk.css", gtk3Css(normal));
      // Apps asking for the dark variant themselves.
      await _writeFile("$dir/gtk-3.0/gtk-dark.css", gtk3Css(dark));
      await _writeFile("$dir/gtk-4.0/gtk.css", gtk4Css(normal));
      await _writeFile("$dir/gtk-4.0/gtk-dark.css", gtk4Css(dark));
    }
    _removeOld(themes, {name, "$name-dark"});

    await _writeFile(
      "${configDir ?? configHome()}/gtk-4.0/$libadwaitaFile",
      "/* Generated by Pangolin for its dahliaOS app style; rewritten when the\n"
      "   accent color changes. */\n"
      "${light.defines}\n"
      "@media (prefers-color-scheme: dark) {\n${dark.defines}\n}\n$adw",
    );
    return name;
  }

  static String _indexTheme(String name) => "[Desktop Entry]\n"
      "Type=X-GNOME-Metatheme\n"
      "Name=$name\n"
      "Comment=dahliaOS look for GTK apps, generated by Pangolin\n"
      "Encoding=UTF-8\n\n"
      "[X-GNOME-Metatheme]\n"
      "GtkTheme=$name\n";

  static Future<void> _writeFile(String path, String contents) async {
    final File file = File(path);
    await file.parent.create(recursive: true);
    // Replaced in one step: an app loading it meanwhile never reads half.
    final File temp = File("$path.tmp");
    await temp.writeAsString(contents, flush: true);
    await temp.rename(path);
  }

  /// Themes generated for an earlier accent (only Pangolin's own, marked).
  static void _removeOld(String themes, Set<String> keep) {
    final Directory dir = Directory(themes);
    if (!dir.existsSync()) return;
    for (final FileSystemEntity e in dir.listSync()) {
      final String base = e.path.split("/").last;
      if (e is! Directory || !base.startsWith("$family-") || keep.contains(base)) continue;
      if (!File("${e.path}/$_marker").existsSync()) continue;
      try {
        e.deleteSync(recursive: true);
      } on FileSystemException {
        // Gone already, or not ours to remove.
      }
    }
  }

  /// Adds or removes the import of [libadwaitaFile] in the user's
  /// gtk-4.0/gtk.css, leaving everything else in that file as it is.
  static Future<void> setLibadwaitaImport(bool on, {String? configDir}) async {
    final File css = File("${configDir ?? configHome()}/gtk-4.0/gtk.css");
    final List<String> lines = css.existsSync() ? await css.readAsLines() : <String>[];
    final List<String> others = lines.where((l) => !l.contains(libadwaitaFile)).toList();
    // @import must come before any other rule: first line.
    final List<String> wanted = on ? [importLine, ...others] : others;
    if (wanted.join("\n") == lines.join("\n")) return;
    if (!on && others.every((l) => l.trim().isEmpty)) {
      if (css.existsSync()) await css.delete();
      return;
    }
    await _writeFile(css.path, "${wanted.join("\n")}\n");
  }
}
