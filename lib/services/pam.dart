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

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:logging/logging.dart';

/// Outcome of a password check.
enum PamResult { success, wrongPassword, unavailable }

/// Checks the user's password with PAM (libpam is loaded at runtime, so
/// Pangolin builds without its headers and runs on any distribution that
/// has it).
abstract final class Pam {
  static final Logger _logger = Logger("Pam");

  /// Whether passwords can be checked here at all: without libpam (e.g. a
  /// system without PAM) a locked screen could never be unlocked.
  static final bool available = () {
    try {
      DynamicLibrary.open("libpam.so.0");
      return true;
    } on ArgumentError {
      return false;
    }
  }();

  /// PAM service used to check passwords: Pangolin's own when installed
  /// system-wide (/etc/pam.d/pangolin), the login service otherwise.
  static String get service {
    for (final String name in ["pangolin", "login", "system-auth", "other"]) {
      if (File("/etc/pam.d/$name").existsSync() ||
          File("/usr/lib/pam.d/$name").existsSync() ||
          File("/usr/share/pam.d/$name").existsSync()) {
        return name;
      }
    }
    return "login";
  }

  static String get user {
    final String? name =
        Platform.environment["USER"] ?? Platform.environment["LOGNAME"];
    if (name != null && name.isNotEmpty) return name;
    final ProcessResult result = Process.runSync("id", ["-un"]);
    return (result.stdout as String).trim();
  }

  /// Checks [password] for the current user, in a process of its own (the
  /// shell's binary, `--check-password`, session/native/check_password.cc):
  /// in this one the Dart VM reaps child processes, and pam_unix then lost
  /// its helper's answer and turned right passwords down at random.
  static Future<PamResult> authenticate(String password) async {
    final Process process;
    try {
      process = await Process.start(
        Platform.resolvedExecutable,
        ["--check-password", service, user],
      );
    } on ProcessException catch (e) {
      _logger.warning("Couldn't check the password: $e");
      return PamResult.unavailable;
    }
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logger.info);
    process.stdout.drain<void>();
    process.stdin.add(utf8.encode(password));
    await process.stdin.close();
    return switch (await process.exitCode) {
      0 => PamResult.success,
      1 => PamResult.wrongPassword,
      _ => PamResult.unavailable,
    };
  }
}
