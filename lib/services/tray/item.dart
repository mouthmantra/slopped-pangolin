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
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pangolin/services/tray/dbusmenu.dart';
import 'package:pangolin/services/tray/pixmap.dart';

enum TrayItemStatus {
  passive,
  active,
  needsAttention;

  static TrayItemStatus parse(String? value) => switch (value) {
        "Passive" => passive,
        "NeedsAttention" => needsAttention,
        // Unknown values: better shown than lost.
        _ => active,
      };
}

/// Order of the categories in the tray, the hardware (network, Bluetooth)
/// closest to the clock.
enum TrayItemCategory {
  applicationStatus,
  communications,
  systemServices,
  hardware;

  static TrayItemCategory parse(String? value) => switch (value) {
        "Communications" => communications,
        "SystemServices" => systemServices,
        "Hardware" => hardware,
        _ => applicationStatus,
      };
}

/// An icon as an item describes it: a name from the icon theme, pixmaps, or
/// both (the name is preferred when the theme has it).
@immutable
class TrayIconSource {
  final String? name;
  final List<TrayPixmap> pixmaps;

  const TrayIconSource({this.name, this.pixmaps = const []});

  bool get isEmpty => name == null && pixmaps.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TrayIconSource &&
      other.name == name &&
      listEquals(other.pixmaps, pixmaps);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(pixmaps));
}

@immutable
class TrayToolTip {
  final String title;
  final String description;
  final TrayIconSource icon;

  const TrayToolTip({
    this.title = "",
    this.description = "",
    this.icon = const TrayIconSource(),
  });

  @override
  bool operator ==(Object other) =>
      other is TrayToolTip &&
      other.title == title &&
      other.description == description &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(title, description, icon);
}

/// [markup] without its tags and with the common entities decoded.
String plainText(String markup) {
  if (!markup.contains("<") && !markup.contains("&")) return markup.trim();
  return markup
      .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), "\n")
      .replaceAll(RegExp("<[^>]*>"), "")
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", '"')
      .replaceAll("&#39;", "'")
      .replaceAll("&apos;", "'")
      .replaceAll("&nbsp;", " ")
      .replaceAll("&amp;", "&")
      .trim();
}

enum TrayScrollOrientation { vertical, horizontal }

enum TrayItemLoad {
  loaded,

  /// The object or its owner doesn't exist (any more).
  gone,

  /// It didn't answer, or not usefully: worth trying again later.
  failed,
}

/// A StatusNotifierItem on the session bus.
///
/// Its properties are read with one GetAll and read again (coalesced) when
/// it signals a change. Nothing here throws: a broken item just keeps its
/// last state.
class TrayItem extends ChangeNotifier {
  static final Logger _logger = Logger("TrayItem");
  static const Duration _timeout = Duration(seconds: 3);

  /// Interfaces of items: the KDE one, and the freedesktop one of the
  /// original draft that a few implementations still use.
  static const List<String> _interfaces = [
    "org.kde.StatusNotifierItem",
    "org.freedesktop.StatusNotifierItem",
  ];

  final DBusClient client;

  /// The unique bus name of the process showing the item.
  final String busName;
  final DBusObjectPath path;

  /// What the item was registered as ("service/path").
  final String registration;

  /// Order of registration, for a stable order in the tray.
  final int serial;

  TrayItem({
    required this.client,
    required this.busName,
    required this.path,
    required this.registration,
    required this.serial,
  });

  String _interface = _interfaces.first;
  StreamSubscription<DBusSignal>? _signals;
  bool _disposed = false;

  /// Set once the properties were read: the item can be shown.
  bool get ready => _ready;
  bool _ready = false;

  String id = "";
  String title = "";
  TrayItemCategory category = TrayItemCategory.applicationStatus;
  TrayItemStatus status = TrayItemStatus.active;
  TrayIconSource icon = const TrayIconSource();
  TrayIconSource attentionIcon = const TrayIconSource();
  TrayIconSource overlayIcon = const TrayIconSource();
  String? iconThemePath;
  TrayToolTip toolTip = const TrayToolTip();
  bool itemIsMenu = false;

  DBusObjectPath? _menuPath;
  DBusMenuClient? _menu;

  /// The item's dbusmenu, if it has one.
  DBusMenuClient? get menu => _menu;

  /// The icon to show now: the attention icon while the item asks for
  /// attention (if it has one).
  TrayIconSource get currentIcon =>
      status == TrayItemStatus.needsAttention && !attentionIcon.isEmpty
          ? attentionIcon
          : icon;

  /// A name for the item, for tooltips and accessibility.
  String get label {
    if (toolTip.title.isNotEmpty) return toolTip.title;
    if (title.isNotEmpty) return title;
    return id;
  }

  /// The tooltip as plain text: its title, or the item's, then the
  /// description (KDE items send it as rich text).
  String get toolTipText {
    final String heading = toolTip.title.isNotEmpty ? toolTip.title : title;
    final String description = plainText(toolTip.description);
    if (description.isEmpty || description == heading) return heading;
    if (heading.isEmpty) return description;
    return "$heading\n$description";
  }

  /// Reads the properties and starts following the item's signals.
  Future<TrayItemLoad> load() async {
    Map<String, DBusValue>? properties;
    for (final String interface in _interfaces) {
      try {
        properties = await _getAll(interface);
        if (properties.isEmpty) continue;
        _interface = interface;
        break;
      } on TimeoutException {
        return TrayItemLoad.failed;
      } catch (e) {
        // No point trying the other interface.
        if (_isGone(e)) return TrayItemLoad.gone;
      }
    }
    if (_disposed) return TrayItemLoad.gone;
    if (properties == null || properties.isEmpty) {
      // Some implementations have no GetAll: read what matters one by one.
      properties = (await _getEach(_allProperties)).values;
      if (_disposed) return TrayItemLoad.gone;
      if (properties.isEmpty) return TrayItemLoad.failed;
    }

    _apply(properties);
    _signals = DBusSignalStream(
      client,
      sender: busName,
      path: path,
      interface: _interface,
    ).listen(
      _onSignal,
      onError: (Object e) => _logger.fine("Signal error from $busName: $e"),
    );
    _ready = true;
    return TrayItemLoad.loaded;
  }

  static bool _isGone(Object e) {
    if (e is! DBusMethodResponseException) return false;
    return const {
      "org.freedesktop.DBus.Error.ServiceUnknown",
      "org.freedesktop.DBus.Error.NameHasNoOwner",
      "org.freedesktop.DBus.Error.UnknownObject",
    }.contains(e.errorName);
  }

  Future<Map<String, DBusValue>> _getAll(String interface) async {
    final DBusMethodSuccessResponse response = await client
        .callMethod(
          destination: busName,
          path: path,
          interface: "org.freedesktop.DBus.Properties",
          name: "GetAll",
          values: [DBusString(interface)],
        )
        .timeout(_timeout);
    final List<DBusValue> values = response.returnValues;
    if (values.isEmpty || values[0] is! DBusDict) return {};
    final Map<String, DBusValue> result = {};
    for (final MapEntry<DBusValue, DBusValue> entry
        in (values[0] as DBusDict).children.entries) {
      if (entry.key is! DBusString) continue;
      final DBusValue v = entry.value;
      result[(entry.key as DBusString).value] = v is DBusVariant ? v.value : v;
    }
    return result;
  }

  static const List<String> _allProperties = [
    "Id",
    "Category",
    "Title",
    "Status",
    "IconName",
    "IconPixmap",
    "IconThemePath",
    "AttentionIconName",
    "AttentionIconPixmap",
    "OverlayIconName",
    "OverlayIconPixmap",
    "ToolTip",
    "ItemIsMenu",
    "Menu",
  ];

  /// Reads [names] one by one: the values, and the names the item answered
  /// with an error for (it doesn't have them, or not any more).
  Future<({Map<String, DBusValue> values, Set<String> absent})> _getEach(
    Iterable<String> names,
  ) async {
    final Map<String, DBusValue> values = {};
    final Set<String> absent = {};
    await Future.wait(
      names.map((name) async {
        try {
          final DBusMethodSuccessResponse response = await client
              .callMethod(
                destination: busName,
                path: path,
                interface: "org.freedesktop.DBus.Properties",
                name: "Get",
                values: [DBusString(_interface), DBusString(name)],
              )
              .timeout(_timeout);
          final List<DBusValue> result = response.returnValues;
          if (result.isEmpty) return;
          final DBusValue v = result[0];
          values[name] = v is DBusVariant ? v.value : v;
        } on DBusMethodResponseException {
          absent.add(name);
        } catch (_) {
          // No answer: keep what we have.
        }
      }),
    );
    return (values: values, absent: absent);
  }

  /// Applies read properties; true when something shown changed.
  bool _apply(Map<String, DBusValue> p) {
    bool changed = false;
    void set<T>(T current, T value, void Function(T) assign) {
      if (current == value) return;
      assign(value);
      changed = true;
    }

    if (p.containsKey("Id")) set(id, _string(p["Id"]) ?? "", (v) => id = v);
    if (p.containsKey("Title")) {
      set(title, _string(p["Title"]) ?? "", (v) => title = v);
    }
    if (p.containsKey("Category")) {
      set(
        category,
        TrayItemCategory.parse(_string(p["Category"])),
        (v) => category = v,
      );
    }
    if (p.containsKey("Status")) {
      set(
        status,
        TrayItemStatus.parse(_string(p["Status"])),
        (v) => status = v,
      );
    }
    if (p.containsKey("IconName") || p.containsKey("IconPixmap")) {
      set(icon, _icon(p, "IconName", "IconPixmap"), (v) => icon = v);
    }
    if (p.containsKey("AttentionIconName") ||
        p.containsKey("AttentionIconPixmap")) {
      set(
        attentionIcon,
        _icon(p, "AttentionIconName", "AttentionIconPixmap"),
        (v) => attentionIcon = v,
      );
    }
    if (p.containsKey("OverlayIconName") ||
        p.containsKey("OverlayIconPixmap")) {
      set(
        overlayIcon,
        _icon(p, "OverlayIconName", "OverlayIconPixmap"),
        (v) => overlayIcon = v,
      );
    }
    if (p.containsKey("IconThemePath")) {
      final String? themePath = _string(p["IconThemePath"]);
      set(
        iconThemePath,
        themePath == null || themePath.isEmpty ? null : themePath,
        (v) => iconThemePath = v,
      );
    }
    if (p.containsKey("ToolTip")) {
      set(toolTip, _toolTip(p["ToolTip"]), (v) => toolTip = v);
    }
    if (p.containsKey("ItemIsMenu")) {
      final DBusValue? value = p["ItemIsMenu"];
      set(
        itemIsMenu,
        value is DBusBoolean && value.value,
        (v) => itemIsMenu = v,
      );
    }
    if (p.containsKey("Menu")) {
      final DBusValue? value = p["Menu"];
      DBusObjectPath? menuPath;
      if (value is DBusObjectPath) {
        menuPath = value;
      } else if (value is DBusString) {
        // Some send the path as a string.
        try {
          menuPath = DBusObjectPath(value.value);
        } catch (_) {}
      }
      // Qt's way of saying "no menu".
      if (menuPath?.value == "/NO_DBUSMENU") menuPath = null;
      if (menuPath != _menuPath) {
        _menuPath = menuPath;
        _menu?.close();
        _menu = menuPath == null
            ? null
            : DBusMenuClient(client, busName, menuPath);
        changed = true;
      }
    }
    return changed;
  }

  static TrayIconSource _icon(
    Map<String, DBusValue> p,
    String nameKey,
    String pixmapKey,
  ) {
    final String? name = _string(p[nameKey]);
    return TrayIconSource(
      name: name == null || name.isEmpty ? null : name,
      pixmaps: parseTrayPixmaps(p[pixmapKey]),
    );
  }

  /// `(sa(iiay)ss)`: icon name, icon pixmaps, title, description.
  static TrayToolTip _toolTip(DBusValue? value) {
    if (value is! DBusStruct || value.children.length < 4) {
      return const TrayToolTip();
    }
    final List<DBusValue> fields = value.children;
    final String? iconName = _string(fields[0]);
    return TrayToolTip(
      icon: TrayIconSource(
        name: iconName == null || iconName.isEmpty ? null : iconName,
        pixmaps: parseTrayPixmaps(fields[1]),
      ),
      title: _string(fields[2]) ?? "",
      description: _string(fields[3]) ?? "",
    );
  }

  // Object paths are strings too.
  static String? _string(DBusValue? value) =>
      value is DBusString ? value.value : null;

  // Signals: each says which properties to read again.

  final Set<String> _pending = {};
  Timer? _refreshTimer;
  bool _refreshing = false;

  static const Map<String, List<String>> _signalProperties = {
    "NewTitle": ["Title"],
    "NewIcon": ["IconName", "IconPixmap"],
    "NewAttentionIcon": ["AttentionIconName", "AttentionIconPixmap"],
    "NewOverlayIcon": ["OverlayIconName", "OverlayIconPixmap"],
    "NewToolTip": ["ToolTip"],
    "NewStatus": ["Status"],
    "NewIconThemePath": ["IconThemePath"],
    "NewMenu": ["Menu"],
  };

  void _onSignal(DBusSignal signal) {
    if (_disposed) return;
    final List<String>? properties = _signalProperties[signal.name];
    if (properties == null) return;

    // These two carry the new value.
    if (signal.values.isNotEmpty && signal.values[0] is DBusString) {
      final String value = (signal.values[0] as DBusString).value;
      if (signal.name == "NewStatus") {
        if (_apply({"Status": DBusString(value)})) notifyListeners();
        return;
      }
      if (signal.name == "NewIconThemePath") {
        if (_apply({"IconThemePath": DBusString(value)})) notifyListeners();
        return;
      }
    }

    _pending.addAll(properties);
    // Animated icons and progress tooltips signal many times a second.
    _refreshTimer ??= Timer(const Duration(milliseconds: 50), _refresh);
  }

  Future<void> _refresh() async {
    _refreshTimer = null;
    if (_disposed || _refreshing || _pending.isEmpty) return;
    _refreshing = true;
    final List<String> names = _pending.toList();
    _pending.clear();
    try {
      final (:values, :absent) = await _getEach(names);
      if (_disposed) return;
      // Properties the item no longer has go back to their defaults (an
      // appindicator has no pixmaps: its IconPixmap is always absent).
      for (final String name in absent) {
        values.putIfAbsent(name, () => const DBusString(""));
      }
      if (_apply(values)) notifyListeners();
    } finally {
      _refreshing = false;
      if (_pending.isNotEmpty && !_disposed) {
        _refreshTimer ??= Timer(const Duration(milliseconds: 50), _refresh);
      }
    }
  }

  // Actions. They report whether the item took the call.

  Future<bool> activate(int x, int y) =>
      _call("Activate", [DBusInt32(x), DBusInt32(y)]);

  Future<bool> secondaryActivate(int x, int y) =>
      _call("SecondaryActivate", [DBusInt32(x), DBusInt32(y)]);

  /// Asks the item to show its own menu (items without a dbusmenu).
  Future<bool> contextMenu(int x, int y) =>
      _call("ContextMenu", [DBusInt32(x), DBusInt32(y)]);

  /// Whether the item is libappindicator's (or Ayatana's): it lives there.
  bool get isAppIndicator =>
      path.value.startsWith("/org/ayatana/NotificationItem");

  /// Scrolls by [steps] wheel notches, positive down (or right).
  ///
  /// The protocol leaves the units to the implementations, and they differ:
  /// libappindicator takes positive as down and hands the delta on to the
  /// app as a count; KDE's items and xembedsniproxy take Qt's wheel angle,
  /// 120 a notch, positive up.
  Future<bool> scroll(int steps, TrayScrollOrientation orientation) => _call(
        "Scroll",
        [
          DBusInt32(isAppIndicator ? steps : -steps * 120),
          DBusString(orientation.name),
        ],
      );

  Future<bool> _call(String method, List<DBusValue> values) async {
    if (_disposed) return false;
    try {
      await client
          .callMethod(
            destination: busName,
            path: path,
            interface: _interface,
            name: method,
            values: values,
          )
          .timeout(_timeout);
      return true;
    } catch (e) {
      _logger.fine("$method on $registration failed: $e");
      return false;
    }
  }

  /// Stops following the item, which is gone. Widgets may still hold it for
  /// a frame, so the tray closes it rather than disposing it.
  void close() {
    if (_disposed) return;
    _disposed = true;
    _refreshTimer?.cancel();
    unawaited(_signals?.cancel().catchError((_) {}));
    _menu?.close();
    _menu = null;
  }

  @override
  void dispose() {
    close();
    super.dispose();
  }

  @override
  String toString() => "TrayItem($registration, $id)";
}
