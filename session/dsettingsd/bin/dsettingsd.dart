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
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:dsettings/server.dart';
import 'package:path/path.dart' as p;

/// Session settings daemon: serves the dsettings tables stored in
/// `$XDG_CONFIG_HOME/dsettings` (or the directory given as the first
/// argument) on the session bus as `io.dahlia.DSettings`.
///
/// Started on demand through D-Bus activation, or by the session itself.
Future<void> main(List<String> args) async {
  final Map<String, String> env = Platform.environment;
  final String configHome =
      env["XDG_CONFIG_HOME"] ?? p.join(env["HOME"] ?? "/tmp", ".config");
  final Directory directory =
      Directory(args.isNotEmpty ? args.first : p.join(configHome, "dsettings"));
  directory.createSync(recursive: true);

  final DBusClient client = DBusClient.session();
  final DBusRequestNameReply reply = await client.requestName(
    "io.dahlia.DSettings",
    flags: {DBusRequestNameFlag.doNotQueue},
  );
  if (reply != DBusRequestNameReply.primaryOwner &&
      reply != DBusRequestNameReply.alreadyOwner) {
    stderr.writeln("dsettingsd: io.dahlia.DSettings is already provided");
    await client.close();
    exit(0);
  }

  final DSettings dsettings = await DSettings.newInstance(directory);
  await client.registerObject(dsettings);
  await dsettings.registerTables();

  Future<void> shutdown(ProcessSignal _) async {
    // At the end of a session the bus may already be gone: tables are saved
    // either way, so leave quietly.
    try {
      await dsettings.close();
      await client.releaseName("io.dahlia.DSettings");
      await client.close();
    } catch (_) {}
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);

  // package:dbus doesn't report a closed connection, and the signal watchers
  // keep this process alive: check the bus is still there so the daemon
  // doesn't outlive its session (e.g. one started by dbus-run-session).
  Timer.periodic(const Duration(seconds: 10), (_) async {
    try {
      await client
          .callMethod(
            destination: "org.freedesktop.DBus",
            path: DBusObjectPath("/org/freedesktop/DBus"),
            interface: "org.freedesktop.DBus.Peer",
            name: "Ping",
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      stderr.writeln("dsettingsd: lost the session bus, exiting");
      exit(0);
    }
  });
}
