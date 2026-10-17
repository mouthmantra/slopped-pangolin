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

import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:yaru_window/yaru_window.dart';

final DahliaAppSpec welcomeApp = DahliaAppSpec(
  name: "welcome",
  title: "Welcome",
  builder: (context, args) => const WelcomePage(),
);

class _AppInfo {
  const _AppInfo(this.name, this.title, this.description);
  final String name;
  final String title;
  final String description;
}

const List<_AppInfo> _bundledApps = [
  _AppInfo("files", "Files", "Browse and organize your files"),
  _AppInfo("settings", "Settings", "Make dahliaOS yours"),
  _AppInfo("store", "App Store", "Install apps from Flathub"),
  _AppInfo("terminal", "Terminal", "A powerful command line"),
  _AppInfo("text_editor", "Text Editor", "Write notes and code"),
  _AppInfo("calculator", "Calculator", "Quick and scientific math"),
  _AppInfo("clock", "Clock", "World clocks, alarms and timers"),
  _AppInfo("gallery", "Gallery", "Your pictures and screenshots"),
  _AppInfo("activity_monitor", "Activity Monitor", "Processes and resources"),
  _AppInfo("logs", "Logs", "See what your system is doing"),
];

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final PageController _pages = PageController();
  int _page = 0;
  static const int _pageCount = 4;

  void _go(int page) {
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DahliaScaffold(
      title: const Text("Welcome to dahliaOS"),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (p) => setState(() => _page = p),
              children: const [
                _IntroPage(),
                _PersonalizePage(),
                _AppsPage(),
                _CommunityPage(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(
              children: [
                TextButton(
                  onPressed: _page == 0 ? null : () => _go(_page - 1),
                  child: const Text("Back"),
                ),
                const Spacer(),
                for (int i = 0; i < _pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _page == _pageCount - 1
                      ? () => YaruWindow.of(context).close()
                      : () => _go(_page + 1),
                  child: Text(_page == _pageCount - 1 ? "Get started" : "Next"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Image.asset(
                theme.brightness == Brightness.dark
                    ? "assets/images/dahliaOS-white.png"
                    : "assets/images/dahliaOS-modern.png",
                height: 72,
              ),
              const SizedBox(height: 32),
              Text(
                "Welcome!",
                style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 16),
              Text(
                "dahliaOS is a modern, lightweight operating system with an "
                "intuitive interface and efficient multitasking. Pangolin, its "
                "desktop, is written in Flutter and runs on the river Wayland "
                "compositor.",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: const [
                  _Feature(Icons.dashboard_customize_outlined, "Customizable"),
                  _Feature(Icons.flash_on_outlined, "Lightweight"),
                  _Feature(Icons.lock_outline_rounded, "Private"),
                  _Feature(Icons.code_rounded, "Open source"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18, color: theme.colorScheme.primary),
      label: Text(label),
    );
  }
}

class _PersonalizePage extends StatelessWidget {
  const _PersonalizePage();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableServiceBuilder<CustomizationService>(
      builder: (context, _) {
        final CustomizationService customization = CustomizationService.current;
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Text("Make it yours", style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    "Changes apply instantly to the desktop and every app.",
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ThemeModeCard(
                        label: "Light",
                        dark: false,
                        selected: !customization.darkMode,
                        onTap: () => customization.darkMode = false,
                      ),
                      const SizedBox(width: 24),
                      ThemeModeCard(
                        label: "Dark",
                        dark: true,
                        selected: customization.darkMode,
                        onTap: () => customization.darkMode = true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text("Accent color", style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final BuiltinColor color in BuiltinColor.values)
                        AccentSwatch(
                          color: color.value,
                          selected: customization.accentColor == color.resource,
                          onTap: () => customization.accentColor = color.resource,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AppsPage extends StatelessWidget {
  const _AppsPage();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        children: [
          Text("Just the basics", style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            "dahliaOS ships a small set of native apps. Get anything else from the App Store.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 200,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                for (final _AppInfo app in _bundledApps)
                  ZenitSection(
                    child: InkWell(
                      onTap: () => SystemUtils.launchApp(app.name),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset("assets/icons/io.dahliaos.${app.name}.png", width: 48, height: 48),
                            const SizedBox(height: 8),
                            Text(app.title, style: theme.textTheme.titleSmall),
                            Text(
                              app.description,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityPage extends StatelessWidget {
  const _CommunityPage();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<(IconData, String, String, String)> links = [
      (Icons.public_rounded, "Website", "Learn more about the project", "https://dahliaos.io"),
      (Icons.menu_book_rounded, "Documentation", "Guides and reference", "https://docs.dahliaos.io"),
      (Icons.code_rounded, "GitHub", "Browse the source and contribute", "https://github.com/dahliaOS"),
      (Icons.forum_rounded, "Discord", "Chat with the community", "https://dahliaos.io/discord"),
      (Icons.volunteer_activism_rounded, "Donate", "Support development", "https://dahliaos.io/donate"),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Text("Join the community", style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                "dahliaOS is and always will be free and open source.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SettingsGroup(
                children: [
                  for (final (icon, title, subtitle, url) in links)
                    SettingsRow(
                      icon: icon,
                      title: title,
                      subtitle: subtitle,
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => SystemUtils.open(url),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
