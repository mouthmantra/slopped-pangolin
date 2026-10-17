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

import 'dart:math' as math;

import 'package:wayland/src/connection.dart';
import 'package:wayland/src/protocols/wayland.dart';
import 'package:wayland/src/proxy.dart';

/// A global advertised by the compositor through `wl_registry.global`.
class WaylandGlobal {
  const WaylandGlobal(this.name, this.interface, this.version);

  final int name;
  final String interface;
  final int version;

  @override
  String toString() => '$interface v$version (#$name)';
}

/// Keeps track of the globals advertised on a connection and binds them with
/// correct version negotiation.
class GlobalRegistry {
  GlobalRegistry._(this.connection, this.registry) {
    registry.onGlobal = (name, interface, version) {
      final WaylandGlobal global = WaylandGlobal(name, interface, version);
      _globals[name] = global;
      onAdded?.call(global);
    };
    registry.onGlobalRemove = (name) {
      final WaylandGlobal? global = _globals.remove(name);
      if (global != null) onRemoved?.call(global);
    };
  }

  /// Creates a registry and waits until the initial burst of globals has
  /// been received.
  static Future<GlobalRegistry> create(WaylandConnection connection) async {
    final GlobalRegistry registry =
        GlobalRegistry._(connection, connection.getRegistry());
    await connection.roundtrip();
    return registry;
  }

  final WaylandConnection connection;
  final WlRegistry registry;
  final Map<int, WaylandGlobal> _globals = {};

  void Function(WaylandGlobal global)? onAdded;
  void Function(WaylandGlobal global)? onRemoved;

  Iterable<WaylandGlobal> get globals => _globals.values;

  WaylandGlobal? operator [](int name) => _globals[name];

  Iterable<WaylandGlobal> all(String interface) =>
      _globals.values.where((g) => g.interface == interface);

  bool has(String interface) => all(interface).isNotEmpty;

  /// Binds the first global implementing [iface], negotiating the highest
  /// version both sides (and [maxVersion], if given) support.
  ///
  /// Returns null when the global is missing or too old for [minVersion].
  T? bind<T extends Proxy>(
    WaylandInterface<T> iface, {
    int minVersion = 1,
    int? maxVersion,
  }) {
    final WaylandGlobal? global = all(iface.name).firstOrNull;
    if (global == null) return null;
    return bindGlobal(global, iface, minVersion: minVersion, maxVersion: maxVersion);
  }

  /// Binds a specific [global], see [bind].
  T? bindGlobal<T extends Proxy>(
    WaylandGlobal global,
    WaylandInterface<T> iface, {
    int minVersion = 1,
    int? maxVersion,
  }) {
    final int version = math.min(
      math.min(global.version, iface.version),
      maxVersion ?? iface.version,
    );
    if (version < minVersion) return null;
    return registry.bind(global.name, iface, version);
  }
}
