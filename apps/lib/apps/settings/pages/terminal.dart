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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/apps/terminal/themes.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:xterm/xterm.dart';

/// Terminal: colors, text and behavior.
class TerminalSettingsPage extends StatelessWidget {
  const TerminalSettingsPage({super.key});

  static const List<int> _scrollbackChoices = [
    1000,
    5000,
    10000,
    50000,
    100000
  ];

  @override
  Widget build(BuildContext context) {
    final PreferencesService prefs = PreferencesService.current;
    T get<T extends Object>(SessionSetting<T> s) =>
        prefs.get<T>(s.key) ?? s.defaultValue;
    void set<T extends Object>(SessionSetting<T> s, T value) =>
        prefs.set<T>(s.key, value);

    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final String current = get(SessionSetting.terminalTheme);
        final int scrollback = get(SessionSetting.terminalScrollback);
        return SettingsPageBody(
          children: [
            SettingsGroup(
              title: "Color theme",
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final MapEntry<String, (String, TerminalTheme)> e
                          in terminalThemes.entries)
                        _ThemePreview(
                          name: e.value.$1,
                          theme: e.value.$2,
                          selected: e.key == current,
                          onTap: () => set(SessionSetting.terminalTheme, e.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: "Text",
              children: [
                SettingsRow(
                  icon: Icons.format_size_rounded,
                  title: "Font size",
                  subtitle:
                      "${get(SessionSetting.terminalFontSize).round()} pt · the monospace font is set in Appearance",
                  trailing: SizedBox(
                    width: 220,
                    child: Slider(
                      min: 8,
                      max: 28,
                      divisions: 20,
                      value: get(SessionSetting.terminalFontSize).clamp(8, 28),
                      onChanged: (v) => set(
                          SessionSetting.terminalFontSize, v.roundToDouble()),
                    ),
                  ),
                ),
                SettingsRow(
                  icon: Icons.text_fields_rounded,
                  title: "Cursor",
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: "block", label: Text("Block")),
                      ButtonSegment(
                          value: "underline", label: Text("Underline")),
                      ButtonSegment(value: "bar", label: Text("Bar")),
                    ],
                    selected: {get(SessionSetting.terminalCursorShape)},
                    onSelectionChanged: (v) =>
                        set(SessionSetting.terminalCursorShape, v.first),
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: "Behavior",
              children: [
                SettingsRow(
                  icon: Icons.history_rounded,
                  title: "Scrollback",
                  subtitle: "Lines kept above the screen (new tabs)",
                  trailing: DropdownButton<int>(
                    value: _scrollbackChoices.contains(scrollback)
                        ? scrollback
                        : null,
                    hint: Text("$scrollback lines"),
                    underline: const SizedBox(),
                    items: [
                      for (final int lines in _scrollbackChoices)
                        DropdownMenuItem(
                          value: lines,
                          child: Text("$lines lines"),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) set(SessionSetting.terminalScrollback, v);
                    },
                  ),
                ),
                SettingsRow(
                  icon: Icons.opacity_rounded,
                  title: "Background opacity",
                  subtitle: "Below 100%, the background is frosted glass",
                  trailing: SizedBox(
                    width: 220,
                    child: Slider(
                      min: 0.5,
                      max: 1,
                      divisions: 10,
                      label:
                          "${(get(SessionSetting.terminalOpacity) * 100).round()}%",
                      value: get(SessionSetting.terminalOpacity).clamp(0.5, 1),
                      onChanged: (v) => set(SessionSetting.terminalOpacity, v),
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

/// A miniature terminal in [theme].
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.name,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final TerminalTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData appTheme = Theme.of(context);
    final TextStyle mono = TextStyle(
      fontFamily: ZenitFonts.monospaceOf(context),
      fontSize: 11,
      height: 1.4,
    );
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: selected
                    ? appTheme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: 148,
                height: 84,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.background,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text: "user",
                              style: TextStyle(color: theme.green)),
                          TextSpan(
                              text: ":",
                              style: TextStyle(color: theme.foreground)),
                          TextSpan(
                              text: "~", style: TextStyle(color: theme.blue)),
                          TextSpan(
                              text: "\$ ls",
                              style: TextStyle(color: theme.foreground)),
                        ],
                      ),
                      style: mono,
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text: "src ",
                              style: TextStyle(color: theme.blue)),
                          TextSpan(
                              text: "run.sh ",
                              style: TextStyle(color: theme.green)),
                          TextSpan(
                              text: "TODO",
                              style: TextStyle(color: theme.yellow)),
                        ],
                      ),
                      style: mono,
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                              text: "error",
                              style: TextStyle(color: theme.red)),
                          TextSpan(
                              text: " ok", style: TextStyle(color: theme.cyan)),
                          TextSpan(
                              text: " █",
                              // Terminal draws its cursor in the accent.
                              style: TextStyle(
                                  color: appTheme.colorScheme.primary)),
                        ],
                      ),
                      style: mono,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(name, style: appTheme.textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}
