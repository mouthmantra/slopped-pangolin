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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:path/path.dart' as p;

/// Small helpers for talking to the rest of the system.
abstract final class SystemUtils {
  static final Map<String, String?> _whichCache = {};

  /// Absolute path of [executable] in $PATH, or null.
  static String? which(String executable) {
    return _whichCache.putIfAbsent(executable, () {
      final String path = Platform.environment["PATH"] ?? "/usr/bin:/bin";
      for (final String dir in path.split(":")) {
        if (dir.isEmpty) continue;
        final File candidate = File(p.join(dir, executable));
        if (candidate.existsSync()) return candidate.path;
      }
      return null;
    });
  }

  /// Runs a command and returns its stdout, or null if it failed or isn't
  /// installed.
  static Future<String?> run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (which(executable) == null && !executable.contains("/")) return null;
    try {
      final ProcessResult result = await Process.run(
        executable,
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      if (result.exitCode != 0) return null;
      return result.stdout as String;
    } on Object {
      return null;
    }
  }

  /// Opens a file or URL with the default application.
  static Future<void> open(String target) async {
    for (final String opener in ["xdg-open", "gio"]) {
      if (which(opener) == null) continue;
      final List<String> args = opener == "gio" ? ["open", target] : [target];
      await Process.start(opener, args, mode: ProcessStartMode.detached);
      return;
    }
  }

  /// Starts another dahliaOS application.
  static Future<void> launchApp(String name, [List<String> args = const []]) {
    return Process.start(
      Platform.resolvedExecutable,
      [name, ...args],
      mode: ProcessStartMode.detached,
    );
  }

  static String get home => Platform.environment["HOME"] ?? "/";

  /// Whether a system bus socket exists. package:dbus reports a missing bus
  /// from inside signal subscriptions, where callers can't catch it.
  static bool get systemBusAvailable {
    final String address = Platform.environment["DBUS_SYSTEM_BUS_ADDRESS"] ??
        "unix:path=/run/dbus/system_bus_socket";
    for (final String part in address.split(";")) {
      if (!part.startsWith("unix:")) return true;
      final RegExpMatch? path = RegExp("path=([^,]+)").firstMatch(part);
      if (path == null) return true;
      if (FileSystemEntity.typeSync(path.group(1)!) != FileSystemEntityType.notFound) {
        return true;
      }
    }
    return false;
  }

  static String get user =>
      Platform.environment["USER"] ?? Platform.environment["LOGNAME"] ?? "user";
}

/// Sends desktop notifications through org.freedesktop.Notifications (served
/// by Pangolin in a dahliaOS session).
class DesktopNotifications {
  DesktopNotifications(this.appName, {this.appIcon = ""});

  final String appName;
  final String appIcon;
  DBusClient? _client;

  Future<int?> notify(
    String summary, {
    String body = "",
    int expireTimeout = -1,
    int replaces = 0,
  }) async {
    try {
      _client ??= DBusClient.session();
      final DBusMethodSuccessResponse response = await _client!.callMethod(
        destination: "org.freedesktop.Notifications",
        path: DBusObjectPath("/org/freedesktop/Notifications"),
        interface: "org.freedesktop.Notifications",
        name: "Notify",
        values: [
          DBusString(appName),
          DBusUint32(replaces),
          DBusString(appIcon),
          DBusString(summary),
          DBusString(body),
          DBusArray.string(const []),
          DBusDict.stringVariant(const {}),
          DBusInt32(expireTimeout),
        ],
        replySignature: DBusSignature("u"),
      );
      return response.values.first.asUint32();
    } on Object {
      return null;
    }
  }

  Future<void> close() async => _client?.close();
}
