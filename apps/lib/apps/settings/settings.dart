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

import 'package:dahlia_apps/apps/settings/pages/about.dart';
import 'package:dahlia_apps/apps/settings/pages/appearance.dart';
import 'package:dahlia_apps/apps/settings/pages/applications.dart';
import 'package:dahlia_apps/apps/settings/pages/bluetooth.dart';
import 'package:dahlia_apps/apps/settings/pages/date_time.dart';
import 'package:dahlia_apps/apps/settings/pages/displays.dart';
import 'package:dahlia_apps/apps/settings/pages/input.dart';
import 'package:dahlia_apps/apps/settings/pages/network.dart';
import 'package:dahlia_apps/apps/settings/pages/power.dart';
import 'package:dahlia_apps/apps/settings/pages/sound.dart';
import 'package:dahlia_apps/apps/settings/pages/terminal.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;

final DahliaAppSpec settingsApp = DahliaAppSpec(
  name: "settings",
  title: "Settings",
  builder: (context, args) =>
      SettingsPage(initialPage: args.isNotEmpty ? args.first : null),
);

class _SettingsPageInfo {
  const _SettingsPageInfo(
      this.id, this.title, this.subtitle, this.icon, this.builder);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}

final List<_SettingsPageInfo?> _pages = [
  _SettingsPageInfo("network", "Network", "Wired and wireless connections",
      Icons.wifi_rounded, (_) => const NetworkPage()),
  _SettingsPageInfo("bluetooth", "Bluetooth", "Devices and adapters",
      Icons.bluetooth_rounded, (_) => const BluetoothPage()),
  null,
  _SettingsPageInfo(
      "appearance",
      "Appearance",
      "Theme, accent color, wallpaper",
      Icons.palette_outlined,
      (_) => const AppearancePage()),
  _SettingsPageInfo("displays", "Displays", "Resolution, scale and layout",
      Icons.monitor_rounded, (_) => const DisplaysPage()),
  _SettingsPageInfo("input", "Keyboard", "Layouts and key repeat",
      Icons.keyboard_rounded, (_) => const InputPage()),
  _SettingsPageInfo("mouse", "Mouse", "Speed, acceleration, scrolling",
      Icons.mouse_rounded, (_) => const InputPage(section: InputSection.mouse)),
  _SettingsPageInfo("touchpad", "Touchpad", "Tapping, scrolling, gestures",
      Icons.touch_app, (_) => const InputPage(section: InputSection.touchpad)),
  _SettingsPageInfo("sound", "Sound", "Volume and output devices",
      Icons.volume_up_rounded, (_) => const SoundPage()),
  _SettingsPageInfo("terminal", "Terminal", "Colors, text and scrollback",
      Icons.terminal_rounded, (_) => const TerminalSettingsPage()),
  _SettingsPageInfo("power", "Power", "Battery and power profiles",
      Icons.battery_charging_full_rounded, (_) => const PowerPage()),
  null,
  _SettingsPageInfo("applications", "Applications", "Installed apps",
      Icons.apps_rounded, (_) => const ApplicationsPage()),
  _SettingsPageInfo("datetime", "Date & Time", "Time zone, clock, language",
      Icons.schedule_rounded, (_) => const DateTimePage()),
  _SettingsPageInfo("about", "About", "This device and dahliaOS",
      Icons.info_outline_rounded, (_) => const AboutPage()),
];

class SettingsPage extends StatefulWidget {
  const SettingsPage({this.initialPage, super.key});

  /// Page id to open first, e.g. `dahlia_apps settings displays`.
  final String? initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _current = _pages
          .whereType<_SettingsPageInfo>()
          .any((pg) => pg.id == widget.initialPage)
      ? widget.initialPage!
      : "appearance";
  final TextEditingController _searchController = TextEditingController();
  String _search = "";
  bool _searching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(String id) {
    setState(() {
      _current = id;
      _searching = false;
      _search = "";
      _searchController.clear();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      _search = "";
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final _SettingsPageInfo page = _pages
        .whereType<_SettingsPageInfo>()
        .firstWhere((pg) => pg.id == _current);
    final String query = _search.trim().toLowerCase();
    final List<_SettingsPageInfo> results = [
      for (final _SettingsPageInfo pg in _pages.whereType<_SettingsPageInfo>())
        if (query.isNotEmpty &&
            (pg.title.toLowerCase().contains(query) ||
                pg.subtitle.toLowerCase().contains(query)))
          pg,
    ];

    // The rail continues the title bar: one surface of the same glass.
    return ListenableBuilder(
      listenable: Listenable.merge([ZenitBlur.state, PreferencesService.current]),
      builder: (context, _) => DahliaScaffold(
        titlebarColor: _SettingsRail.colorOf(context),
        body: Row(
          children: [
            _SettingsRail(
              current: _searching ? null : _current,
              searching: _searching,
              onSelected: _open,
              onSearch: _toggleSearch,
            ),
            Expanded(
              child: _searching
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                          child: SearchField(
                            controller: _searchController,
                            hint: "Search settings",
                            autofocus: true,
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        Expanded(
                          child: query.isEmpty
                              ? const SizedBox.shrink()
                              : _SearchResults(
                                  results: results, onSelected: _open),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Lined up with the groups of SettingsPageBody.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth: SettingsPageBody.maxWidth),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(page.title,
                                      style: theme.textTheme.headlineSmall),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey(page.id),
                            child: page.builder(context),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Navigation rail of the dahliaOS design: round accent buttons on an accent
/// tinted pane, the current page highlighted around its button.
class _SettingsRail extends StatelessWidget {
  const _SettingsRail({
    required this.current,
    required this.searching,
    required this.onSelected,
    required this.onSearch,
  });

  final String? current;
  final bool searching;
  final ValueChanged<String> onSelected;
  final VoidCallback onSearch;

  /// Continues the title bar (same tint, translucent over river's blur).
  static Color colorOf(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color base = DahliaTitlebar.accentTint
        ? Color.alphaBlend(
            theme.colorScheme.primary.withValues(alpha: dark ? 0.16 : 0.09),
            theme.scaffoldBackgroundColor,
          )
        : theme.colorScheme.surface.themedLightness(context, 0.05);
    return ZenitBlur.active ? base.withValues(alpha: ZenitBlur.fillOpacity) : base;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget rail = ColoredBox(
      color: colorOf(context),
      child: SizedBox(
        width: 88,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            _RailItem(
              tooltip: "Search",
              selected: searching,
              onTap: onSearch,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.search_rounded,
                    size: 20, color: theme.colorScheme.onSurface),
              ),
            ),
            const SizedBox(height: 14),
            for (final _SettingsPageInfo? pg in _pages)
              if (pg == null)
                const SizedBox(height: 14)
              else
                _RailButton(
                  page: pg,
                  selected: pg.id == current,
                  onTap: () => onSelected(pg.id),
                ),
          ],
        ),
      ),
    );
    if (!ZenitBlur.active) return rail;
    return BlurRegion(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(DahliaTitlebar.windowRadius),
      ),
      child: rail,
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton(
      {required this.page, required this.selected, required this.onTap});

  final _SettingsPageInfo page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RailItem(
      tooltip: page.title,
      selected: selected,
      onTap: onTap,
      child: _PageIcon(page: page, size: 40),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: dark ? 0.32 : 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              height: 56,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageIcon extends StatelessWidget {
  const _PageIcon({required this.page, required this.size});

  final _SettingsPageInfo page;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child:
          Icon(page.icon, size: size / 2, color: theme.colorScheme.onPrimary),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onSelected});

  final List<_SettingsPageInfo> results;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: "No results",
        subtitle: "No settings match your search",
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        for (final _SettingsPageInfo pg in results)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelected(pg.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      _PageIcon(page: pg, size: 36),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pg.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(pg.subtitle, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Scrollable body shared by settings pages.
class SettingsPageBody extends StatelessWidget {
  const SettingsPageBody({required this.children, super.key});

  static const double maxWidth = 820;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}
