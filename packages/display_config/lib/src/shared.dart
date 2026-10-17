// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// What users share with the login screen, which runs as its own user and
/// can't read their home directories: their display configuration and their
/// wallpaper.
///
/// They are files named after the user ("logan.displays.json") in a
/// directory every user can write to, sticky like /tmp so nobody can replace
/// another user's files (tool/install.sh creates /var/lib/pangolin/users).
/// The login screen only uses a file owned by the user it's named after.
abstract final class SharedUserFiles {
  static String get directory =>
      Platform.environment["PANGOLIN_SHARED_DIR"] ?? "/var/lib/pangolin/users";

  static String get currentUser {
    final String? name =
        Platform.environment["USER"] ?? Platform.environment["LOGNAME"];
    if (name != null && name.isNotEmpty) return name;
    return (Process.runSync("id", ["-un"]).stdout as String).trim();
  }

  static bool _validName(String user) =>
      user.isNotEmpty && !user.contains("/") && !user.startsWith(".");

  /// The file [user] published as [name], or null when there is none or it
  /// isn't a regular file owned by that user.
  static File? published(String user, String name) {
    if (!_validName(user)) return null;
    final String path = "$directory/$user.$name";
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final int? uid = _uidOf(user);
    if (uid == null) return null;
    try {
      final ProcessResult stat = Process.runSync("stat", ["-c", "%u", path]);
      if (stat.exitCode != 0) return null;
      if (int.tryParse((stat.stdout as String).trim()) != uid) return null;
    } on ProcessException {
      return null;
    }
    return File(path);
  }

  /// Publishes [bytes] as [name] for the current user. Written aside and
  /// renamed: the login screen never reads half a file. Completes with
  /// whether it was published (false where the directory doesn't exist,
  /// e.g. installs in a home directory).
  static Future<bool> publish(String name, List<int> bytes) async {
    final String user = currentUser;
    if (!_validName(user)) return false;
    if (!Directory(directory).existsSync()) return false;
    final File target = File("$directory/$user.$name");
    final File temp = File("$directory/.$user.$name.tmp");
    try {
      await temp.writeAsBytes(bytes, flush: true);
      // Readable by the login screen whatever the umask.
      await Process.run("chmod", ["644", temp.path]);
      await temp.rename(target.path);
      return true;
    } on Object {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } on FileSystemException {
        // Nothing left to clean up.
      }
      return false;
    }
  }

  static int? _uidOf(String user) {
    try {
      for (final String line in File("/etc/passwd").readAsLinesSync()) {
        final List<String> fields = line.split(":");
        if (fields.length > 2 && fields[0] == user) {
          return int.tryParse(fields[2]);
        }
      }
    } on FileSystemException {
      return null;
    }
    // Users from a directory service (LDAP, systemd-homed).
    try {
      final ProcessResult result = Process.runSync("id", ["-u", user]);
      if (result.exitCode == 0) {
        return int.tryParse((result.stdout as String).trim());
      }
    } on ProcessException {
      return null;
    }
    return null;
  }
}
