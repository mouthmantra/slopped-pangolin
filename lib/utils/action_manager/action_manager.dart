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

import 'dart:async';
import 'dart:io';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/components/overlays/account_overlay.dart';
import 'package:pangolin/components/overlays/power_overlay.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/session_lock.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/data/app_ids.dart';

final Logger _logger = Logger("ActionManager");

class ActionManager {
  const ActionManager._();

  static ShellService get _shell => ShellService.current;

  static Future<void> showPowerMenu(BuildContext context) async {
    _shell.dismissEverything();
    await Future.delayed(Constants.animationDuration);
    _shell.showOverlay(
      PowerOverlay.overlayId,
      dismissEverything: false,
    );
  }

  static Future<void> showAccountMenu(BuildContext context) async {
    _shell.dismissEverything();
    await Future.delayed(Constants.animationDuration);
    _shell.showOverlay(
      AccountOverlay.overlayId,
      dismissEverything: false,
    );
  }

  /// Opens Settings, on [page] if given (its id, e.g. "sound").
  static void openSettings(BuildContext context, {String? page}) {
    _shell.dismissEverything();
    ApplicationService.current.startApp(
      DahliaApps.settings,
      args: [if (page != null) page],
    );
  }

  static bool _has(String command) {
    final String path = Platform.environment["PATH"] ?? "/usr/bin:/bin";
    return path
        .split(":")
        .any((dir) => dir.isNotEmpty && File("$dir/$command").existsSync());
  }

  /// Runs the first available command, detached so the shell never waits on
  /// it. Returns false when none of them exists.
  static bool _runFirst(List<List<String>> commands) {
    for (final List<String> command in commands) {
      if (!_has(command.first)) continue;
      Process.start(
        command.first,
        command.skip(1).toList(),
        mode: ProcessStartMode.detached,
      ).then(
        (_) {},
        onError: (Object e) =>
            _logger.warning("Couldn't run ${command.join(" ")}", e),
      );
      return true;
    }
    _logger.warning(
      "None of ${commands.map((c) => c.first).join(", ")} is installed",
    );
    return false;
  }

  static void powerOff() {
    _shell.dismissEverything();
    _runFirst([
      ["systemctl", "poweroff"],
      ["loginctl", "poweroff"],
      ["poweroff"],
    ]);
  }

  static void reboot() {
    _shell.dismissEverything();
    _runFirst([
      ["systemctl", "reboot"],
      ["loginctl", "reboot"],
      ["reboot"],
    ]);
  }

  /// Locks the session first, so that it wakes up locked.
  static Future<void> suspend() async {
    _shell.dismissEverything();
    await SessionLock.instance.lock();
    _runFirst([
      ["systemctl", "suspend"],
      ["loginctl", "suspend"],
    ]);
  }

  /// Pangolin's own lock screen, or an installed screen locker
  /// (ext-session-lock client) outside river.
  static bool get canLock =>
      SessionLock.instance.supported || _lockers.any((c) => _has(c.first));

  static const List<List<String>> _lockers = [
    ["waylock", "-fork-on-lock"],
    ["swaylock", "-f"],
    ["gtklock", "-d"],
  ];

  static void lock() {
    _shell.dismissEverything();
    if (SessionLock.instance.supported) {
      unawaited(SessionLock.instance.lock());
      return;
    }
    _runFirst(_lockers);
  }

  /// Ends the river session; every client, Pangolin included, goes with it.
  static Future<void> logout() async {
    _shell.dismissEverything();
    final WindowManagerService wm = WindowManagerService.current;
    // Exit right away: a clean exit tells the session's init script this was
    // a sign out, not a crash to recover from.
    if (wm.managesSessionWindows) await wm.exitSession();
    exit(0);
  }
}
