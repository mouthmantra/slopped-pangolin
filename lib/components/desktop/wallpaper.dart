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
import 'package:pangolin/components/desktop/wallpaper_picker.dart';
import 'package:pangolin/components/shell/shell_popups.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/data/app_ids.dart';
import 'package:pangolin/widgets/context_menu.dart';
import 'package:pangolin/widgets/resource/image/image.dart';
import 'package:provider/provider.dart';

class WallpaperLayer extends StatelessWidget
    with StatelessServiceListener<CustomizationService> {
  const WallpaperLayer({super.key});

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    return SizedBox.expand(
      child: ChangeNotifierProvider.value(
        value: WindowManagerService.current.controller,
        child: _WallpaperContextMenu(
          child: ResourceImage(
            resource: service.wallpaper,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _WallpaperContextMenu extends StatelessWidget {
  const _WallpaperContextMenu({
    required this.child,
  });

  final Widget child;

  static void _changeWallpaper(BuildContext context) {
    showDialog(
      barrierColor: Colors.transparent,
      context: shellPopupContext(context),
      builder: (context) => const WallpaperPicker(),
    );
  }

  static void _openSettings() =>
      ApplicationService.current.startApp(DahliaApps.settings);

  // In a session the desktop is river's BACKGROUND layer: the menu and the
  // picker go on the shell surface, above windows (see shell_popups.dart).
  Future<void> _showSessionMenu(BuildContext context, Offset position) async {
    final String? action = await showShellMenu<String>(
      context: context,
      globalPosition: position,
      items: const [
        PopupMenuItem(
          value: "wallpaper",
          child: ListTile(
            dense: true,
            leading: Icon(Icons.image),
            title: Text("Change Wallpaper"),
          ),
        ),
        PopupMenuItem(
          value: "settings",
          child: ListTile(
            dense: true,
            leading: Icon(Icons.settings_outlined),
            title: Text("Settings"),
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case "wallpaper":
        _changeWallpaper(context);
      case "settings":
        _openSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PangolinSession.isSession) {
      Offset? longPressPosition;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => _showSessionMenu(context, d.globalPosition),
        onLongPressDown: (d) => longPressPosition = d.globalPosition,
        onLongPress: () {
          if (longPressPosition != null) {
            _showSessionMenu(context, longPressPosition!);
          }
        },
        child: child,
      );
    }

    return ContextMenu(
      entries: [
        ContextMenuItem(
          onTap: () => _changeWallpaper(context),
          leading: const Icon(Icons.image),
          child: const Text("Change Wallpaper"),
        ),
        ContextMenuItem(
          onTap: _openSettings,
          leading: const Icon(Icons.settings_outlined),
          child: const Text("Settings"),
        ),
      ],
      child: child,
    );
  }
}
