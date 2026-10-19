// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

// pangolin-displays [--greeter] [--watch]
//
// Sets up the connected monitors. With --watch, keeps running and does it
// again whenever monitors are connected or disconnected. The session and the
// login screen start it before the shell, so that it comes up at the right
// resolution and scale.
//
// In a session: the configuration saved (by Settings) for these monitors,
// else GNOME's (~/.config/monitors.xml, then /etc/xdg/monitors.xml). The
// resulting setup is shared with the login screen (DisplayProfiles.publish).
//
// On the login screen (--greeter): the setup the last user's desktop had
// for these monitors, else the most recent one any user shared for them,
// else /etc/xdg/monitors.xml, else what was saved for the login screen.

import 'dart:async';
import 'dart:io';

import 'package:display_config/display_config.dart';

Future<void> main(List<String> args) async {
  final bool watch = args.contains("--watch");
  final bool greeter = args.contains("--greeter");

  final DisplayConfigurator? configurator;
  try {
    configurator = await DisplayConfigurator.connect();
  } on Object catch (e) {
    stderr.writeln("pangolin-displays: cannot connect to the compositor: $e");
    exit(1);
  }
  if (configurator == null) {
    stderr.writeln("pangolin-displays: the compositor has no output management");
    exit(1);
  }

  Set<String>? applied;
  Future<void> sync() async {
    final Set<String> ids = configurator!.ids;
    // Only when the set of monitors changes: what the user changes in the
    // meantime (in Settings) stays.
    if (applied != null &&
        applied!.length == ids.length &&
        applied!.containsAll(ids)) {
      return;
    }
    applied = ids;
    try {
      final String? source = greeter
          ? await _applyForGreeter(configurator, ids)
          : await _applyForSession(configurator);
      if (source != null) {
        stderr.writeln("pangolin-displays: applied $source");
      }
    } on Object catch (e) {
      stderr.writeln("pangolin-displays: $e");
    }
  }

  // The desktop's setup, as river reports it once applied, for the login
  // screen.
  Timer? publishTimer;
  void schedulePublish() {
    if (greeter) return;
    publishTimer?.cancel();
    publishTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await DisplayProfiles.publish(configurator!.current);
      } on Object catch (e) {
        stderr.writeln("pangolin-displays: couldn't share the setup: $e");
      }
    });
  }

  // Never all off: the monitor in use was unplugged and nothing saved
  // turns on one that's left (an external one unplugged from a laptop
  // whose panel was off).
  Future<void> keepOneOn() async {
    try {
      final OutputHeadState? head = await configurator!.ensureOneEnabled();
      if (head != null) {
        stderr.writeln("pangolin-displays: no monitor was on, turned on ${head.name}");
      }
    } on Object catch (e) {
      stderr.writeln("pangolin-displays: $e");
    }
  }

  await sync();
  await keepOneOn();
  if (!watch) {
    await configurator.close();
    return;
  }
  schedulePublish();
  configurator.changes.listen(
    (_) async {
      await sync();
      await keepOneOn();
      schedulePublish();
    },
    onDone: () => exit(0),
  );
}

Future<String?> _applyForSession(DisplayConfigurator configurator) async {
  if (await configurator.applySaved()) return "the saved configuration";
  final String config = Platform.environment["XDG_CONFIG_HOME"]?.isNotEmpty == true
      ? Platform.environment["XDG_CONFIG_HOME"]!
      : "${Platform.environment["HOME"] ?? "."}/.config";
  if (await configurator.applyMonitorsXml("$config/monitors.xml")) {
    return "GNOME's configuration ($config/monitors.xml)";
  }
  if (await configurator.applyMonitorsXml()) {
    return "the system's monitors.xml";
  }
  return null;
}

Future<String?> _applyForGreeter(
  DisplayConfigurator configurator,
  Set<String> ids,
) async {
  final List<String> users = DisplayProfiles.sharingUsers();
  final String? last = _lastGreeterUser();
  if (last != null && users.remove(last)) users.insert(0, last);
  for (final String user in users) {
    final List<OutputSettings>? profile = DisplayProfiles.sharedBy(user, ids);
    if (profile != null) {
      await configurator.applyProfile(profile);
      return "$user's desktop setup";
    }
  }
  if (await configurator.applyMonitorsXml()) {
    return "the system's monitors.xml";
  }
  if (await configurator.applySaved()) return "the saved configuration";
  return null;
}

/// The user who logged in last, as the login screen remembers it.
String? _lastGreeterUser() {
  final String? state = Platform.environment["XDG_STATE_HOME"];
  if (state == null) return null;
  try {
    final List<String> lines = File("$state/pangolin-greeter").readAsLinesSync();
    return lines.isEmpty || lines.first.isEmpty ? null : lines.first;
  } on FileSystemException {
    return null;
  }
}
