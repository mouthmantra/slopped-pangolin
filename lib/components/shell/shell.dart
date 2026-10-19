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
import 'package:flutter/services.dart';
import 'package:pangolin/components/overlays/notifications/queue.dart';
import 'package:pangolin/components/taskbar/app_list.dart';
import 'package:pangolin/components/taskbar/launcher.dart';
import 'package:pangolin/components/taskbar/notifications.dart';
import 'package:pangolin/components/taskbar/overview.dart';
import 'package:pangolin/components/taskbar/quick_settings.dart';
import 'package:pangolin/components/taskbar/search.dart';
import 'package:pangolin/components/taskbar/show_desktop.dart';
import 'package:pangolin/components/taskbar/taskbar.dart';
import 'package:pangolin/components/taskbar/tray.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/utils/wm/wm.dart';
import 'package:pangolin/widgets/input_region.dart';
import 'package:zenit_ui/zenit_ui.dart' show ZenitFonts;

class Shell extends StatefulWidget {
  final List<ShellOverlay> overlays;

  const Shell({
    required this.overlays,
    super.key,
  });

  @override
  ShellState createState() => ShellState();
}

class ShellState extends State<Shell> with TickerProviderStateMixin {
  /// Escape closes what's open (launcher, quick settings, menus...): the
  /// keyboard comes here while an overlay is shown, unless something in it
  /// (a search field, the overview) takes it and handles Escape itself.
  final FocusNode _keys = FocusNode(debugLabel: "shell overlays");

  @override
  void initState() {
    super.initState();
    ShellService.current.registerShell(this, widget.overlays);
    for (final ShellOverlay overlay in widget.overlays) {
      ShellService.current
          .getShowingNotifier(overlay.id)
          .addListener(_onOverlaysChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShellService.current.notifyStartupComplete();
    });
  }

  @override
  void dispose() {
    ShellInputRegion.instance.claim(this, false);
    _keys.dispose();
    super.dispose();
  }

  /// While an overlay is open the shell surface takes all input (clicking
  /// outside dismisses it) and the keyboard (launcher search, ...).
  void _onOverlaysChanged() {
    final bool shown = ShellService.current.currentlyShownOverlays.isNotEmpty;
    ShellInputRegion.instance.claim(this, shown);
    if (shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_keys.hasFocus) _keys.requestFocus();
      });
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        ShellService.current.currentlyShownOverlays.isNotEmpty) {
      ShellService.current.dismissEverything();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void notify() {
    setState(() {});
  }

  void showInformativeDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          message,
          style: TextStyle(fontFamily: ZenitFonts.monospaceOf(context)),
        ),
        shape: Constants.bigShape,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: (event) {
                  ShellService.current.dismissEverything();
                },
                behavior: HitTestBehavior.translucent,
              ),
            ),
            const Taskbar(
              leading: [
                LauncherButton(),
                SearchButton(),
                OverviewButton(),
              ],
              centerRelativeToScreen: true,
              center: [AppListElement()],
              trailing: [
                //TODO: here is the keyboard button
                //KeyboardButton(),
                TrayMenuButton(),
                QuickSettingsButton(),
                NotificationsButton(),
                ShowDesktopButton(),
              ],
            ),
            ...widget.overlays,
            Positioned(
              width: 420,
              right: WindowHierarchy.of(context).wmInsets.right + 8,
              bottom: WindowHierarchy.of(context).wmInsets.bottom + 8,
              child: const InputRegion(child: NotificationQueue()),
            ),
          ],
        ),
      ),
    );
  }
}
