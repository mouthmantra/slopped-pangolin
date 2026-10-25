import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/gtk_theme.dart';

// GtkTheme writes into a scratch folder: PANGOLIN_GTK_THEME_OUT when set (to
// try the theme with real GTK apps), a temporary one otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String data;
  late String config;

  setUp(() {
    final String? out = Platform.environment["PANGOLIN_GTK_THEME_OUT"];
    root = out != null ? Directory(out) : Directory.systemTemp.createTempSync("gtk-theme");
    data = "${root.path}/data";
    config = "${root.path}/config";
  });

  tearDown(() {
    if (Platform.environment["PANGOLIN_GTK_THEME_OUT"] == null) root.deleteSync(recursive: true);
  });

  test("palette follows Zenit", () {
    final GtkPalette light = GtkPalette(dark: false, accent: const Color(0xFFFF5722), tint: true);
    final GtkPalette dark = GtkPalette(dark: true, accent: const Color(0xFFFF5722), tint: true);
    expect(light.colors["pangolin_bg"], "#ffffff");
    expect(dark.colors["pangolin_bg"], "#1a1a1a");
    expect(light.colors["pangolin_surface"], "#e6e6e6");
    // An orange accent is light enough for black text in light mode
    // (luminance over 0.3 is Zenit's rule); white below.
    expect(GtkPalette(dark: false, accent: const Color(0xFF0073CF), tint: true).colors["pangolin_on_accent"],
        "#ffffff");
    // The title bar takes 9% of the accent over the window color.
    expect(light.colors["pangolin_header"], "#fff0eb");
    expect(
      GtkPalette(dark: false, accent: const Color(0xFFFF5722), tint: false).colors["pangolin_header"],
      "#d9d9d9",
    );
    expect(light.defines, contains("@define-color pangolin_accent #ff5722;"));
  });

  test("themes for the accent, the old one removed", () async {
    final String old = await GtkTheme.write(const Color(0xFF0073CF), tint: true, dataDir: data, configDir: config);
    expect(old, "dahliaOS-0073cft");
    final String name = await GtkTheme.write(const Color(0xFFFF5722), tint: true, dataDir: data, configDir: config);
    expect(name, "dahliaOS-ff5722t");
    for (final String n in [name, "$name-dark"]) {
      for (final String f in ["index.theme", "gtk-3.0/gtk.css", "gtk-3.0/gtk-dark.css", "gtk-4.0/gtk.css", "gtk-4.0/gtk-dark.css"]) {
        expect(File("$data/themes/$n/$f").existsSync(), isTrue, reason: "$n/$f");
      }
    }
    expect(Directory("$data/themes/$old").existsSync(), isFalse);
    final String gtk3 = File("$data/themes/$name/gtk-3.0/gtk.css").readAsStringSync();
    expect(gtk3, startsWith('@import url("resource:///org/gtk/libgtk/theme/Adwaita/gtk-contained.css");'));
    expect(File("$data/themes/$name-dark/gtk-3.0/gtk.css").readAsStringSync(), contains("gtk-contained-dark.css"));
    expect(File("$data/themes/$name-dark/gtk-4.0/gtk.css").readAsStringSync(), contains("Default-dark.css"));
    final String adw = File("$config/gtk-4.0/${GtkTheme.libadwaitaFile}").readAsStringSync();
    expect(adw, contains("@media (prefers-color-scheme: dark)"));
    expect(adw, contains("@define-color accent_bg_color @pangolin_accent;"));
  });

  test("a theme folder that isn't Pangolin's stays", () async {
    Directory("$data/themes/dahliaOS-mine/gtk-3.0").createSync(recursive: true);
    await GtkTheme.write(const Color(0xFFFF5722), tint: false, dataDir: data, configDir: config);
    expect(Directory("$data/themes/dahliaOS-mine").existsSync(), isTrue);
  });

  test("the libadwaita import comes and goes, the user's lines stay", () async {
    final File css = File("$config/gtk-4.0/gtk.css")..createSync(recursive: true);
    css.writeAsStringSync("/* mine */\nlabel { color: red; }\n");
    await GtkTheme.setLibadwaitaImport(true, configDir: config);
    await GtkTheme.setLibadwaitaImport(true, configDir: config);
    final List<String> lines = css.readAsLinesSync();
    expect(lines.first, GtkTheme.importLine);
    expect(lines.where((l) => l.contains(GtkTheme.libadwaitaFile)), hasLength(1));
    await GtkTheme.setLibadwaitaImport(false, configDir: config);
    expect(css.readAsStringSync(), "/* mine */\nlabel { color: red; }\n");

    // Without lines of the user's, the file goes again.
    css.deleteSync();
    await GtkTheme.setLibadwaitaImport(true, configDir: config);
    expect(css.existsSync(), isTrue);
    await GtkTheme.setLibadwaitaImport(false, configDir: config);
    expect(css.existsSync(), isFalse);
  });
}
