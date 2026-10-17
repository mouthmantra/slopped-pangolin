/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/components/desktop/wallpaper.dart';
import 'package:pangolin/components/overlays/account_overlay.dart';
import 'package:pangolin/components/overlays/launcher/compact_launcher_overlay.dart';
import 'package:pangolin/components/overlays/network_secret_overlay.dart';
import 'package:pangolin/components/overlays/notifications/overlay.dart';
import 'package:pangolin/components/overlays/overview/backdrop.dart';
import 'package:pangolin/components/overlays/overview_overlay.dart';
import 'package:pangolin/components/shell/screenshot.dart';
import 'package:pangolin/components/overlays/polkit_overlay.dart';
import 'package:pangolin/components/overlays/power_overlay.dart';
import 'package:pangolin/components/overlays/quick_settings/quick_settings_overlay.dart';
import 'package:pangolin/components/overlays/search/search_overlay.dart';
import 'package:pangolin/components/overlays/tray_overlay.dart';
import 'package:pangolin/components/overlays/welcome_overlay.dart';
import 'package:pangolin/components/shell/shell.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/wm/layout.dart';
import 'package:pangolin/utils/wm/wm.dart';

/// The whole desktop inside a single surface (windowed mode): wallpaper,
/// built-in windows and the shell.
class Desktop extends StatelessWidget {
  const Desktop({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: Stack(
        children: [
          WallpaperLayer(),
          Positioned.fill(child: ShellHost()),
        ],
      ),
    );
  }
}

/// Session mode, BACKGROUND layer: the wallpaper below every window, and the
/// overview's backdrop below the windows it shows.
class DesktopSurface extends StatelessWidget {
  const DesktopSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const WallpaperLayer(),
        ListenableServiceBuilder<CustomizationService>(
          builder: (context, _) => OverviewBackdrop(
            wallpaper: CustomizationService.current.wallpaper,
          ),
        ),
      ],
    );
  }
}

/// Session mode, TOP layer: taskbar, launcher and the other overlays, drawn
/// on a transparent surface above application windows.
class ShellSurface extends StatelessWidget {
  const ShellSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      type: MaterialType.transparency,
      child: ShellHost(),
    );
  }
}

/// Hosts the shell inside the Utopia hierarchy owned by the window manager
/// service, which also provides the work area insets the overlays use.
class ShellHost extends StatefulWidget {
  const ShellHost({super.key});

  @override
  State<ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<ShellHost> {
  static final Logger _logger = Logger("ShellHost");

  static const shellEntry = WindowEntry(
    features: [],
    layoutInfo: FreeformLayoutInfo(
      alwaysOnTop: true,
      alwaysOnTopMode: AlwaysOnTopMode.systemOverlay,
    ),
    properties: {
      WindowEntry.title: "shell",
      WindowExtras.stableId: "shell",
      WindowEntry.showOnTaskbar: false,
      WindowEntry.icon: null,
    },
  );

  @override
  void initState() {
    super.initState();
    ShellService.current.onShellReadyCallback(() {
      if (CustomizationService.current.showWelcomeScreen &&
          !PangolinSession.isRestart) {
        ShellService.current.showOverlay("welcome");
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      WindowManagerService.current.push(
        shellEntry.newInstance(
          content: Shell(
            overlays: [
              CompactLauncherOverlay(),
              SearchOverlay(),
              OverviewOverlay(),
              QuickSettingsOverlay(),
              PowerOverlay(),
              AccountOverlay(),
              WelcomeOverlay(),
              NotificationsOverlay(),
              TrayMenuOverlay(),
              ScreenshotOverlay(),
              PolkitOverlay(),
              NetworkSecretOverlay(),
            ],
          ),
        ),
      );
      _logger.info("Initialized desktop shell (${PangolinSession.mode.name})");
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WindowManagerService.current.controller.wmInsets =
        const EdgeInsets.only(bottom: PangolinSession.taskbarHeight);
  }

  @override
  Widget build(BuildContext context) {
    return WindowHierarchy(
      controller: WindowManagerService.current.controller,
      layoutDelegate: const PangolinLayoutDelegate(),
    );
  }
}
