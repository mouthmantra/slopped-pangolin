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

import 'package:path/path.dart' as p;
import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// Per-application JSON data (alarms, world clocks, recent files, ...),
/// stored in `$XDG_DATA_HOME/dahliaos/<app>.json`.
///
/// Settings shared with the shell go through [PreferencesService] instead.
class AppStorage {
  AppStorage._(this._file, this._data);

  static Future<AppStorage> open(String app) async {
    final File file = File(p.join(xdg.dataHome.path, "dahliaos", "$app.json"));
    Map<String, Object?> data = {};
    try {
      if (await file.exists()) {
        data = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
      }
    } on FormatException {
      // Corrupted file: start over rather than refusing to launch.
    }
    return AppStorage._(file, data);
  }

  final File _file;
  final Map<String, Object?> _data;
  Timer? _saveTimer;

  T? get<T>(String key) => _data[key] as T?;

  List<Map<String, Object?>> getList(String key) =>
      ((_data[key] as List?) ?? const [])
          .cast<Map>()
          .map((e) => e.cast<String, Object?>())
          .toList();

  void set(String key, Object? value) {
    _data[key] = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    await _file.parent.create(recursive: true);
    final File tmp = File("${_file.path}.tmp");
    await tmp.writeAsString(const JsonEncoder.withIndent("  ").convert(_data));
    await tmp.rename(_file.path);
  }
}
