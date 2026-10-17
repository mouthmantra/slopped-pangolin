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
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/dbus/utils.dart';

/// A VPN connection saved in NetworkManager (any VPN plugin, or WireGuard).
class VpnConnection {
  const VpnConnection({
    required this.path,
    required this.uuid,
    required this.name,
    required this.kind,
    required this.lastUsed,
  });

  final DBusObjectPath path;
  final String uuid;
  final String name;

  /// "WireGuard", "OpenVPN", "IPsec"... for display.
  final String kind;

  /// Seconds since the epoch, 0 when never used.
  final int lastUsed;
}

enum VpnState { off, connecting, on, disconnecting }

/// VPNs through NetworkManager: the saved connections, which are on, and
/// turning them on and off. Also NetworkManager's secret agent for this
/// session: it hands NetworkManager the passwords VPNs (and Wi-Fi networks)
/// need, from the keyring when they were saved there (as GNOME does) or
/// asked for with [VpnService.secretRequest].
class VpnService extends ChangeNotifier {
  VpnService._();

  static final VpnService instance = VpnService._();
  static final Logger _logger = Logger("VpnService");

  static const String _nm = "org.freedesktop.NetworkManager";
  static const String _settingsInterface = "$_nm.Settings";
  static const String _connectionInterface = "$_nm.Settings.Connection";
  static const String _activeInterface = "$_nm.Connection.Active";
  static const String _agentPath = "/org/freedesktop/NetworkManager/SecretAgent";
  static const String _agentInterface = "$_nm.SecretAgent";

  DBusClient? _bus;
  bool _started = false;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Whether NetworkManager could be reached.
  bool available = false;
  List<VpnConnection> connections = const [];

  /// State of the connections that are on (or getting there), by uuid.
  Map<String, VpnState> states = const {};
  final Map<String, DBusObjectPath> _active = {};

  /// Why the last connection attempt failed, for the Quick Settings page.
  String? error;

  /// A password being asked for (one at a time), shown by the network
  /// password dialog.
  final ValueNotifier<NetworkSecretRequest?> secretRequest =
      ValueNotifier(null);
  final List<NetworkSecretRequest> _secretQueue = [];
  String? _nmOwner;

  bool get anyActive => states.values.any((s) => s == VpnState.on);
  bool get anyBusy => states.values
      .any((s) => s == VpnState.connecting || s == VpnState.disconnecting);

  VpnState stateOf(VpnConnection c) => states[c.uuid] ?? VpnState.off;

  /// The VPN that's on, or being turned on.
  VpnConnection? get current {
    for (final VpnConnection c in connections) {
      final VpnState s = stateOf(c);
      if (s == VpnState.on || s == VpnState.connecting) return c;
    }
    return null;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (!systemBusAvailable()) return;
    final DBusClient bus = DBusClient.system();
    _bus = bus;
    try {
      _nmOwner = await bus.getNameOwner(_nm);
      if (_nmOwner == null) {
        await bus.close();
        _bus = null;
        return;
      }
      final DBusRemoteObject manager = DBusRemoteObject(
        bus,
        name: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager"),
      );
      _subscriptions
        ..add(manager.propertiesChanged.listen((_) => _refresh()))
        ..add(
          DBusSignalStream(bus, sender: _nm, interface: _settingsInterface)
              .listen((_) => _refresh()),
        )
        ..add(
          DBusSignalStream(
            bus,
            sender: _nm,
            interface: _activeInterface,
            name: "StateChanged",
          ).listen((_) => _refresh()),
        )
        ..add(
          DBusSignalStream(
            bus,
            sender: _nm,
            interface: _connectionInterface,
            name: "Updated",
          ).listen((_) => _refresh()),
        );
      await _refresh();
      await _registerAgent(bus);
    } on Object catch (e) {
      _logger.info("NetworkManager isn't available: $e");
    }
  }

  bool _refreshing = false;
  bool _refreshAgain = false;

  Future<void> _refresh() async {
    final DBusClient? bus = _bus;
    if (bus == null) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _read(bus);
      } while (_refreshAgain);
    } on Object catch (e) {
      _logger.fine("Couldn't read the VPN connections: $e");
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _read(DBusClient bus) async {
    final DBusRemoteObject settings = DBusRemoteObject(
      bus,
      name: _nm,
      path: DBusObjectPath("/org/freedesktop/NetworkManager/Settings"),
    );
    final List<DBusObjectPath> paths = (await settings.callMethod(
      _settingsInterface,
      "ListConnections",
      [],
      replySignature: DBusSignature("ao"),
    ))
        .returnValues
        .first
        .asObjectPathArray()
        .toList();
    final List<VpnConnection> found = [];
    for (final DBusObjectPath path in paths) {
      try {
        final Map<String, Map<String, DBusValue>> s =
            await _settingsOf(bus, path);
        final Map<String, DBusValue>? connection = s["connection"];
        if (connection == null) continue;
        final String type = connection["type"]?.asString() ?? "";
        if (type != "vpn" && type != "wireguard") continue;
        found.add(
          VpnConnection(
            path: path,
            uuid: connection["uuid"]?.asString() ?? path.value,
            name: connection["id"]?.asString() ?? "VPN",
            kind: type == "wireguard"
                ? "WireGuard"
                : _vpnKind(s["vpn"]?["service-type"]?.asString() ?? ""),
            lastUsed: connection["timestamp"]?.asUint64() ?? 0,
          ),
        );
      } on Object {
        // Removed meanwhile, or not readable by this user.
      }
    }
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final DBusRemoteObject manager = DBusRemoteObject(
      bus,
      name: _nm,
      path: DBusObjectPath("/org/freedesktop/NetworkManager"),
    );
    final List<DBusObjectPath> active =
        (await manager.getProperty(_nm, "ActiveConnections"))
            .asObjectPathArray()
            .toList();
    final Map<String, VpnState> newStates = {};
    _active.clear();
    for (final DBusObjectPath path in active) {
      try {
        final DBusRemoteObject object =
            DBusRemoteObject(bus, name: _nm, path: path);
        final String type =
            (await object.getProperty(_activeInterface, "Type")).asString();
        if (type != "vpn" && type != "wireguard") continue;
        final String uuid =
            (await object.getProperty(_activeInterface, "Uuid")).asString();
        final int state =
            (await object.getProperty(_activeInterface, "State")).asUint32();
        final VpnState? s = switch (state) {
          1 => VpnState.connecting,
          2 => VpnState.on,
          3 => VpnState.disconnecting,
          _ => null,
        };
        if (s == null) continue;
        newStates[uuid] = s;
        _active[uuid] = path;
      } on Object {
        // Gone meanwhile.
      }
    }

    available = true;
    connections = found;
    if (!mapEquals(newStates, states)) {
      if (newStates.values.contains(VpnState.on)) error = null;
      states = newStates;
    }
    notifyListeners();
  }

  static Future<Map<String, Map<String, DBusValue>>> _settingsOf(
    DBusClient bus,
    DBusObjectPath path,
  ) async {
    final DBusValue value = (await DBusRemoteObject(
      bus,
      name: _nm,
      path: path,
    ).callMethod(
      _connectionInterface,
      "GetSettings",
      [],
      replySignature: DBusSignature("a{sa{sv}}"),
    ))
        .returnValues
        .first;
    return _settingsMap(value);
  }

  static Map<String, Map<String, DBusValue>> _settingsMap(DBusValue value) => {
        for (final MapEntry<DBusValue, DBusValue> e in value.asDict().entries)
          e.key.asString(): e.value.asStringVariantDict(),
      };

  static String _vpnKind(String serviceType) {
    final String plugin = serviceType.split(".").last.toLowerCase();
    return switch (plugin) {
      "openvpn" => "OpenVPN",
      "openconnect" => "OpenConnect",
      "vpnc" => "Cisco (vpnc)",
      "l2tp" => "L2TP",
      "pptp" => "PPTP",
      "strongswan" || "libreswan" => "IPsec",
      "fortisslvpn" => "Fortinet",
      "sstp" => "SSTP",
      _ => "VPN",
    };
  }

  /// Turns [connection] on, or off when it's on.
  Future<void> toggle(VpnConnection connection) async {
    final VpnState state = stateOf(connection);
    if (state == VpnState.on || state == VpnState.connecting) {
      await disconnect(connection);
    } else {
      await connect(connection);
    }
  }

  /// The VPN used last, for the Quick Settings tile.
  VpnConnection? get preferred {
    if (connections.isEmpty) return null;
    return connections.reduce((a, b) => b.lastUsed > a.lastUsed ? b : a);
  }

  Future<void> connect(VpnConnection connection) async {
    final DBusClient? bus = _bus;
    if (bus == null) return;
    error = null;
    states = {...states, connection.uuid: VpnState.connecting};
    notifyListeners();
    try {
      await bus.callMethod(
        destination: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager"),
        interface: _nm,
        name: "ActivateConnection",
        values: [
          connection.path,
          DBusObjectPath("/"),
          DBusObjectPath("/"),
        ],
        replySignature: DBusSignature("o"),
      );
    } on DBusMethodResponseException catch (e) {
      error = _describe(
        e.errorName,
        e.response.values.firstOrNull is DBusString
            ? e.response.values.first.asString()
            : null,
      );
      states = {...states}..remove(connection.uuid);
      notifyListeners();
    } on Object catch (e) {
      error = "Couldn't connect: $e";
      states = {...states}..remove(connection.uuid);
      notifyListeners();
    }
    await _refresh();
  }

  Future<void> disconnect(VpnConnection connection) async {
    final DBusClient? bus = _bus;
    final DBusObjectPath? active = _active[connection.uuid];
    if (bus == null || active == null) return;
    try {
      await bus.callMethod(
        destination: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager"),
        interface: _nm,
        name: "DeactivateConnection",
        values: [active],
        replySignature: DBusSignature(""),
      );
    } on Object catch (e) {
      _logger.info("Couldn't disconnect ${connection.name}: $e");
    }
    await _refresh();
  }

  static String _describe(String name, String? message) {
    if (name.endsWith("NoSecrets") || name.endsWith("UserCanceled")) {
      return "No password was given";
    }
    if (name.endsWith("PermissionDenied") || name.endsWith("NotAuthorized")) {
      return "Not allowed to change network connections";
    }
    return message?.isNotEmpty == true ? message! : "Couldn't connect";
  }

  /// A program that edits NetworkManager connections, if one is installed.
  static String? get editor {
    for (final String dir in (Platform.environment["PATH"] ?? "/usr/bin")
        .split(":")) {
      if (File("$dir/nm-connection-editor").existsSync()) {
        return "$dir/nm-connection-editor";
      }
    }
    return null;
  }

  // Secret agent.

  Future<void> _registerAgent(DBusClient bus) async {
    try {
      await bus.registerObject(_SecretAgentObject(this));
      await bus.callMethod(
        destination: _nm,
        path: DBusObjectPath("/org/freedesktop/NetworkManager/AgentManager"),
        interface: "$_nm.AgentManager",
        name: "RegisterWithCapabilities",
        values: const [
          DBusString("io.dahliaos.pangolin"),
          // NM_SECRET_AGENT_CAPABILITY_VPN_HINTS
          DBusUint32(1),
        ],
        replySignature: DBusSignature(""),
      );
      _logger.info("Registered as NetworkManager's secret agent");
    } on Object catch (e) {
      // Another desktop's agent (Pangolin nested in it), or no permission.
      _logger.info("Not NetworkManager's secret agent: $e");
    }
  }

  bool _fromNetworkManager(DBusMethodCall call) =>
      _nmOwner != null && call.sender == _nmOwner;

  Future<DBusMethodResponse> _getSecrets(DBusMethodCall call) async {
    final Map<String, Map<String, DBusValue>> connection =
        _settingsMap(call.values[0]);
    final String settingName = call.values[2].asString();
    final List<String> hints = call.values[3].asStringArray().toList();
    final int flags = call.values[4].asUint32();
    final String uuid = connection["connection"]?["uuid"]?.asString() ?? "";
    final String name = connection["connection"]?["id"]?.asString() ?? "";

    final List<String> keys = _secretKeys(connection, settingName, hints);
    if (keys.isEmpty) return _noSecrets();
    final bool requestNew = flags & 0x2 != 0;
    final bool mayAsk = flags & 0x1 != 0;

    // Saved in the keyring (by GNOME, or by this agent)?
    if (!requestNew) {
      final Map<String, String> saved =
          await _Keyring.lookup(uuid, settingName, keys);
      if (saved.length == keys.length) {
        return DBusMethodSuccessResponse([_secretsValue(settingName, saved)]);
      }
    }
    if (!mayAsk) return _noSecrets();

    final String? message = hints
        .where((h) => h.startsWith("x-vpn-message:"))
        .map((h) => h.substring("x-vpn-message:".length))
        .firstOrNull;
    final NetworkSecretRequest request = NetworkSecretRequest._(
      connectionPath: call.values[1].asObjectPath(),
      settingName: settingName,
      name: name,
      isVpn: settingName == "vpn" || settingName == "wireguard",
      keys: keys,
      message: message,
      retry: requestNew,
    );
    _enqueue(request);
    final Map<String, String>? answers = await request._answer.future;
    _dequeue(request);
    if (answers == null) {
      return DBusMethodErrorResponse("$_agentInterface.UserCanceled");
    }
    if (request.remember) {
      unawaited(_Keyring.store(uuid, name, settingName, answers));
    }
    return DBusMethodSuccessResponse([_secretsValue(settingName, answers)]);
  }

  static DBusMethodResponse _noSecrets() =>
      DBusMethodErrorResponse("$_agentInterface.NoSecrets");

  /// Which secrets [settingName] needs: the ones NetworkManager hints at, or
  /// the VPN plugin's secrets that may be asked for (their "-flags" entry
  /// isn't "not required"), or the Wi-Fi password.
  static List<String> _secretKeys(
    Map<String, Map<String, DBusValue>> connection,
    String settingName,
    List<String> hints,
  ) {
    final List<String> hinted = [
      for (final String h in hints)
        if (!h.startsWith("x-vpn-message:") && h.isNotEmpty) h,
    ];
    if (hinted.isNotEmpty) return hinted;
    switch (settingName) {
      case "vpn":
        final Map<String, String> data = {
          for (final MapEntry<DBusValue, DBusValue> e
              in connection["vpn"]?["data"]?.asDict().entries ?? const [])
            e.key.asString(): e.value.asString(),
        };
        return [
          for (final MapEntry<String, String> e in data.entries)
            if (e.key.endsWith("-flags") &&
                (int.tryParse(e.value) ?? 0) & 0x4 == 0)
              e.key.substring(0, e.key.length - "-flags".length),
        ];
      case "802-11-wireless-security":
        final String keyMgmt =
            connection[settingName]?["key-mgmt"]?.asString() ?? "";
        if (keyMgmt == "none") return const ["wep-key0"];
        return const ["psk"];
      default:
        return const [];
    }
  }

  static DBusValue _secretsValue(String settingName, Map<String, String> s) {
    final Map<String, DBusValue> setting = settingName == "vpn"
        ? {
            "secrets": DBusDict(
              DBusSignature("s"),
              DBusSignature("s"),
              {
                for (final MapEntry<String, String> e in s.entries)
                  DBusString(e.key): DBusString(e.value),
              },
            ),
          }
        : {
            for (final MapEntry<String, String> e in s.entries)
              e.key: DBusString(e.value),
          };
    return DBusDict(
      DBusSignature("s"),
      DBusSignature("a{sv}"),
      {DBusString(settingName): DBusDict.stringVariant(setting)},
    );
  }

  void _enqueue(NetworkSecretRequest request) {
    _secretQueue.add(request);
    secretRequest.value ??= request;
  }

  void _dequeue(NetworkSecretRequest request) {
    _secretQueue.remove(request);
    if (secretRequest.value == request) {
      secretRequest.value = _secretQueue.firstOrNull;
    }
  }

  DBusMethodResponse _cancelGetSecrets(DBusMethodCall call) {
    final DBusObjectPath path = call.values[0].asObjectPath();
    final String setting = call.values[1].asString();
    for (final NetworkSecretRequest r in [..._secretQueue]) {
      if (r.connectionPath == path && r.settingName == setting) r.cancel();
    }
    return DBusMethodSuccessResponse();
  }

  Future<DBusMethodResponse> _saveSecrets(DBusMethodCall call) async {
    final Map<String, Map<String, DBusValue>> connection =
        _settingsMap(call.values[0]);
    final String uuid = connection["connection"]?["uuid"]?.asString() ?? "";
    final String name = connection["connection"]?["id"]?.asString() ?? "";
    final Map<String, DBusValue>? vpn = connection["vpn"];
    if (vpn?["secrets"] != null) {
      await _Keyring.store(uuid, name, "vpn", {
        for (final MapEntry<DBusValue, DBusValue> e
            in vpn!["secrets"]!.asDict().entries)
          e.key.asString(): e.value.asString(),
      });
    }
    final DBusValue? psk = connection["802-11-wireless-security"]?["psk"];
    if (psk != null) {
      await _Keyring.store(
        uuid,
        name,
        "802-11-wireless-security",
        {"psk": psk.asString()},
      );
    }
    return DBusMethodSuccessResponse();
  }

  Future<DBusMethodResponse> _deleteSecrets(DBusMethodCall call) async {
    final Map<String, Map<String, DBusValue>> connection =
        _settingsMap(call.values[0]);
    final String uuid = connection["connection"]?["uuid"]?.asString() ?? "";
    if (uuid.isNotEmpty) await _Keyring.delete(uuid);
    return DBusMethodSuccessResponse();
  }
}

/// A password NetworkManager needs to connect.
class NetworkSecretRequest {
  NetworkSecretRequest._({
    required this.connectionPath,
    required this.settingName,
    required this.name,
    required this.isVpn,
    required this.keys,
    required this.message,
    required this.retry,
  });

  final DBusObjectPath connectionPath;
  final String settingName;

  /// The connection's name.
  final String name;
  final bool isVpn;

  /// The secrets to ask for ("password", "psk"...).
  final List<String> keys;

  /// What the VPN plugin says about it, if anything.
  final String? message;

  /// The previous answer was wrong.
  final bool retry;

  /// Save the answers in the keyring.
  bool remember = true;

  final Completer<Map<String, String>?> _answer = Completer();

  bool get done => _answer.isCompleted;

  void respond(Map<String, String> answers) {
    if (!_answer.isCompleted) _answer.complete(answers);
  }

  void cancel() {
    if (!_answer.isCompleted) _answer.complete(null);
  }

  /// A label for [key].
  static String label(String key) => switch (key) {
        "password" || "Xauth password" => "Password",
        "psk" || "wep-key0" => "Password",
        "cert-pass" => "Key passphrase",
        "IPSec secret" || "ipsec-psk" => "Group password",
        "private-key" => "Private key",
        _ => key[0].toUpperCase() + key.substring(1).replaceAll("-", " "),
      };
}

class _SecretAgentObject extends DBusObject {
  _SecretAgentObject(this._service)
      : super(DBusObjectPath(VpnService._agentPath));

  final VpnService _service;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != VpnService._agentInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    // Only NetworkManager may ask (anyone else could fake a dialog).
    if (!_service._fromNetworkManager(call)) {
      return DBusMethodErrorResponse.accessDenied();
    }
    switch (call.name) {
      case "GetSecrets":
        if (call.signature != DBusSignature("a{sa{sv}}osasu")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return _service._getSecrets(call);
      case "CancelGetSecrets":
        if (call.signature != DBusSignature("os")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return _service._cancelGetSecrets(call);
      case "SaveSecrets":
        if (call.signature != DBusSignature("a{sa{sv}}o")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return _service._saveSecrets(call);
      case "DeleteSecrets":
        if (call.signature != DBusSignature("a{sa{sv}}o")) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        return _service._deleteSecrets(call);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
  }
}

/// Network secrets in the user's keyring (the Secret Service: GNOME
/// Keyring, KWallet...), where NetworkManager's agents keep them: the
/// passwords a user saved in GNOME work here too.
abstract final class _Keyring {
  static const String _service = "org.freedesktop.secrets";
  static const String _path = "/org/freedesktop/secrets";
  static const String _schema = "org.freedesktop.NetworkManager.Connection";

  static Future<T?> _withSession<T>(
    Future<T> Function(DBusClient bus, DBusObjectPath session) body,
  ) async {
    final DBusClient bus = DBusClient.session();
    try {
      final DBusMethodSuccessResponse reply = await bus.callMethod(
        destination: _service,
        path: DBusObjectPath(_path),
        interface: "org.freedesktop.Secret.Service",
        name: "OpenSession",
        values: [const DBusString("plain"), const DBusVariant(DBusString(""))],
        replySignature: DBusSignature("vo"),
      );
      return await body(bus, reply.returnValues[1].asObjectPath());
    } on Object {
      return null;
    } finally {
      await bus.close();
    }
  }

  static Future<Map<String, String>> lookup(
    String uuid,
    String setting,
    List<String> keys,
  ) async {
    if (uuid.isEmpty) return const {};
    return await _withSession((bus, session) async {
          final Map<String, String> found = {};
          for (final String key in keys) {
            final DBusMethodSuccessResponse search = await bus.callMethod(
              destination: _service,
              path: DBusObjectPath(_path),
              interface: "org.freedesktop.Secret.Service",
              name: "SearchItems",
              values: [
                DBusDict(
                  DBusSignature("s"),
                  DBusSignature("s"),
                  {
                    const DBusString("connection-uuid"): DBusString(uuid),
                    const DBusString("setting-name"): DBusString(setting),
                    const DBusString("setting-key"): DBusString(key),
                  },
                ),
              ],
              replySignature: DBusSignature("aoao"),
            );
            // Locked items would need the keyring's own unlock prompt:
            // asked for here instead.
            final List<DBusObjectPath> items =
                search.returnValues[0].asObjectPathArray().toList();
            if (items.isEmpty) continue;
            final DBusMethodSuccessResponse secrets = await bus.callMethod(
              destination: _service,
              path: DBusObjectPath(_path),
              interface: "org.freedesktop.Secret.Service",
              name: "GetSecrets",
              values: [DBusArray.objectPath([items.first]), session],
              replySignature: DBusSignature("a{o(oayays)}"),
            );
            final Map<DBusValue, DBusValue> map =
                secrets.returnValues.first.asDict();
            if (map.isEmpty) continue;
            final List<DBusValue> secret = map.values.first.asStruct();
            found[key] = utf8.decode(secret[2].asByteArray().toList());
          }
          return found;
        }) ??
        const {};
  }

  static Future<void> store(
    String uuid,
    String name,
    String setting,
    Map<String, String> secrets,
  ) async {
    if (uuid.isEmpty) return;
    await _withSession((bus, session) async {
      for (final MapEntry<String, String> e in secrets.entries) {
        await bus.callMethod(
          destination: _service,
          path: DBusObjectPath("$_path/aliases/default"),
          interface: "org.freedesktop.Secret.Collection",
          name: "CreateItem",
          values: [
            DBusDict.stringVariant({
              "org.freedesktop.Secret.Item.Label":
                  DBusString("Network secret for $name/$setting/${e.key}"),
              "org.freedesktop.Secret.Item.Attributes": DBusDict(
                DBusSignature("s"),
                DBusSignature("s"),
                {
                  const DBusString("connection-uuid"): DBusString(uuid),
                  const DBusString("setting-name"): DBusString(setting),
                  const DBusString("setting-key"): DBusString(e.key),
                  const DBusString("xdg:schema"): const DBusString(_schema),
                },
              ),
            }),
            DBusStruct([
              session,
              DBusArray.byte(const []),
              DBusArray.byte(utf8.encode(e.value)),
              const DBusString("text/plain"),
            ]),
            const DBusBoolean(true),
          ],
          replySignature: DBusSignature("oo"),
        );
      }
      return null;
    });
  }

  static Future<void> delete(String uuid) async {
    await _withSession((bus, session) async {
      final DBusMethodSuccessResponse search = await bus.callMethod(
        destination: _service,
        path: DBusObjectPath(_path),
        interface: "org.freedesktop.Secret.Service",
        name: "SearchItems",
        values: [
          DBusDict(
            DBusSignature("s"),
            DBusSignature("s"),
            {const DBusString("connection-uuid"): DBusString(uuid)},
          ),
        ],
        replySignature: DBusSignature("aoao"),
      );
      for (final DBusValue item in [
        ...search.returnValues[0].asArray(),
        ...search.returnValues[1].asArray(),
      ]) {
        await bus.callMethod(
          destination: _service,
          path: item.asObjectPath(),
          interface: "org.freedesktop.Secret.Item",
          name: "Delete",
          replySignature: DBusSignature("o"),
        );
      }
      return null;
    });
  }
}
