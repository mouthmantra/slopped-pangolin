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

/// XKB layouts and their variants from the evdev rules catalog.
class _XkbCatalog {
  final Map<String, String> layouts = {};
  final Map<String, List<(String, String)>> variants = {};

  static _XkbCatalog load() {
    final _XkbCatalog catalog = _XkbCatalog();
    final File lst = File("/usr/share/X11/xkb/rules/evdev.lst");
    if (!lst.existsSync()) {
      catalog.layouts.addAll(const {
        "us": "English (US)", "gb": "English (UK)", "de": "German",
        "fr": "French", //
        "es": "Spanish", "it": "Italian", "pt": "Portuguese",
        "br": "Portuguese (Brazil)",
        "ru": "Russian", "ua": "Ukrainian", "pl": "Polish", "se": "Swedish",
      });
      return catalog;
    }
    String section = "";
    for (final String line in lst.readAsLinesSync()) {
      if (line.startsWith("! ")) {
        section = line.substring(2).trim();
        continue;
      }
      final Match? m = RegExp(r"^\s+(\S+)\s+(.*)$").firstMatch(line);
      if (m == null) continue;
      if (section == "layout") {
        catalog.layouts[m.group(1)!] = m.group(2)!.trim();
      } else if (section == "variant") {
        // "  dvorak          us: English (Dvorak)"
        final Match? v =
            RegExp(r"^(\S+):\s*(.*)$").firstMatch(m.group(2)!.trim());
        if (v != null) {
          catalog.variants
              .putIfAbsent(v.group(1)!, () => [])
              .add((m.group(1)!, v.group(2)!));
        }
      }
    }
    return catalog;
  }
}

enum InputSection { keyboard, mouse, touchpad }

/// Keyboard, mouse or touchpad settings.
class InputPage extends StatefulWidget {
  const InputPage({this.section = InputSection.keyboard, super.key});

  final InputSection section;

  @override
  State<InputPage> createState() => _InputPageState();
}

class _InputPageState extends State<InputPage> {
  late final _XkbCatalog _catalog = _XkbCatalog.load();

  static const Map<String, String> _switchOptions = {
    "grp:alt_shift_toggle": "Alt + Shift",
    "grp:win_space_toggle": "Super + Space",
    "grp:ctrl_shift_toggle": "Ctrl + Shift",
    "grp:caps_toggle": "Caps Lock",
    "": "None",
  };

  PreferencesService get _prefs => PreferencesService.current;

  /// Whether this computer has a touchpad (a pointer device with absolute
  /// axes, in the kernel's list); shown anyway when that can't be read.
  late final bool _hasTouchpad = () {
    try {
      final String devices = File("/proc/bus/input/devices").readAsStringSync();
      for (final String device in devices.split(RegExp(r"\n\s*\n"))) {
        final RegExpMatch? props =
            RegExp(r"^B: PROP=([0-9a-f]+)", multiLine: true).firstMatch(device);
        if (props == null) continue;
        final int bits = int.tryParse(props.group(1)!, radix: 16) ?? 0;
        // INPUT_PROP_POINTER, not INPUT_PROP_DIRECT (touchscreens).
        if (bits & 1 != 0 && bits & 2 == 0 && device.contains("B: ABS=")) {
          return true;
        }
      }
      return false;
    } on Object {
      return true;
    }
  }();

  Widget _speedRow({
    required IconData icon,
    required String title,
    required SessionSetting<double> setting,
  }) {
    return SettingsRow(
      icon: icon,
      title: title,
      trailing: SizedBox(
        width: 260,
        child: Row(
          children: [
            const Text("Slow", style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                min: -1,
                max: 1,
                divisions: 20,
                value: _get(setting).clamp(-1.0, 1.0),
                onChanged: (v) => _set(setting, v),
              ),
            ),
            const Text("Fast", style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  T _get<T extends Object>(SessionSetting<T> s) =>
      _prefs.get<T>(s.key) ?? s.defaultValue;

  void _set<T extends Object>(SessionSetting<T> s, T value) {
    _prefs.set<T>(s.key, value);
    setState(() {});
  }

  List<String> get _layouts => _get(SessionSetting.keyboardLayouts)
      .split(",")
      .where((l) => l.isNotEmpty)
      .toList();

  List<String> get _variants {
    final List<String> v = _get(SessionSetting.keyboardVariants).split(",");
    return [for (int i = 0; i < _layouts.length; i++) i < v.length ? v[i] : ""];
  }

  void _setLayouts(List<String> layouts, List<String> variants) {
    _set(SessionSetting.keyboardLayouts, layouts.join(","));
    _set(SessionSetting.keyboardVariants, variants.join(","));
  }

  String get _switchOption {
    final List<String> options =
        _get(SessionSetting.keyboardOptions).split(",");
    return options.firstWhere((o) => o.startsWith("grp:"), orElse: () => "");
  }

  void _setSwitchOption(String option) {
    final List<String> others = _get(SessionSetting.keyboardOptions)
        .split(",")
        .where((o) => o.isNotEmpty && !o.startsWith("grp:"))
        .toList();
    _set(SessionSetting.keyboardOptions,
        [...others, if (option.isNotEmpty) option].join(","));
  }

  String _layoutName(String layout, String variant) {
    final String base = _catalog.layouts[layout] ?? layout;
    if (variant.isEmpty) return base;
    final String? v = _catalog.variants[layout]
        ?.where((e) => e.$1 == variant)
        .firstOrNull
        ?.$2;
    return v ?? "$base ($variant)";
  }

  Future<void> _addLayout() async {
    final (String, String)? choice = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _LayoutPicker(catalog: _catalog),
    );
    if (choice == null) return;
    _setLayouts([..._layouts, choice.$1], [..._variants, choice.$2]);
  }

  List<Widget> _mouseGroups() => [
        SettingsGroup(
          title: "Mouse",
          children: [
            _speedRow(
              icon: Icons.mouse_outlined,
              title: "Pointer speed",
              setting: SessionSetting.pointerSpeed,
            ),
            SettingsRow(
              icon: Icons.trending_up_rounded,
              title: "Mouse acceleration",
              subtitle: "Faster movements take the pointer further",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.mouseAcceleration),
                onChanged: (v) => _set(SessionSetting.mouseAcceleration, v),
              ),
            ),
            SettingsRow(
              icon: Icons.swap_vert_rounded,
              title: "Natural scrolling",
              subtitle: "Content moves the way the wheel turns",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.mouseNaturalScroll),
                onChanged: (v) => _set(SessionSetting.mouseNaturalScroll, v),
              ),
            ),
            SettingsRow(
              icon: Icons.ads_click_rounded,
              title: "Primary button",
              subtitle: "Also on the touchpad",
              trailing: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text("Left")),
                  ButtonSegment(value: true, label: Text("Right")),
                ],
                selected: {_get(SessionSetting.leftHanded)},
                onSelectionChanged: (v) =>
                    _set(SessionSetting.leftHanded, v.first),
              ),
            ),
          ],
        ),
      ];

  List<Widget> _touchpadGroups() => [
        SettingsGroup(
          title: "Touchpad",
          children: [
            SettingsRow(
              icon: Icons.touch_app_outlined,
              title: "Touchpad",
              trailing: DropdownButton<String>(
                value: const {"enabled", "disabled", "external_mouse"}
                        .contains(_get(SessionSetting.touchpadMode))
                    ? _get(SessionSetting.touchpadMode)
                    : "enabled",
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: "enabled", child: Text("On")),
                  DropdownMenuItem(
                    value: "external_mouse",
                    child: Text("Off while a mouse is connected"),
                  ),
                  DropdownMenuItem(value: "disabled", child: Text("Off")),
                ],
                onChanged: (v) =>
                    _set(SessionSetting.touchpadMode, v ?? "enabled"),
              ),
            ),
            _speedRow(
              icon: Icons.speed_rounded,
              title: "Pointer speed",
              setting: SessionSetting.touchpadSpeed,
            ),
            SettingsRow(
              icon: Icons.trending_up_rounded,
              title: "Acceleration",
              subtitle: "Faster swipes take the pointer further",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.touchpadAcceleration),
                onChanged: (v) => _set(SessionSetting.touchpadAcceleration, v),
              ),
            ),
            SettingsRow(
              icon: Icons.touch_app_outlined,
              title: "Tap to click",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.tapToClick),
                onChanged: (v) => _set(SessionSetting.tapToClick, v),
              ),
            ),
            SettingsRow(
              icon: Icons.ads_click_rounded,
              title: "Two-finger right click",
              subtitle: "Click (or tap) with two fingers for the "
                  "context menu, instead of the bottom right corner",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.twoFingerRightClick),
                onChanged: (v) => _set(SessionSetting.twoFingerRightClick, v),
              ),
            ),
            SettingsRow(
              icon: Icons.swap_vert_rounded,
              title: "Natural scrolling",
              subtitle: "Content follows your fingers",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.naturalScroll),
                onChanged: (v) => _set(SessionSetting.naturalScroll, v),
              ),
            ),
            SettingsRow(
              icon: Icons.keyboard_hide_outlined,
              title: "Disable while typing",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.disableWhileTyping),
                onChanged: (v) => _set(SessionSetting.disableWhileTyping, v),
              ),
            ),
            SettingsRow(
              icon: Icons.swipe_rounded,
              title: "Gestures",
              subtitle: "Swipe up for the overview, sideways to "
                  "switch desktops, pinch to show the desktop",
              trailing: ZenitSwitch(
                value: _get(SessionSetting.gesturesEnabled),
                onChanged: (v) => _set(SessionSetting.gesturesEnabled, v),
              ),
            ),
            if (_get(SessionSetting.gesturesEnabled))
              SettingsRow(
                icon: Icons.back_hand_outlined,
                title: "Fingers for gestures",
                subtitle: "Swipes with other finger counts scroll",
                trailing: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 3, label: Text("Three")),
                    ButtonSegment(value: 4, label: Text("Four")),
                  ],
                  selected: {_get(SessionSetting.gestureFingers) == 4 ? 4 : 3},
                  onSelectionChanged: (v) =>
                      _set(SessionSetting.gestureFingers, v.first),
                ),
              ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableServiceBuilder<PreferencesService>(
      builder: (context, _) {
        final List<String> layouts = _layouts;
        final List<String> variants = _variants;

        switch (widget.section) {
          case InputSection.mouse:
            return SettingsPageBody(children: _mouseGroups());
          case InputSection.touchpad:
            if (!_hasTouchpad) {
              return const EmptyState(
                icon: Icons.touch_app_outlined,
                title: "No touchpad found",
                subtitle:
                    "Touchpad settings show up here when one is connected",
              );
            }
            return SettingsPageBody(children: _touchpadGroups());
          case InputSection.keyboard:
        }
        return SettingsPageBody(
          children: [
            SettingsGroup(
              title: "Keyboard layouts",
              children: [
                for (int i = 0; i < layouts.length; i++)
                  SettingsRow(
                    icon: i == 0
                        ? Icons.keyboard_rounded
                        : Icons.keyboard_outlined,
                    title: _layoutName(layouts[i], variants[i]),
                    subtitle: i == 0 ? "Default" : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          IconButton(
                            tooltip: "Make default",
                            icon: const Icon(Icons.arrow_upward_rounded),
                            onPressed: () {
                              final List<String> l = List.of(layouts)
                                ..insert(0, layouts[i]);
                              final List<String> v = List.of(variants)
                                ..insert(0, variants[i]);
                              l.removeAt(i + 1);
                              v.removeAt(i + 1);
                              _setLayouts(l, v);
                            },
                          ),
                        if (layouts.length > 1)
                          IconButton(
                            tooltip: "Remove",
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => _setLayouts(
                              List.of(layouts)..removeAt(i),
                              List.of(variants)..removeAt(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                SettingsRow(
                  icon: Icons.add_rounded,
                  title: "Add a layout…",
                  onTap: _addLayout,
                ),
                SettingsRow(
                  title: "Switch layouts with",
                  trailing: DropdownButton<String>(
                    value: _switchOptions.containsKey(_switchOption)
                        ? _switchOption
                        : "",
                    underline: const SizedBox(),
                    items: [
                      for (final MapEntry<String, String> o
                          in _switchOptions.entries)
                        DropdownMenuItem(value: o.key, child: Text(o.value)),
                    ],
                    onChanged: (v) => _setSwitchOption(v ?? ""),
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: "Key repeat",
              children: [
                SettingsRow(
                  title: "Delay",
                  subtitle: "${_get(SessionSetting.keyRepeatDelay)} ms",
                  trailing: SizedBox(
                    width: 260,
                    child: Slider(
                      min: 150,
                      max: 1000,
                      divisions: 17,
                      value: _get(SessionSetting.keyRepeatDelay)
                          .toDouble()
                          .clamp(150, 1000),
                      onChanged: (v) =>
                          _set(SessionSetting.keyRepeatDelay, v.round()),
                    ),
                  ),
                ),
                SettingsRow(
                  title: "Rate",
                  subtitle: "${_get(SessionSetting.keyRepeatRate)} per second",
                  trailing: SizedBox(
                    width: 260,
                    child: Slider(
                      min: 5,
                      max: 60,
                      divisions: 11,
                      value: _get(SessionSetting.keyRepeatRate)
                          .toDouble()
                          .clamp(5, 60),
                      onChanged: (v) =>
                          _set(SessionSetting.keyRepeatRate, v.round()),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: TextField(
                      decoration:
                          InputDecoration(hintText: "Type here to test")),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LayoutPicker extends StatefulWidget {
  const _LayoutPicker({required this.catalog});
  final _XkbCatalog catalog;

  @override
  State<_LayoutPicker> createState() => _LayoutPickerState();
}

class _LayoutPickerState extends State<_LayoutPicker> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final String q = _query.toLowerCase();
    final List<(String, String, String)> options = [
      for (final MapEntry<String, String> l
          in widget.catalog.layouts.entries) ...[
        (l.key, "", l.value),
        for (final (String, String) v
            in widget.catalog.variants[l.key] ?? const [])
          (l.key, v.$1, v.$2),
      ],
    ]
        .where((o) => q.isEmpty || o.$3.toLowerCase().contains(q) || o.$1 == q)
        .toList();

    return AlertDialog(
      title: const Text("Add a keyboard layout"),
      content: SizedBox(
        width: 420,
        height: 440,
        child: Column(
          children: [
            SearchField(
                autofocus: true,
                hint: "Search layouts",
                onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(options[i].$3),
                  subtitle: Text(options[i].$2.isEmpty
                      ? options[i].$1
                      : "${options[i].$1} · ${options[i].$2}"),
                  onTap: () =>
                      Navigator.pop(context, (options[i].$1, options[i].$2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
