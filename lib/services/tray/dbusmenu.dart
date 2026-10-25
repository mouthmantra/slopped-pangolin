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

const String _interface = "com.canonical.dbusmenu";

enum DBusMenuToggleType { none, checkmark, radio }

enum DBusMenuDisposition { normal, informative, warning, alert }

/// One entry of a com.canonical.dbusmenu layout, immutable: updates make a
/// new tree that shares the unchanged parts.
class DBusMenuNode {
  /// Menus nested deeper than this, or with more entries, are cut: they come
  /// from another process and must not be able to stall the shell.
  static const int maxDepth = 16;
  static const int maxNodes = 4000;

  final int id;
  final Map<String, DBusValue> properties;
  final List<DBusMenuNode> children;

  DBusMenuNode({
    required this.id,
    this.properties = const {},
    this.children = const [],
  });

  bool get isSeparator => _string("type") == "separator";

  /// The label with its mnemonic marks (`_`).
  String get label => _string("label") ?? "";

  /// The label as shown: mnemonic marks removed.
  String get displayLabel => stripMnemonics(label);

  bool get enabled => _bool("enabled") ?? true;
  bool get visible => _bool("visible") ?? true;

  String? get iconName {
    final String? name = _string("icon-name");
    return name == null || name.isEmpty ? null : name;
  }

  /// PNG data. The same list each time (images are cached by it).
  late final Uint8List? iconData = () {
    final DBusValue? value = properties["icon-data"];
    if (value is! DBusArray || value.childSignature != DBusSignature.byte) {
      return null;
    }
    if (value.children.isEmpty) return null;
    return Uint8List.fromList(value.asByteArray().toList());
  }();

  bool get hasIcon => iconName != null || properties["icon-data"] != null;

  DBusMenuToggleType get toggleType => switch (_string("toggle-type")) {
        "checkmark" => DBusMenuToggleType.checkmark,
        "radio" => DBusMenuToggleType.radio,
        _ => DBusMenuToggleType.none,
      };

  /// On, off, or null for "indeterminate".
  bool? get toggleState {
    final DBusValue? value = properties["toggle-state"];
    if (value is DBusBoolean) return value.value;
    final int? state = _intOf(value);
    if (state == 1) return true;
    if (state == 0) return false;
    return null;
  }

  /// Whether this entry opens a submenu. The children of some (Qt's) only
  /// arrive once AboutToShow was called for it.
  bool get isSubmenu =>
      _string("children-display") == "submenu" || children.isNotEmpty;

  DBusMenuDisposition get disposition => switch (_string("disposition")) {
        "informative" => DBusMenuDisposition.informative,
        "warning" => DBusMenuDisposition.warning,
        "alert" => DBusMenuDisposition.alert,
        _ => DBusMenuDisposition.normal,
      };

  /// What is shown: hidden entries left out, and separators only between
  /// other entries, one at a time.
  List<DBusMenuNode> get shownChildren {
    final List<DBusMenuNode> result = [];
    for (final DBusMenuNode child in children) {
      if (!child.visible) continue;
      if (child.isSeparator && (result.isEmpty || result.last.isSeparator)) {
        continue;
      }
      result.add(child);
    }
    while (result.isNotEmpty && result.last.isSeparator) {
      result.removeLast();
    }
    return result;
  }

  DBusMenuNode? find(int id) {
    if (this.id == id) return this;
    for (final DBusMenuNode child in children) {
      final DBusMenuNode? found = child.find(id);
      if (found != null) return found;
    }
    return null;
  }

  /// This tree with the properties of ItemsPropertiesUpdated applied:
  /// [updated] values set, [removed] names back to their defaults.
  DBusMenuNode withProperties(
    Map<int, Map<String, DBusValue>> updated,
    Map<int, List<String>> removed,
  ) {
    bool changed = false;
    final List<DBusMenuNode> newChildren = [];
    for (final DBusMenuNode child in children) {
      final DBusMenuNode newChild = child.withProperties(updated, removed);
      if (!identical(newChild, child)) changed = true;
      newChildren.add(newChild);
    }

    Map<String, DBusValue> newProperties = properties;
    final Map<String, DBusValue>? set = updated[id];
    final List<String>? unset = removed[id];
    if (set != null || unset != null) {
      newProperties = Map.of(properties);
      if (unset != null) unset.forEach(newProperties.remove);
      if (set != null) newProperties.addAll(set);
      changed = true;
    }

    if (!changed) return this;
    return DBusMenuNode(
      id: id,
      properties: newProperties,
      children: newChildren,
    );
  }

  /// Parses a `(ia{sv}av)` layout. Null when [value] isn't one; children
  /// that aren't are skipped.
  static DBusMenuNode? parse(DBusValue value) => _parse(value, 0, _Budget());

  static DBusMenuNode? _parse(DBusValue raw, int depth, _Budget budget) {
    final DBusValue value = raw is DBusVariant ? raw.value : raw;
    if (value is! DBusStruct || value.children.length < 3) return null;
    if (budget.nodes++ >= maxNodes) return null;
    final List<DBusValue> fields = value.children;
    final int? id = _intOf(fields[0]);
    if (id == null) return null;

    final Map<String, DBusValue> properties = {};
    final DBusValue rawProperties = fields[1];
    if (rawProperties is DBusDict) {
      for (final MapEntry<DBusValue, DBusValue> entry
          in rawProperties.children.entries) {
        final DBusValue key = entry.key;
        if (key is! DBusString) continue;
        final DBusValue v = entry.value;
        properties[key.value] = v is DBusVariant ? v.value : v;
      }
    }

    final List<DBusMenuNode> children = [];
    final DBusValue rawChildren = fields[2];
    if (rawChildren is DBusArray && depth < maxDepth) {
      for (final DBusValue child in rawChildren.children) {
        final DBusMenuNode? node = _parse(child, depth + 1, budget);
        if (node != null) children.add(node);
      }
    }

    return DBusMenuNode(id: id, properties: properties, children: children);
  }

  String? _string(String name) {
    final DBusValue? value = properties[name];
    return value is DBusString ? value.value : null;
  }

  bool? _bool(String name) {
    final DBusValue? value = properties[name];
    if (value is DBusBoolean) return value.value;
    final int? number = _intOf(value);
    return number == null ? null : number != 0;
  }

  @override
  String toString() => "DBusMenuNode($id, $label, ${children.length})";
}

class _Budget {
  int nodes = 0;
}

/// Removes the mnemonic marks of a dbusmenu label: `_` before the access
/// key goes, `__` is a literal underscore.
String stripMnemonics(String label) {
  if (!label.contains("_")) return label;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < label.length; i++) {
    final String c = label[i];
    if (c != "_") {
      out.write(c);
    } else if (i + 1 < label.length && label[i + 1] == "_") {
      out.write("_");
      i++;
    }
  }
  return out.toString();
}

/// Reads the arguments of ItemsPropertiesUpdated (`a(ia{sv})a(ias)`).
({Map<int, Map<String, DBusValue>> updated, Map<int, List<String>> removed})
    parseMenuPropertyUpdates(List<DBusValue> values) {
  final Map<int, Map<String, DBusValue>> updated = {};
  final Map<int, List<String>> removed = {};
  if (values.isNotEmpty && values[0] is DBusArray) {
    for (final DBusValue entry in (values[0] as DBusArray).children) {
      if (entry is! DBusStruct || entry.children.length < 2) continue;
      final int? id = _intOf(entry.children[0]);
      final DBusValue dict = entry.children[1];
      if (id == null || dict is! DBusDict) continue;
      final Map<String, DBusValue> properties = updated[id] ??= {};
      for (final MapEntry<DBusValue, DBusValue> p in dict.children.entries) {
        if (p.key is! DBusString) continue;
        final DBusValue v = p.value;
        properties[(p.key as DBusString).value] =
            v is DBusVariant ? v.value : v;
      }
    }
  }
  if (values.length > 1 && values[1] is DBusArray) {
    for (final DBusValue entry in (values[1] as DBusArray).children) {
      if (entry is! DBusStruct || entry.children.length < 2) continue;
      final int? id = _intOf(entry.children[0]);
      final DBusValue names = entry.children[1];
      if (id == null || names is! DBusArray) continue;
      (removed[id] ??= []).addAll(names.children.whereType<DBusString>().map(
            (e) => e.value,
          ));
    }
  }
  return (updated: updated, removed: removed);
}

int? _intOf(DBusValue? value) => switch (value) {
      DBusInt32(:final value) => value,
      DBusUint32(:final value) => value,
      DBusInt64(:final value) => value,
      DBusUint64(:final value) => value,
      DBusInt16(:final value) => value,
      DBusUint16(:final value) => value,
      DBusByte(:final value) => value,
      _ => null,
    };

/// The menu of a tray item, read over com.canonical.dbusmenu.
///
/// The layout is read when the menu is about to open, and kept up to date
/// while it is open (LayoutUpdated, ItemsPropertiesUpdated). Every call has
/// a timeout and every failure is swallowed: the menu then just doesn't
/// open.
class DBusMenuClient extends ChangeNotifier {
  static final Logger _logger = Logger("TrayMenu");
  static const Duration _timeout = Duration(seconds: 2);

  final DBusClient client;
  final String busName;
  final DBusObjectPath path;

  DBusMenuClient(this.client, this.busName, this.path) {
    _signals = DBusSignalStream(
      client,
      sender: busName,
      path: path,
      interface: _interface,
    ).listen(
      _onSignal,
      onError: (Object e) => _logger.fine("Signal error from $busName: $e"),
    );
  }

  late final StreamSubscription<DBusSignal> _signals;
  bool _disposed = false;

  DBusMenuNode? _root;

  /// The layout as last read, null before it was.
  DBusMenuNode? get root => _root;

  /// Set when the layout changed since it was read.
  bool _stale = true;

  /// Menus and submenus open right now.
  final Set<int> _open = {};

  bool _fetching = false;
  bool _fetchAgain = false;
  Timer? _fetchTimer;

  /// Gets the menu ready to open: AboutToShow for the root, then the
  /// layout if it changed. Null when there is nothing to show.
  Future<DBusMenuNode?> prepare() async {
    final bool needsUpdate = await _aboutToShow(0);
    if (_root == null || _stale || needsUpdate) await _fetchLayout();
    final DBusMenuNode? root = _root;
    if (root == null || root.shownChildren.isEmpty) return null;
    return root;
  }

  /// A menu ([id] 0) or submenu opened.
  void opened(int id) {
    _open.add(id);
    _event(id, "opened");
    if (id != 0) {
      unawaited(
        _aboutToShow(id).then((update) {
          if (update) _scheduleFetch();
        }),
      );
    }
  }

  void closed(int id) {
    if (!_open.remove(id)) return;
    _event(id, "closed");
  }

  void clicked(int id) => _event(id, "clicked");

  bool get _isOpen => _open.isNotEmpty;

  Future<bool> _aboutToShow(int id) async {
    try {
      final DBusMethodSuccessResponse response = await client
          .callMethod(
            destination: busName,
            path: path,
            interface: _interface,
            name: "AboutToShow",
            values: [DBusInt32(id)],
          )
          .timeout(_timeout);
      final List<DBusValue> values = response.returnValues;
      return values.isNotEmpty &&
          values[0] is DBusBoolean &&
          (values[0] as DBusBoolean).value;
    } catch (e) {
      // Optional for the item (Electron doesn't have it).
      return false;
    }
  }

  void _event(int id, String event) {
    final int timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0xffffffff;
    unawaited(
      client
          .callMethod(
            destination: busName,
            path: path,
            interface: _interface,
            name: "Event",
            values: [
              DBusInt32(id),
              DBusString(event),
              const DBusVariant(DBusInt32(0)),
              DBusUint32(timestamp),
            ],
          )
          .timeout(_timeout)
          .then<void>((_) {}, onError: (Object e) {
        _logger.fine("Event $event on $id of $busName failed: $e");
      }),
    );
  }

  void _scheduleFetch() {
    if (_disposed) return;
    if (_fetching) {
      _fetchAgain = true;
      return;
    }
    // Updates come in bursts.
    _fetchTimer ??= Timer(const Duration(milliseconds: 30), () {
      _fetchTimer = null;
      unawaited(_fetchLayout());
    });
  }

  Future<void> _fetchLayout() async {
    if (_disposed) return;
    if (_fetching) {
      _fetchAgain = true;
      return;
    }
    _fetching = true;
    try {
      do {
        _fetchAgain = false;
        _stale = false;
        final DBusMethodSuccessResponse response = await client
            .callMethod(
              destination: busName,
              path: path,
              interface: _interface,
              name: "GetLayout",
              values: [
                const DBusInt32(0),
                const DBusInt32(-1),
                DBusArray.string(const []),
              ],
            )
            .timeout(_timeout);
        if (_disposed) return;
        final List<DBusValue> values = response.returnValues;
        final DBusMenuNode? root =
            values.length >= 2 ? DBusMenuNode.parse(values[1]) : null;
        if (root == null) {
          _logger.fine("Unusable layout from $busName$path");
        }
        _root = root;
        notifyListeners();
      } while (_fetchAgain && !_disposed);
    } catch (e) {
      _logger.fine("GetLayout of $busName$path failed: $e");
      _stale = true;
    } finally {
      _fetching = false;
    }
  }

  void _onSignal(DBusSignal signal) {
    if (_disposed) return;
    switch (signal.name) {
      case "LayoutUpdated":
        _stale = true;
        if (_isOpen) _scheduleFetch();
      case "ItemsPropertiesUpdated":
        final DBusMenuNode? root = _root;
        if (root == null) return;
        final updates = parseMenuPropertyUpdates(signal.values);
        final DBusMenuNode newRoot =
            root.withProperties(updates.updated, updates.removed);
        if (identical(newRoot, root)) return;
        _root = newRoot;
        notifyListeners();
    }
  }

  /// Stops following the menu (its item is gone, or has another menu now).
  /// An open menu may still hold it, so it isn't disposed.
  void close() {
    if (_disposed) return;
    _disposed = true;
    _fetchTimer?.cancel();
    unawaited(_signals.cancel().catchError((_) {}));
  }

  bool get isClosed => _disposed;

  @override
  void dispose() {
    close();
    super.dispose();
  }
}
