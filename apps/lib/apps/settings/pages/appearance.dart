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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:path/path.dart' as p;

/// Wallpapers shipped with Pangolin, previewed from the apps' own copies.
const Map<String, String> _bundledWallpapers = {
  "images/wallpapers/lucerne.png": "assets/images/lucerne.png",
  "images/wallpapers/modern.png": "assets/images/modern.png",
};

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  List<String> _systemWallpapers() {
    final List<String> found = [];
    for (final String dir in [
      "/usr/share/backgrounds",
      "/usr/share/wallpapers",
      p.join(SystemUtils.home, "Pictures", "Wallpapers"),
    ]) {
      final Directory d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        for (final FileSystemEntity e in d.listSync(recursive: true)) {
          if (e is File &&
              const {".png", ".jpg", ".jpeg", ".webp"}
                  .contains(p.extension(e.path).toLowerCase())) {
            found.add(e.path);
          }
          if (found.length > 40) return found;
        }
      } on FileSystemException {
        continue;
      }
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableServiceBuilder<CustomizationService>(
      builder: (context, _) {
        final CustomizationService c = CustomizationService.current;
        final ImageResource current = c.wallpaper;
        final List<ImageResource> files = [
          ...c.recentWallpapers,
          for (final String path in _systemWallpapers())
            ImageResource(type: ImageResourceType.file, value: path),
        ].where((r) => r.type == ImageResourceType.file).toSet().toList();

        void setWallpaper(ImageResource resource) {
          c.wallpaper = resource;
          if (resource.type == ImageResourceType.file) {
            c.recentWallpapers = [
              resource,
              ...c.recentWallpapers.where((r) => r != resource),
            ].take(8).toList();
          }
        }

        Widget thumb(ImageResource resource, Widget image) => _WallpaperThumb(
              selected: current == resource,
              onTap: () => setWallpaper(resource),
              child: image,
            );

        return SettingsPageBody(
          children: [
            SettingsGroup(
              title: "Theme",
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ThemeModeCard(
                      label: "Light",
                      dark: false,
                      selected: !c.darkMode,
                      onTap: () => c.darkMode = false,
                    ),
                    const SizedBox(width: 20),
                    ThemeModeCard(
                      label: "Dark",
                      dark: true,
                      selected: c.darkMode,
                      onTap: () => c.darkMode = true,
                    ),
                  ],
                ),
              ],
            ),
            SettingsGroup(
              children: [
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) {
                    final String style = PreferencesService.current
                            .get<String>(SessionSetting.appStyle.key) ??
                        SessionSetting.appStyle.defaultValue;
                    return SettingsRow(
                      icon: Icons.style_outlined,
                      title: "Other apps",
                      subtitle: "How GTK apps look",
                      trailing: ZenitSegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: "dahlia", label: Text("dahliaOS")),
                          ButtonSegment(value: "adwaita", label: Text("Adwaita")),
                        ],
                        selected: {style == "adwaita" ? "adwaita" : "dahlia"},
                        onSelectionChanged: (v) =>
                            PreferencesService.current.set<String>(
                          SessionSetting.appStyle.key,
                          v.first,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            SettingsGroup(
              title: "Accent color",
              padding: const EdgeInsets.all(16),
              children: [
                ListenableBuilder(
                  // The wallpaper choice is a setting of its own.
                  listenable: PreferencesService.current,
                  builder: (context, _) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final BuiltinColor color in BuiltinColor.values)
                        Tooltip(
                          message: color.name[0].toUpperCase() +
                              color.name.substring(1),
                          child: AccentSwatch(
                            color: color.value,
                            selected: !_fromWallpaper &&
                                c.accentColor == color.resource,
                            onTap: () {
                              _setFromWallpaper(false);
                              c.accentColor = color.resource;
                            },
                          ),
                        ),
                      // Taken from the wallpaper by the shell.
                      Tooltip(
                        message: "From wallpaper",
                        child: AccentSwatch(
                          color: _fromWallpaper
                              ? c.accentColor.resolve() ?? Colors.grey
                              : Colors.blueGrey,
                          icon: Icons.wallpaper_rounded,
                          selected: _fromWallpaper,
                          onTap: () => _setFromWallpaper(true),
                        ),
                      ),
                      Tooltip(
                        message: "Custom",
                        child: AccentSwatch(
                          color: _isCustom(c)
                              ? c.accentColor.resolve() ?? Colors.grey
                              : Colors.blueGrey,
                          icon: Icons.palette_rounded,
                          selected: _isCustom(c),
                          onTap: () => _pickCustom(context, c),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: "Wallpaper",
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final MapEntry<String, String> w
                        in _bundledWallpapers.entries)
                      thumb(
                        ImageResource(
                            type: ImageResourceType.dahlia, value: w.key),
                        Image.asset(w.value,
                            fit: BoxFit.cover, cacheWidth: 320),
                      ),
                    for (final ImageResource r in files)
                      if (File(r.value).existsSync())
                        thumb(
                            r,
                            Image.file(File(r.value),
                                fit: BoxFit.cover, cacheWidth: 320)),
                    _WallpaperThumb(
                      selected: false,
                      onTap: () async {
                        final String? path = await showFileDialog(
                          context,
                          initialDirectory:
                              p.join(SystemUtils.home, "Pictures"),
                          extensions: const ["png", "jpg", "jpeg", "webp"],
                          title: "Choose a wallpaper",
                        );
                        if (path != null) {
                          setWallpaper(ImageResource(
                              type: ImageResourceType.file, value: path));
                        }
                      },
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined),
                              SizedBox(height: 4),
                              Text("Choose…", style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SettingsGroup(
              title: "Taskbar",
              children: [
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) {
                    final String alignment = PreferencesService.current
                            .get<String>(SessionSetting.taskbarAlignment.key) ??
                        SessionSetting.taskbarAlignment.defaultValue;
                    return SettingsRow(
                      icon: Icons.align_horizontal_left_rounded,
                      title: "App icons",
                      subtitle: "Where the taskbar shows apps",
                      trailing: ZenitSegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: "center", label: Text("Center")),
                          ButtonSegment(value: "left", label: Text("Left")),
                        ],
                        selected: {alignment == "left" ? "left" : "center"},
                        onSelectionChanged: (v) =>
                            PreferencesService.current.set<String>(
                          SessionSetting.taskbarAlignment.key,
                          v.first,
                        ),
                      ),
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) {
                    final String size = PreferencesService.current
                            .get<String>(SessionSetting.taskbarSize.key) ??
                        SessionSetting.taskbarSize.defaultValue;
                    return SettingsRow(
                      icon: Icons.height_rounded,
                      title: "Size",
                      trailing: ZenitSegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: "small", label: Text("Small")),
                          ButtonSegment(value: "medium", label: Text("Medium")),
                          ButtonSegment(value: "large", label: Text("Large")),
                        ],
                        selected: {
                          const {"small", "large"}.contains(size)
                              ? size
                              : "medium",
                        },
                        onSelectionChanged: (v) =>
                            PreferencesService.current.set<String>(
                          SessionSetting.taskbarSize.key,
                          v.first,
                        ),
                      ),
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) => SettingsRow(
                    icon: Icons.vertical_align_bottom_rounded,
                    title: "Hide automatically",
                    subtitle: "Point at the bottom edge of the screen to "
                        "show the taskbar",
                    trailing: ZenitSwitch(
                      value: PreferencesService.current.get<bool>(
                            SessionSetting.taskbarAutohide.key,
                          ) ??
                          SessionSetting.taskbarAutohide.defaultValue,
                      onChanged: (v) => PreferencesService.current.set<bool>(
                        SessionSetting.taskbarAutohide.key,
                        v,
                      ),
                    ),
                  ),
                ),
                if (c.pinnedApps.isEmpty)
                  const SettingsRow(
                    title: "No pinned apps",
                    subtitle: "Right click an app on the taskbar to pin it",
                  ),
                for (final String app in c.pinnedApps)
                  SettingsRow(
                    icon: Icons.push_pin_outlined,
                    title: app,
                    trailing: IconButton(
                      tooltip: "Unpin",
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => c.pinnedApps =
                          c.pinnedApps.where((a) => a != app).toList(),
                    ),
                  ),
              ],
            ),
            SettingsGroup(
              title: "App menu",
              children: [
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) => SettingsRow(
                    icon: Icons.fullscreen_rounded,
                    title: "Full screen",
                    subtitle: "Show apps in a grid over the whole screen",
                    trailing: ZenitSwitch(
                      value: PreferencesService.current.get<bool>(
                            SessionSetting.launcherFullscreen.key,
                          ) ??
                          SessionSetting.launcherFullscreen.defaultValue,
                      onChanged: (v) => PreferencesService.current.set<bool>(
                        SessionSetting.launcherFullscreen.key,
                        v,
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) {
                    final String sort = PreferencesService.current
                            .get<String>(SessionSetting.launcherSort.key) ??
                        SessionSetting.launcherSort.defaultValue;
                    return SettingsRow(
                      icon: Icons.sort_rounded,
                      title: "Sort apps",
                      trailing: ZenitSegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: "name", label: Text("A to Z")),
                          ButtonSegment(
                            value: "category",
                            label: Text("Category"),
                          ),
                        ],
                        selected: {sort == "category" ? "category" : "name"},
                        onSelectionChanged: (v) =>
                            PreferencesService.current.set<String>(
                          SessionSetting.launcherSort.key,
                          v.first,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const _FontsGroup(),
            const _PointerGroup(),
            const _HotCornersGroup(),
            SettingsGroup(
              title: "Desktop",
              children: [
                SettingsRow(
                  icon: Icons.waving_hand_outlined,
                  title: "Show welcome screen at startup",
                  trailing: ZenitSwitch(
                    value: c.showWelcomeScreen,
                    onChanged: (v) => c.showWelcomeScreen = v,
                  ),
                ),
                SettingsRow(
                  icon: Icons.blur_on_rounded,
                  title: "Visual effects",
                  subtitle: "Blur and transparency in the shell",
                  trailing: ZenitSwitch(
                    value: c.enableEffects,
                    onChanged: (v) => c.enableEffects = v,
                  ),
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) => SettingsRow(
                    icon: Icons.crop_square_rounded,
                    title: "Window borders",
                    subtitle: "A thin outline around windows",
                    trailing: ZenitSwitch(
                      value: PreferencesService.current.get<bool>(
                            SessionSetting.windowBorders.key,
                          ) ??
                          SessionSetting.windowBorders.defaultValue,
                      onChanged: (v) => PreferencesService.current.set<bool>(
                        SessionSetting.windowBorders.key,
                        v,
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) => SettingsRow(
                    icon: Icons.filter_none_rounded,
                    title: "Opaque inactive windows",
                    subtitle: "Windows you aren't using drop their blur",
                    trailing: ZenitSwitch(
                      value: PreferencesService.current.get<bool>(
                            SessionSetting.opaqueInactiveWindows.key,
                          ) ??
                          SessionSetting.opaqueInactiveWindows.defaultValue,
                      onChanged: (v) => PreferencesService.current.set<bool>(
                        SessionSetting.opaqueInactiveWindows.key,
                        v,
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: PreferencesService.current,
                  builder: (context, _) => SettingsRow(
                    icon: Icons.format_color_fill_rounded,
                    title: "Tint title bars",
                    subtitle: "Title bars take a touch of the accent color",
                    trailing: ZenitSwitch(
                      value: DahliaTitlebar.accentTint,
                      onChanged: (v) => PreferencesService.current.set<bool>(
                        SessionSetting.titlebarAccentTint.key,
                        v,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WallpaperThumb extends StatelessWidget {
  const _WallpaperThumb({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 160,
        height: 100,
        padding: EdgeInsets.all(selected ? 3 : 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
            width: selected ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }
}

/// The monospace choice that leaves the setting empty.
String get _defaultMonospaceLabel => SessionFonts.defaultMonospace == null
    ? "System default"
    : "${SessionFonts.defaultMonospace} (default)";

/// Interface and monospace fonts of the shell and the dahliaOS apps.
class _FontsGroup extends StatelessWidget {
  const _FontsGroup();

  @override
  Widget build(BuildContext context) {
    return ListenableServiceBuilder<PreferencesService>(
      builder: (context, _) {
        final PreferencesService prefs = PreferencesService.current;
        String read(SessionSetting<String> s) =>
            prefs.get<String>(s.key) ?? s.defaultValue;
        final String ui = read(SessionSetting.interfaceFont);
        final String mono = read(SessionSetting.monospaceFont);

        Future<void> pick(SessionSetting<String> setting,
            {required bool monospace}) async {
          final String? family = await showDialog<String>(
            context: context,
            builder: (context) => _FontPicker(
              monospace: monospace,
              current: read(setting),
            ),
          );
          if (family != null) prefs.set<String>(setting.key, family);
        }

        return SettingsGroup(
          title: "Fonts",
          children: [
            SettingsRow(
              icon: Icons.text_fields_rounded,
              title: "Interface",
              subtitle: "Shell and dahliaOS apps",
              trailing: _FontButton(
                label: ui.isEmpty ? "Inter (default)" : ui,
                family: ui.isEmpty ? null : ui,
                onPressed: () =>
                    pick(SessionSetting.interfaceFont, monospace: false),
              ),
            ),
            SettingsRow(
              icon: Icons.terminal_rounded,
              title: "Monospace",
              subtitle: "Terminal, text editor and logs",
              trailing: _FontButton(
                label: mono.isEmpty ? _defaultMonospaceLabel : mono,
                family: SessionFonts.monospace(mono) ?? "monospace",
                onPressed: () =>
                    pick(SessionSetting.monospaceFont, monospace: true),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FontButton extends StatelessWidget {
  const _FontButton(
      {required this.label, required this.family, required this.onPressed});

  final String label;
  final String? family;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.expand_more_rounded, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: family == null ? null : TextStyle(fontFamily: family),
        ),
      ),
    );
  }
}

/// Lists the font families installed on the system (fontconfig), each
/// previewed in its own font. Pops the chosen family, "" for the default.
class _FontPicker extends StatefulWidget {
  const _FontPicker({required this.monospace, required this.current});

  final bool monospace;
  final String current;

  @override
  State<_FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<_FontPicker> {
  List<String>? _families;
  String _query = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Set<String> families = {};
    try {
      final ProcessResult result = await Process.run("fc-list", [
        "--format",
        "%{family[0]}\\n",
        if (widget.monospace) ":spacing=mono",
      ]);
      if (result.exitCode == 0) {
        for (final String line in (result.stdout as String).split("\n")) {
          final String family = line.trim();
          if (family.isNotEmpty) families.add(family);
        }
      }
    } on ProcessException {
      // No fontconfig tools: only the default is offered.
    }
    if (!mounted) return;
    setState(() {
      _families = families.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String>? families = _families;
    final String query = _query.toLowerCase();
    final List<String> shown = [
      "",
      ...?families?.where((f) => f.toLowerCase().contains(query)),
    ];
    final String sample = widget.monospace
        ? "fn main() { return 0x2A; }"
        : "The quick brown fox jumps over the lazy dog";

    return AlertDialog(
      title: Text(widget.monospace ? "Monospace font" : "Interface font"),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            SearchField(
              hint: "Search fonts",
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: families == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final String family = shown[i];
                        final bool selected = family == widget.current;
                        final String? previewFamily = family.isEmpty
                            ? (widget.monospace
                                ? SessionFonts.monospace(family) ?? "monospace"
                                : null)
                            : family;
                        return Material(
                          color: selected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => Navigator.pop(context, family),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    family.isEmpty
                                        ? (widget.monospace
                                            ? _defaultMonospaceLabel
                                            : "Inter (default)")
                                        : family,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? theme.colorScheme.onPrimary
                                          : null,
                                    ),
                                  ),
                                  Text(
                                    sample,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontFamily: previewFamily,
                                      color: selected
                                          ? theme.colorScheme.onPrimary
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
      ],
    );
  }
}

/// Mouse pointer theme and size.
class _PointerGroup extends StatelessWidget {
  const _PointerGroup();

  static const List<int> _sizes = [24, 32, 40, 48];

  /// Installed cursor themes (icon theme directories with cursors).
  static List<String> _themes() {
    final Map<String, String> env = Platform.environment;
    final String home = env["HOME"] ?? "";
    final List<String> roots = [
      "$home/.icons",
      "${env["XDG_DATA_HOME"] ?? "$home/.local/share"}/icons",
      for (final String d
          in (env["XDG_DATA_DIRS"] ?? "/usr/local/share:/usr/share").split(":"))
        if (d.isNotEmpty) "$d/icons",
      "/usr/share/pixmaps",
    ];
    final Set<String> themes = {};
    for (final String root in roots) {
      final Directory dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final FileSystemEntity e in dir.listSync()) {
        if (Directory("${e.path}/cursors").existsSync()) {
          themes.add(e.uri.pathSegments.where((s) => s.isNotEmpty).last);
        }
      }
    }
    final List<String> sorted = themes.toList()..sort();
    // Pangolin's own first.
    if (sorted.remove("Pangolin")) sorted.insert(0, "Pangolin");
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final PreferencesService prefs = PreferencesService.current;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final String theme =
            prefs.get<String>(SessionSetting.cursorTheme.key) ??
                SessionSetting.cursorTheme.defaultValue;
        final int size = prefs.get<int>(SessionSetting.cursorSize.key) ??
            SessionSetting.cursorSize.defaultValue;
        final List<String> themes = _themes();
        if (!themes.contains(theme)) themes.insert(0, theme);
        return SettingsGroup(
          title: "Pointer",
          children: [
            SettingsRow(
              icon: Icons.mouse_outlined,
              title: "Pointer style",
              trailing: DropdownButton<String>(
                value: theme,
                underline: const SizedBox(),
                items: [
                  for (final String t in themes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(t == "Pangolin" ? "Pangolin (default)" : t),
                    ),
                ],
                onChanged: (v) {
                  if (v != null)
                    prefs.set<String>(SessionSetting.cursorTheme.key, v);
                },
              ),
            ),
            SettingsRow(
              icon: Icons.format_size_rounded,
              title: "Pointer size",
              trailing: ZenitSegmentedButton<int>(
                segments: [
                  for (final int s in _sizes)
                    ButtonSegment(
                      value: s,
                      label: Text(switch (s) {
                        24 => "Default",
                        32 => "Large",
                        40 => "Larger",
                        _ => "Largest",
                      }),
                    ),
                ],
                selected: {_sizes.contains(size) ? size : 24},
                onSelectionChanged: (v) =>
                    prefs.set<int>(SessionSetting.cursorSize.key, v.first),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// What pushing the pointer into each corner of the screen does.
class _HotCornersGroup extends StatelessWidget {
  const _HotCornersGroup();

  static const List<(SessionSetting<String>, String, IconData)> _corners = [
    (SessionSetting.hotCornerTopLeft, "Top left", Icons.north_west_rounded),
    (SessionSetting.hotCornerTopRight, "Top right", Icons.north_east_rounded),
    (
      SessionSetting.hotCornerBottomLeft,
      "Bottom left",
      Icons.south_west_rounded
    ),
    (
      SessionSetting.hotCornerBottomRight,
      "Bottom right",
      Icons.south_east_rounded
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PreferencesService.current,
      builder: (context, _) {
        final PreferencesService prefs = PreferencesService.current;
        return SettingsGroup(
          title: "Hot corners",
          children: [
            for (final (setting, label, icon) in _corners)
              SettingsRow(
                icon: icon,
                title: label,
                subtitle: setting == SessionSetting.hotCornerTopLeft
                    ? "Push the pointer into a corner of the screen"
                    : null,
                trailing: DropdownButton<GestureAction>(
                  value: GestureAction.parse(
                    prefs.get<String>(setting.key) ?? setting.defaultValue,
                  ),
                  underline: const SizedBox(),
                  items: [
                    for (final GestureAction action in GestureAction.values)
                      if (action != GestureAction.switchDesktop)
                        DropdownMenuItem(
                            value: action, child: Text(action.label)),
                  ],
                  onChanged: (action) => prefs.set<String>(
                    setting.key,
                    (action ?? GestureAction.none).value,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

bool get _fromWallpaper =>
    PreferencesService.current
        .get<bool>(SessionSetting.accentFromWallpaper.key) ??
    SessionSetting.accentFromWallpaper.defaultValue;

void _setFromWallpaper(bool on) => PreferencesService.current
    .set<bool>(SessionSetting.accentFromWallpaper.key, on);

/// A color picked with the custom picker (not a built-in one, not the
/// wallpaper's).
bool _isCustom(CustomizationService c) =>
    !_fromWallpaper && c.accentColor.subtype == ColorResourceType.hex;

Future<void> _pickCustom(BuildContext context, CustomizationService c) async {
  final Color? picked = await showDialog<Color>(
    context: context,
    builder: (context) => _CustomAccentDialog(
      initial: c.accentColor.resolve() ?? const Color(0xFFFF5722),
    ),
  );
  if (picked == null) return;
  _setFromWallpaper(false);
  c.accentColor = ColorResource(
    type: ColorResourceType.hex,
    value: (picked.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, "0"),
  );
}

/// Hue, saturation and brightness, with a preview and the hex code.
class _CustomAccentDialog extends StatefulWidget {
  const _CustomAccentDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<_CustomAccentDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex =
      TextEditingController(text: _hexOf(_hsv));

  static String _hexOf(HSVColor hsv) => (hsv.toColor().toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .padLeft(6, "0")
      .toUpperCase();

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _hex.text = _hexOf(hsv);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(width: 90, child: Text(label)),
            Expanded(child: ZenitSlider(value: value, onChanged: onChanged)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Custom accent color"),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 12),
            _slider("Hue", _hsv.hue / 360, (v) => _set(_hsv.withHue(v * 360))),
            _slider("Saturation", _hsv.saturation,
                (v) => _set(_hsv.withSaturation(v))),
            _slider("Brightness", _hsv.value, (v) => _set(_hsv.withValue(v))),
            const SizedBox(height: 8),
            TextField(
              controller: _hex,
              decoration:
                  const InputDecoration(prefixText: "#", labelText: "Hex"),
              onSubmitted: (text) {
                final int? value =
                    int.tryParse(text.replaceAll("#", ""), radix: 16);
                if (value != null && text.replaceAll("#", "").length == 6) {
                  setState(() =>
                      _hsv = HSVColor.fromColor(Color(0xFF000000 | value)));
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: const Text("Use color"),
        ),
      ],
    );
  }
}
