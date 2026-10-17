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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:dbus/dbus.dart';
import 'package:dsettings/dsettings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences shared with the shell through the dsettings daemon.
///
/// Pangolin owns the `pangolin` table (theme, accent color, wallpaper, ...).
/// Applications read and write the same table so that, for example, changing
/// the accent color in Settings immediately restyles the shell and every open
/// app. Unlike the shell's own implementation this one never claims the
/// `io.dahlia.Pangolin` bus name.
class AppPreferencesServiceFactory extends ServiceFactory<PreferencesService> {
  const AppPreferencesServiceFactory();

  @override
  PreferencesService build() => _SharedTablePreferencesService();

  @override
  PreferencesService fallback() => _LocalPreferencesService();
}

class _SharedTablePreferencesService extends PreferencesService {
  final DBusClient _client = DBusClient.session();
  late final DSettings _dsettings = DSettings(client: _client);
  late final DSettingsTable _table;
  final Map<String, Object> _values = {};

  final Map<String, Object> _pendingWrites = {};
  Timer? _flushTimer;

  @override
  Future<void> start() async {
    final DSettingsTable? table = await _dsettings
        .getTable("pangolin")
        .timeout(const Duration(seconds: 2));
    if (table == null) {
      throw StateError("The pangolin settings table does not exist yet");
    }
    _table = table;

    final Map<String, DSettingsEntry> all = await _table.readAll();
    all.forEach((key, entry) => _values[key] = entry.value as Object);

    _table.addSettingsWrittenListener((data) {
      data.forEach((key, entry) => _values[key] = entry.value as Object);
      notifyListeners();
    });
    _table.addSettingsDeletedListener((keys) {
      keys.forEach(_values.remove);
      notifyListeners();
    });
    _table.addSettingsClearedListener(() {
      _values.clear();
      notifyListeners();
    });
  }

  @override
  Future<void> stop() async {
    _flush();
    await _client.close();
  }

  @override
  T? get<T>(String key, [T? defaultValue]) {
    final List<T> probe = <T>[];
    if (probe is List<List<String>>) {
      return (_values[key] as List?)?.cast<String>() as T? ?? defaultValue;
    }
    return _values[key] as T? ?? defaultValue;
  }

  @override
  void set<T>(String key, T value) {
    _values[key] = value as Object;
    _pendingWrites[key] = value;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 100), _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    if (_pendingWrites.isEmpty) return;
    final Map<String, Object> batch = Map.of(_pendingWrites);
    _pendingWrites.clear();
    _table.writeBatch(batch);
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    await _table.delete(key);
  }

  // Applications never wipe the shell's settings.
  @override
  void clear() {}
}

/// Used when no dsettings daemon is running (e.g. apps started outside a
/// Pangolin session): settings are kept per application.
class _LocalPreferencesService extends PreferencesService {
  SharedPreferences? _prefs;

  @override
  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  void stop() {}

  @override
  T? get<T>(String key, [T? defaultValue]) {
    final Object? value = _prefs?.get(key);
    if (value is List) return value.cast<String>() as T?;
    return value as T? ?? defaultValue;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    switch (value) {
      case final int v:
        await prefs.setInt(key, v);
      case final double v:
        await prefs.setDouble(key, v);
      case final bool v:
        await prefs.setBool(key, v);
      case final String v:
        await prefs.setString(key, v);
      case final List<String> v:
        await prefs.setStringList(key, v);
    }
    notifyListeners();
  }

  @override
  Future<void> delete(String key) async => _prefs?.remove(key);

  @override
  void clear() {}
}
