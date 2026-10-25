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
import 'dart:io';

import 'package:display_config/src/shared.dart';

/// Identifies a monitor across sessions and ports: by make, model and
/// serial number when it reports them, by connector name otherwise.
String outputId({
  required String name,
  String make = "",
  String model = "",
  String serial = "",
}) {
  if (make.isNotEmpty || model.isNotEmpty || serial.isNotEmpty) {
    return "$make|$model|$serial";
  }
  return "connector:$name";
}

/// How one monitor is set up.
class OutputSettings {
  const OutputSettings({
    required this.id,
    required this.enabled,
    this.width = 0,
    this.height = 0,
    this.refresh = 0,
    this.scale = 1,
    this.transform = 0,
    this.x = 0,
    this.y = 0,
    this.adaptiveSync,
  });

  factory OutputSettings.fromJson(Map<String, Object?> json) => OutputSettings(
        id: json["id"]! as String,
        enabled: json["enabled"] as bool? ?? true,
        width: (json["width"] as num?)?.toInt() ?? 0,
        height: (json["height"] as num?)?.toInt() ?? 0,
        refresh: (json["refresh"] as num?)?.toInt() ?? 0,
        scale: (json["scale"] as num?)?.toDouble() ?? 1,
        transform: (json["transform"] as num?)?.toInt() ?? 0,
        x: (json["x"] as num?)?.toInt() ?? 0,
        y: (json["y"] as num?)?.toInt() ?? 0,
        adaptiveSync: json["adaptiveSync"] as bool?,
      );

  final String id;
  final bool enabled;

  /// Mode in pixels and mHz; 0 keeps the monitor's preferred mode.
  final int width;
  final int height;
  final int refresh;
  final double scale;

  /// wl_output.transform.
  final int transform;
  final int x;
  final int y;
  final bool? adaptiveSync;

  /// The same settings at [x], [y].
  OutputSettings movedTo(int x, int y) => OutputSettings(
        id: id,
        enabled: enabled,
        width: width,
        height: height,
        refresh: refresh,
        scale: scale,
        transform: transform,
        x: x,
        y: y,
        adaptiveSync: adaptiveSync,
      );

  Map<String, Object?> toJson() => {
        "id": id,
        "enabled": enabled,
        "width": width,
        "height": height,
        "refresh": refresh,
        "scale": scale,
        "transform": transform,
        "x": x,
        "y": y,
        if (adaptiveSync != null) "adaptiveSync": adaptiveSync,
      };
}

/// The saved configurations, one per set of monitors, in
/// `$XDG_CONFIG_HOME/pangolin/displays.json`.
abstract final class DisplayProfiles {
  static File get file {
    final Map<String, String> env = Platform.environment;
    final String config = env["XDG_CONFIG_HOME"]?.isNotEmpty == true
        ? env["XDG_CONFIG_HOME"]!
        : "${env["HOME"] ?? "."}/.config";
    return File("$config/pangolin/displays.json");
  }

  /// Every saved configuration; empty when there is none or the file can't
  /// be read.
  static List<List<OutputSettings>> load() => loadFile(file);

  /// The configurations in [f] (the format [save] writes).
  static List<List<OutputSettings>> loadFile(File f) {
    try {
      if (!f.existsSync()) return const [];
      final Object? json = jsonDecode(f.readAsStringSync());
      if (json is! Map || json["profiles"] is! List) return const [];
      return [
        for (final Object? profile in json["profiles"] as List)
          if (profile is Map && profile["outputs"] is List)
            [
              for (final Object? output in profile["outputs"] as List)
                if (output is Map<String, Object?> && output["id"] is String)
                  OutputSettings.fromJson(output),
            ],
      ];
    } on Object {
      return const [];
    }
  }

  /// The configuration saved for exactly these monitors.
  static List<OutputSettings>? match(Set<String> ids) =>
      matchIn(load(), ids);

  /// The configuration of [profiles] for exactly these monitors.
  static List<OutputSettings>? matchIn(
    List<List<OutputSettings>> profiles,
    Set<String> ids,
  ) {
    for (final List<OutputSettings> profile in profiles) {
      final Set<String> saved = {for (final OutputSettings o in profile) o.id};
      if (saved.length == ids.length && saved.containsAll(ids)) return profile;
    }
    return null;
  }

  /// Saves [outputs], replacing what was saved for the same monitors.
  static void save(List<OutputSettings> outputs) {
    final Set<String> ids = {for (final OutputSettings o in outputs) o.id};
    final List<List<OutputSettings>> profiles = [
      for (final List<OutputSettings> profile in load())
        if (!_sameIds(profile, ids)) profile,
      outputs,
    ];
    final File f = file;
    f.parent.createSync(recursive: true);
    // Written aside and renamed: a crash never leaves half a file.
    final File temp = File("${f.path}.tmp");
    temp.writeAsStringSync(_encode(profiles), flush: true);
    temp.renameSync(f.path);
  }

  static String _encode(List<List<OutputSettings>> profiles) =>
      const JsonEncoder.withIndent("  ").convert({
        "version": 1,
        "profiles": [
          for (final List<OutputSettings> profile in profiles)
            {"outputs": [for (final OutputSettings o in profile) o.toJson()]},
        ],
      });

  /// Name of the configurations a user shares with the login screen
  /// ([SharedUserFiles]).
  static const String sharedName = "displays.json";

  /// Shares how the monitors are set up right now with the login screen
  /// (replacing what was shared for the same monitors), so that it looks
  /// like the desktop. Completes with whether something changed.
  static Future<bool> publish(List<OutputSettings> current) async {
    if (current.isEmpty) return false;
    final Set<String> ids = {for (final OutputSettings o in current) o.id};
    final File? previous =
        SharedUserFiles.published(SharedUserFiles.currentUser, sharedName);
    final List<List<OutputSettings>> old =
        previous == null ? const [] : loadFile(previous);
    final List<List<OutputSettings>> profiles = [
      current,
      for (final List<OutputSettings> profile in old)
        if (!_sameIds(profile, ids)) profile,
    ];
    final String json = _encode(profiles);
    if (previous != null && previous.readAsStringSync() == json) return false;
    return SharedUserFiles.publish(sharedName, utf8.encode(json));
  }

  /// The configuration [user] shared for exactly these monitors.
  static List<OutputSettings>? sharedBy(String user, Set<String> ids) {
    final File? f = SharedUserFiles.published(user, sharedName);
    return f == null ? null : matchIn(loadFile(f), ids);
  }

  /// Users who shared a configuration, the most recent first.
  static List<String> sharingUsers() {
    final List<(String, DateTime)> users = [];
    try {
      for (final FileSystemEntity e
          in Directory(SharedUserFiles.directory).listSync()) {
        final String name = e.uri.pathSegments.last;
        if (name.startsWith(".") || !name.endsWith(".$sharedName")) continue;
        users.add((
          name.substring(0, name.length - sharedName.length - 1),
          e.statSync().modified,
        ));
      }
    } on FileSystemException {
      return const [];
    }
    users.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final (String user, _) in users) user];
  }

  static bool _sameIds(List<OutputSettings> profile, Set<String> ids) {
    final Set<String> saved = {for (final OutputSettings o in profile) o.id};
    return saved.length == ids.length && saved.containsAll(ids);
  }
}
