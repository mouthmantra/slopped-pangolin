import 'dart:async';
import 'dart:io';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:dbus/dbus.dart';
import 'package:pangolin/services/tray/item.dart';
import 'package:pangolin/services/tray/watcher.dart';

export 'package:pangolin/services/tray/item.dart';

class TrayServiceFactory extends ServiceFactory<TrayService> {
  const TrayServiceFactory();

  @override
  TrayService build() {
    if (!Platform.isLinux) return _DummyTrayService();

    return _DBusTrayService();
  }

  @override
  TrayService? fallback() => _DummyTrayService();
}

/// The system tray: StatusNotifierItems (AppIndicator, KStatusNotifierItem,
/// Qt, Electron) of the session.
abstract class TrayService extends ListenableService {
  TrayService();

  static TrayService get current {
    return ServiceManager.getService<TrayService>()!;
  }

  /// Every item, in tray order: by category, then as they came. Listeners
  /// hear about items coming and going and about status changes; each item
  /// notifies about its own changes.
  List<TrayItem> get items;

  /// Active items and items asking for attention: first in the tray.
  List<TrayItem> get shownItems =>
      [for (final TrayItem i in items) if (i.status != TrayItemStatus.passive) i];

  /// Passive items (nothing to show right now): last in the tray.
  List<TrayItem> get hiddenItems =>
      [for (final TrayItem i in items) if (i.status == TrayItemStatus.passive) i];
}

class _DummyTrayService extends TrayService {
  @override
  FutureOr<void> start() {
    // noop
  }

  @override
  FutureOr<void> stop() {
    // noop
  }

  @override
  List<TrayItem> get items => const [];
}

/// An item the tray knows about, loading or loaded.
class _Entry {
  final ItemAddress address;

  /// Unique bus name of the item's process.
  final String owner;
  final int serial;

  _Entry(this.address, this.owner, this.serial);

  String get registration => "${address.service}${address.path.value}";

  TrayItem? item;
  int attempts = 0;
  Timer? retry;
  TrayItemStatus? status;
  TrayItemCategory? category;
  void Function()? listener;

  bool get shown => item?.ready ?? false;

  void close() {
    retry?.cancel();
    retry = null;
    final TrayItem? item = this.item;
    this.item = null;
    if (item == null) return;
    if (listener != null) item.removeListener(listener!);
    item.close();
  }
}

/// The StatusNotifierWatcher of the session when none runs yet (then also
/// the host), otherwise a host registered with the running one; it takes
/// over when that one leaves.
class _DBusTrayService extends TrayService {
  static const Duration _timeout = Duration(seconds: 3);
  static const String _itemNamePrefix = "org.kde.StatusNotifierItem-";

  final String _hostName = "org.kde.StatusNotifierHost-$pid";

  DBusClient? _client;
  StatusNotifierWatcherObject? _watcher;
  StreamSubscription<DBusNameOwnerChangedEvent>? _names;
  StreamSubscription<DBusSignal>? _watcherSignals;

  /// By owner and object path: an app registering its unique and its
  /// well-known name shows once.
  final Map<String, _Entry> _entries = {};
  List<TrayItem> _items = const [];
  int _serial = 0;
  bool _stopped = false;

  /// Becoming the watcher or a host happens one step at a time.
  Future<void> _transitions = Future.value();

  @override
  List<TrayItem> get items => _items;

  @override
  Future<void> start() async {
    final DBusClient client = DBusClient.session();
    try {
      await client.ping().timeout(_timeout);
    } catch (e) {
      unawaited(client.close().catchError((_) {}));
      throw Exception("No session bus for the tray: $e");
    }
    _client = client;
    _names = client.nameOwnerChanged.listen(
      _onNameOwnerChanged,
      onError: (Object e) => logger.warning("NameOwnerChanged: $e"),
    );
    try {
      await client.requestName(
        _hostName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );
    } catch (e) {
      logger.warning("Couldn't own $_hostName: $e");
    }
    _transition(_claimWatcher);
    await _transitions;
  }

  void _transition(Future<void> Function() step) {
    _transitions = _transitions.then((_) {
      if (_stopped) return null;
      return step();
    }).catchError((Object e, StackTrace s) {
      logger.warning("Tray watcher/host setup failed", e, s);
    });
  }

  /// Becomes the watcher if nobody is, otherwise a host of the watcher.
  Future<void> _claimWatcher() async {
    final DBusClient? client = _client;
    if (client == null || _watcher != null) return;
    final DBusRequestNameReply reply = await client.requestName(
      watcherInterface,
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    if (reply == DBusRequestNameReply.primaryOwner ||
        reply == DBusRequestNameReply.alreadyOwner) {
      await _startWatcher(client);
    } else {
      await _attachToWatcher(client);
    }
  }

  Future<void> _startWatcher(DBusClient client) async {
    final StatusNotifierWatcherObject watcher =
        StatusNotifierWatcherObject(onRegisterItem: _registerItem);
    try {
      await client.registerObject(watcher);
    } catch (e) {
      logger.warning("Couldn't export the StatusNotifierWatcher: $e");
      try {
        await client.releaseName(watcherInterface);
      } catch (_) {}
      return;
    }
    _watcher = watcher;
    await _watcherSignals?.cancel().catchError((_) {});
    _watcherSignals = null;
    logger.info("Running the StatusNotifierWatcher");

    // Items of a watcher that went away stay registered here.
    for (final _Entry entry in _entries.values) {
      watcher.addItem(entry.address, entry.owner);
    }
    unawaited(watcher.emitHostRegistered());
    unawaited(_adoptItems(client));
  }

  /// Items left from a previous watcher (the shell restarting): libappindicator
  /// and Qt register again when a watcher appears, but nothing obliges them
  /// to. Items owning a "org.kde.StatusNotifierItem-*" name can be found.
  Future<void> _adoptItems(DBusClient client) async {
    final List<String> names;
    try {
      names = await client.listNames().timeout(_timeout);
    } catch (_) {
      return;
    }
    for (final String name in names) {
      if (!name.startsWith(_itemNamePrefix)) continue;
      unawaited(_registerItem("", name));
    }
  }

  /// RegisterStatusNotifierItem of our watcher.
  Future<DBusMethodResponse?> _registerItem(String sender, String value) async {
    final ItemAddress? address = parseItemAddress(value, sender: sender);
    if (address == null) {
      return DBusMethodErrorResponse.invalidArgs(
        "Not a bus name or an object path: $value",
      );
    }
    final String? owner = await _ownerOf(address.service);
    if (owner == null) {
      return DBusMethodErrorResponse.invalidArgs(
        "${address.service} is not on the bus",
      );
    }
    final StatusNotifierWatcherObject? watcher = _watcher;
    if (watcher != null && !watcher.hasItemAt(owner, address.path)) {
      watcher.addItem(address, owner);
    }
    _addEntry(address, owner);
    return null;
  }

  Future<void> _attachToWatcher(DBusClient client) async {
    await _watcherSignals?.cancel().catchError((_) {});
    _watcherSignals = DBusSignalStream(
      client,
      sender: watcherInterface,
      path: watcherPath,
      interface: watcherInterface,
    ).listen(
      _onWatcherSignal,
      onError: (Object e) => logger.fine("Watcher signal: $e"),
    );
    logger.info("Using the running StatusNotifierWatcher");

    try {
      await client
          .callMethod(
            destination: watcherInterface,
            path: watcherPath,
            interface: watcherInterface,
            name: "RegisterStatusNotifierHost",
            values: [DBusString(_hostName)],
          )
          .timeout(_timeout);
    } catch (e) {
      logger.warning("Couldn't register as a StatusNotifierHost: $e");
    }

    final List<String> registered;
    try {
      final DBusValue value = await DBusRemoteObject(
        client,
        name: watcherInterface,
        path: watcherPath,
      ).getProperty(watcherInterface, "RegisteredStatusNotifierItems").timeout(
            _timeout,
          );
      registered = value.asStringArray().toList();
    } catch (e) {
      logger.warning("Couldn't read the registered tray items: $e");
      return;
    }
    for (final String item in registered) {
      unawaited(_addAddress(item));
    }
  }

  void _onWatcherSignal(DBusSignal signal) {
    // Left over from before we became the watcher.
    if (_watcher != null) return;
    if (signal.values.isEmpty || signal.values[0] is! DBusString) return;
    final String value = (signal.values[0] as DBusString).value;
    switch (signal.name) {
      case "StatusNotifierItemRegistered":
        unawaited(_addAddress(value));
      case "StatusNotifierItemUnregistered":
        final ItemAddress? address = parseItemAddress(value);
        if (address == null) return;
        _removeEntries(
          (e) =>
              e.address.path == address.path &&
              (e.address.service == address.service ||
                  e.owner == address.service),
        );
    }
  }

  Future<void> _addAddress(String value) async {
    final ItemAddress? address = parseItemAddress(value);
    if (address == null) return;
    final String? owner = await _ownerOf(address.service);
    if (owner != null) _addEntry(address, owner);
  }

  Future<String?> _ownerOf(String service) async {
    final DBusClient? client = _client;
    if (client == null) return null;
    try {
      return await client.getNameOwner(service).timeout(_timeout);
    } catch (_) {
      return null;
    }
  }

  void _onNameOwnerChanged(DBusNameOwnerChangedEvent event) {
    final DBusClient? client = _client;
    if (client == null || _stopped) return;
    if (event.name == watcherInterface) {
      // Ours (the change may arrive before RequestName answers).
      if (_watcher != null || event.newOwner == client.uniqueName) return;
      if (event.newOwner == null) {
        logger.info("The StatusNotifierWatcher left, taking over");
        _transition(_claimWatcher);
      } else {
        _transition(() => _attachToWatcher(client));
      }
      return;
    }
    if (event.newOwner == null) {
      _watcher?.nameVanished(event.name);
      _removeEntries(
        (e) => e.owner == event.name || e.address.service == event.name,
      );
    }
  }

  void _addEntry(ItemAddress address, String owner) {
    final String key = "$owner${address.path.value}";
    final _Entry? existing = _entries[key];
    if (existing != null) {
      // Registering again retries an item that didn't answer before.
      if (existing.item == null && existing.retry == null) {
        existing.attempts = 0;
        unawaited(_load(key, existing));
      }
      return;
    }
    final _Entry entry = _Entry(address, owner, _serial++);
    _entries[key] = entry;
    unawaited(_load(key, entry));
  }

  Future<void> _load(String key, _Entry entry) async {
    final DBusClient? client = _client;
    if (client == null) return;
    entry.retry = null;
    entry.attempts++;
    final TrayItem item = TrayItem(
      client: client,
      busName: entry.owner,
      path: entry.address.path,
      registration: entry.registration,
      serial: entry.serial,
    );
    entry.item = item;
    final TrayItemLoad result = await item.load();
    if (_stopped || _entries[key] != entry || entry.item != item) {
      item.close();
      return;
    }
    switch (result) {
      case TrayItemLoad.loaded:
        entry.status = item.status;
        entry.category = item.category;
        entry.listener = () => _onItemChanged(entry);
        item.addListener(entry.listener!);
        logger.info("Tray item ${entry.registration} (${item.id})");
        _update();
      case TrayItemLoad.gone:
        entry.close();
        _entries.remove(key);
        _watcher?.removeItemAt(entry.owner, entry.address.path);
      case TrayItemLoad.failed:
        entry.close();
        if (entry.attempts < 3) {
          entry.retry = Timer(Duration(seconds: 2 * entry.attempts), () {
            if (_entries[key] == entry) unawaited(_load(key, entry));
          });
        } else {
          logger.warning(
            "Tray item ${entry.registration} doesn't answer, not shown",
          );
        }
    }
  }

  void _onItemChanged(_Entry entry) {
    final TrayItem? item = entry.item;
    if (item == null) return;
    if (item.status == entry.status && item.category == entry.category) {
      return;
    }
    entry.status = item.status;
    entry.category = item.category;
    _update();
  }

  void _removeEntries(bool Function(_Entry entry) test) {
    bool changed = false;
    _entries.removeWhere((key, entry) {
      if (!test(entry)) return false;
      if (entry.shown) changed = true;
      logger.info("Tray item ${entry.registration} left");
      entry.close();
      return true;
    });
    if (changed) _update();
  }

  void _update() {
    final List<_Entry> shown = [
      for (final _Entry entry in _entries.values)
        if (entry.shown) entry,
    ]..sort((a, b) {
        final int category =
            a.item!.category.index.compareTo(b.item!.category.index);
        return category != 0 ? category : a.serial.compareTo(b.serial);
      });
    _items = List.unmodifiable(shown.map((e) => e.item!));
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _names?.cancel().catchError((_) {});
    await _watcherSignals?.cancel().catchError((_) {});
    for (final _Entry entry in _entries.values) {
      entry.close();
    }
    _entries.clear();
    _items = const [];

    final DBusClient? client = _client;
    _client = null;
    if (client == null) return;
    try {
      final StatusNotifierWatcherObject? watcher = _watcher;
      _watcher = null;
      if (watcher != null) {
        await client.unregisterObject(watcher);
        await client.releaseName(watcherInterface);
      }
      await client.releaseName(_hostName);
    } catch (_) {
      // The bus may be gone already.
    }
    await client.close().catchError((_) {});
  }
}
