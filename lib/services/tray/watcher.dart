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

import 'package:dbus/dbus.dart';

const String watcherInterface = "org.kde.StatusNotifierWatcher";
final DBusObjectPath watcherPath = DBusObjectPath("/StatusNotifierWatcher");

/// Where an item lives: what RegisterStatusNotifierItem was given, or an
/// entry of RegisteredStatusNotifierItems.
typedef ItemAddress = ({String service, DBusObjectPath path});

/// Reads an item registration. libappindicator registers its object path
/// (the item belongs to [sender]), KDE and Qt a bus name (the item is at
/// /StatusNotifierItem), and watchers list items as "service/path". Null
/// when [value] is none of these.
ItemAddress? parseItemAddress(String value, {String? sender}) {
  String service;
  String path;
  if (value.startsWith("/")) {
    if (sender == null || sender.isEmpty) return null;
    service = sender;
    path = value;
  } else {
    final int slash = value.indexOf("/");
    if (slash < 0) {
      service = value;
      path = "/StatusNotifierItem";
    } else {
      service = value.substring(0, slash);
      path = value.substring(slash);
    }
  }
  if (!_validBusName(service)) return null;
  try {
    return (service: service, path: DBusObjectPath(path));
  } catch (_) {
    return null;
  }
}

final RegExp _uniqueName = RegExp(r"^:[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$");
final RegExp _wellKnownName =
    RegExp(r"^[A-Za-z_-][A-Za-z0-9_-]*(\.[A-Za-z_-][A-Za-z0-9_-]*)+$");

bool _validBusName(String name) {
  if (name.isEmpty || name.length > 255) return false;
  return _uniqueName.hasMatch(name) || _wellKnownName.hasMatch(name);
}

/// Pangolin's org.kde.StatusNotifierWatcher, exported while no other
/// watcher runs. It only keeps the registrations: [onRegisterItem] checks
/// them and hands them to the tray.
class StatusNotifierWatcherObject extends DBusObject {
  /// Checks and records a registration; returns the error to answer with,
  /// or null.
  final Future<DBusMethodResponse?> Function(String sender, String value)
      onRegisterItem;

  StatusNotifierWatcherObject({required this.onRegisterItem})
      : super(watcherPath);

  /// Registered items by "service/path", with the unique name of their
  /// owner.
  final Map<String, ({ItemAddress address, String owner})> _items = {};

  /// Hosts other than Pangolin itself (which always is one).
  final Set<String> _hosts = {};

  List<String> get registeredItems => _items.keys.toList();

  /// Whether the item of [owner] at [path] is registered already, under
  /// any name (an app may register its unique and its well-known name).
  bool hasItemAt(String owner, DBusObjectPath path) => _items.values.any(
        (e) => e.owner == owner && e.address.path == path,
      );

  void addItem(ItemAddress address, String owner) {
    final String registration = "${address.service}${address.path.value}";
    if (_items.containsKey(registration)) return;
    _items[registration] = (address: address, owner: owner);
    unawaited(_emit("StatusNotifierItemRegistered", registration));
    unawaited(_itemsChanged());
  }

  void removeItem(String registration) {
    if (_items.remove(registration) == null) return;
    unawaited(_emit("StatusNotifierItemUnregistered", registration));
    unawaited(_itemsChanged());
  }

  /// Removes the registrations of the item of [owner] at [path].
  void removeItemAt(String owner, DBusObjectPath path) {
    final List<String> gone = [
      for (final MapEntry(:key, :value) in _items.entries)
        if (value.owner == owner && value.address.path == path) key,
    ];
    gone.forEach(removeItem);
  }

  /// [name] left the bus: its items and its host go.
  void nameVanished(String name) {
    final List<String> gone = [
      for (final MapEntry(:key, :value) in _items.entries)
        if (value.owner == name || value.address.service == name) key,
    ];
    gone.forEach(removeItem);
    _hosts.remove(name);
  }

  Future<void> _emit(String signal, String value) async {
    try {
      await emitSignal(watcherInterface, signal, [DBusString(value)]);
    } catch (_) {
      // Closing down.
    }
  }

  Future<void> _itemsChanged() async {
    try {
      await emitPropertiesChanged(
        watcherInterface,
        changedProperties: {
          "RegisteredStatusNotifierItems": DBusArray.string(registeredItems),
        },
      );
    } catch (_) {}
  }

  Future<void> emitHostRegistered() async {
    try {
      await emitSignal(watcherInterface, "StatusNotifierHostRegistered");
    } catch (_) {}
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != watcherInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.signature != DBusSignature.string) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final String value = methodCall.values[0].asString();
    switch (methodCall.name) {
      case "RegisterStatusNotifierItem":
        final DBusMethodResponse? error =
            await onRegisterItem(methodCall.sender ?? "", value);
        return error ?? DBusMethodSuccessResponse();
      case "RegisterStatusNotifierHost":
        // Hosts register the bus name they own; track it, or the sender.
        final String host = value.isNotEmpty && _validBusName(value)
            ? value
            : methodCall.sender ?? "";
        if (host.isNotEmpty && _hosts.add(host)) {
          unawaited(emitHostRegistered());
        }
        return DBusMethodSuccessResponse();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }

  DBusValue? _property(String name) => switch (name) {
        "RegisteredStatusNotifierItems" => DBusArray.string(registeredItems),
        // Pangolin is a host as long as it is the watcher.
        "IsStatusNotifierHostRegistered" => const DBusBoolean(true),
        "ProtocolVersion" => const DBusInt32(0),
        _ => null,
      };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final DBusValue? value =
        interface == watcherInterface ? _property(name) : null;
    if (value == null) return DBusMethodErrorResponse.unknownProperty();
    return DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> setProperty(
    String interface,
    String name,
    DBusValue value,
  ) async {
    if (interface == watcherInterface && _property(name) != null) {
      return DBusMethodErrorResponse.propertyReadOnly();
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    final Map<String, DBusValue> properties = {};
    if (interface == watcherInterface) {
      for (final String name in const [
        "RegisteredStatusNotifierItems",
        "IsStatusNotifierHostRegistered",
        "ProtocolVersion",
      ]) {
        properties[name] = _property(name)!;
      }
    }
    return DBusGetAllPropertiesResponse(properties);
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectArgument arg(String name) => DBusIntrospectArgument(
          DBusSignature.string,
          DBusArgumentDirection.in_,
          name: name,
        );
    DBusIntrospectArgument out() =>
        DBusIntrospectArgument(DBusSignature.string, DBusArgumentDirection.out);
    return [
      DBusIntrospectInterface(
        watcherInterface,
        methods: [
          DBusIntrospectMethod("RegisterStatusNotifierItem", args: [arg("service")]),
          DBusIntrospectMethod("RegisterStatusNotifierHost", args: [arg("service")]),
        ],
        signals: [
          DBusIntrospectSignal("StatusNotifierItemRegistered", args: [out()]),
          DBusIntrospectSignal("StatusNotifierItemUnregistered", args: [out()]),
          DBusIntrospectSignal("StatusNotifierHostRegistered"),
          DBusIntrospectSignal("StatusNotifierHostUnregistered"),
        ],
        properties: [
          DBusIntrospectProperty(
            "RegisteredStatusNotifierItems",
            DBusSignature("as"),
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            "IsStatusNotifierHostRegistered",
            DBusSignature.boolean,
            access: DBusPropertyAccess.read,
          ),
          DBusIntrospectProperty(
            "ProtocolVersion",
            DBusSignature.int32,
            access: DBusPropertyAccess.read,
          ),
        ],
      ),
    ];
  }
}
