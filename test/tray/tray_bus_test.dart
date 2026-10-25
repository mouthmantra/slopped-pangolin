// The tray against real items on a private session bus. Needs dbus-run-session
// and python3-dbus-next:
//
//   PANGOLIN_TRAY_BUS_TEST=1 dbus-run-session -- flutter test test/tray/tray_bus_test.dart
//
// Skipped otherwise: it would take over the StatusNotifierWatcher of the bus
// it runs on.

import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pangolin/services/tray.dart';
import 'package:pangolin/services/tray/dbusmenu.dart';

const String _watcher = "org.kde.StatusNotifierWatcher";
final DBusObjectPath _watcherPath = DBusObjectPath("/StatusNotifierWatcher");

String? get _skip {
  if (Platform.environment["PANGOLIN_TRAY_BUS_TEST"] != "1") {
    return "Set PANGOLIN_TRAY_BUS_TEST=1 and run under dbus-run-session";
  }
  final String address = Platform.environment["DBUS_SESSION_BUS_ADDRESS"] ?? "";
  // Never the session's real bus.
  if (address.isEmpty || address.contains("/run/user/")) {
    return "Not a private bus: $address";
  }
  return null;
}

/// A test client (fixtures/*.py) and what it printed.
class Client {
  final Process process;
  final List<String> lines = [];

  Client._(this.process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    process.stderr.transform(utf8.decoder).listen((e) => stderr.write("[client] $e"));
  }

  static final List<Client> _all = [];

  static Future<Client> start(String fixture, [List<String> args = const []]) async {
    final Process process = await Process.start(
      "python3",
      ["-I", "test/tray/fixtures/$fixture", ...args],
    );
    final Client client = Client._(process);
    _all.add(client);
    await until(() => client.lines.any((l) => l.startsWith("READY") || l.startsWith("WATCHER")));
    return client;
  }

  static Future<Client> item([List<String> args = const []]) => start("sni_item.py", args);

  /// The unique bus name, from its READY line.
  String get uniqueName => lines.firstWhere((l) => l.startsWith("READY")).split(" ")[1];

  void send(String command) => process.stdin.writeln(command);

  Future<void> saw(String line) => until(() => lines.contains(line), reason: line);

  Future<void> kill() async {
    process.kill();
    await process.exitCode;
    _all.remove(this);
  }

  static Future<void> killAll() async {
    for (final Client c in List.of(_all)) {
      await c.kill();
    }
  }
}

Future<void> until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String? reason,
}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure("Timed out waiting${reason != null ? " for $reason" : ""}");
    }
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

Future<List<String>> registered(DBusClient bus) async {
  final DBusValue value = await DBusRemoteObject(bus, name: _watcher, path: _watcherPath)
      .getProperty(_watcher, "RegisteredStatusNotifierItems");
  return value.asStringArray().toList();
}

TrayItem? itemOf(TrayService tray, Client client) =>
    tray.items.where((e) => e.busName == client.uniqueName).firstOrNull;

void main() {
  late DBusClient bus;

  setUpAll(() {
    if (_skip == null) bus = DBusClient.session();
  });
  tearDownAll(() async {
    await Client.killAll();
    if (_skip == null) await bus.close();
  });

  group("as the watcher", skip: _skip, () {
    late TrayService tray;
    late Client a;

    setUpAll(() async {
      tray = const TrayServiceFactory().build();
      await tray.start();
    });
    tearDownAll(() async {
      await tray.stop();
      await Client.killAll();
    });

    test("owns the watcher name and is a host", () async {
      expect(await bus.getNameOwner(_watcher), isNotNull);
      expect(await bus.getNameOwner("org.kde.StatusNotifierHost-$pid"), isNotNull);
      final DBusRemoteObject watcher =
          DBusRemoteObject(bus, name: _watcher, path: _watcherPath);
      expect(
        await watcher.getProperty(_watcher, "IsStatusNotifierHostRegistered"),
        const DBusBoolean(true),
      );
      expect(await watcher.getProperty(_watcher, "ProtocolVersion"), const DBusInt32(0));
    });

    test("an item registered by its path (libappindicator) shows", () async {
      a = await Client.item([
        "--register", "path", "--id", "app-a", "--title", "App A",
        "--icon", "audio-volume-high", "--pixmaps", "--category", "Hardware",
      ]);
      await until(() => itemOf(tray, a) != null, reason: "app-a in the tray");
      final TrayItem item = itemOf(tray, a)!;
      expect(item.id, "app-a");
      expect(item.title, "App A");
      expect(item.status, TrayItemStatus.active);
      expect(item.category, TrayItemCategory.hardware);
      expect(item.icon.name, "audio-volume-high");
      expect(item.icon.pixmaps.map((e) => e.width), [16, 32]);
      expect(item.icon.pixmaps.first.toRgba().sublist(0, 4), [255, 0, 0, 255]);
      expect(item.menu, isNotNull);
      expect(item.itemIsMenu, isFalse);
      expect(
        await registered(bus),
        contains("${a.uniqueName}/org/ayatana/NotificationItem/app_a"),
      );
    });

    test("items registered by name all show, though all are at /StatusNotifierItem", () async {
      final Client b = await Client.item(["--register", "name", "--id", "qt-b", "--no-menu"]);
      final Client c = await Client.item(["--register", "name", "--id", "qt-c"]);
      await until(() => itemOf(tray, b) != null && itemOf(tray, c) != null);
      expect(itemOf(tray, b)!.menu, isNull, reason: "/NO_DBUSMENU is no menu");
      expect(itemOf(tray, c)!.id, "qt-c");
      // Hardware goes last, next to the clock.
      expect(tray.items.last, same(itemOf(tray, a)));
      expect(await registered(bus), hasLength(3));
    });

    test("passive items are hidden, attention shows the attention icon", () async {
      final TrayItem item = itemOf(tray, a)!;
      a.send("status Passive");
      await until(() => tray.hiddenItems.contains(item));
      expect(tray.shownItems, isNot(contains(item)));

      a.send("attention mail-unread");
      a.send("status NeedsAttention");
      await until(
        () => item.status == TrayItemStatus.needsAttention && item.currentIcon.name == "mail-unread",
      );
      expect(tray.shownItems, contains(item));

      a.send("status Active");
      await until(() => item.status == TrayItemStatus.active);
      expect(item.currentIcon.name, "audio-volume-high");
    });

    test("follows the item's signals", () async {
      final TrayItem item = itemOf(tray, a)!;
      a.send("title Renamed");
      a.send("icon audio-volume-muted");
      a.send("overlay emblem-important");
      a.send("tooltip Volume|<b>40</b>&amp;muted");
      await until(
        () =>
            item.title == "Renamed" &&
            item.icon.name == "audio-volume-muted" &&
            item.overlayIcon.name == "emblem-important" &&
            item.toolTip.title == "Volume",
      );
      expect(item.toolTipText, "Volume\n40&muted");

      a.send("pixmap 24");
      await until(() => item.icon.name == null);
      expect(item.icon.pixmaps.single.width, 24);
    });

    test("clicks, the middle button and the wheel reach the item", () async {
      final TrayItem item = itemOf(tray, a)!;
      expect(await item.activate(5, 6), isTrue);
      await a.saw("CALL Activate 5 6");
      expect(await item.secondaryActivate(7, 8), isTrue);
      await a.saw("CALL SecondaryActivate 7 8");
      // An appindicator: notches, positive down.
      expect(item.isAppIndicator, isTrue);
      expect(await item.scroll(-2, TrayScrollOrientation.vertical), isTrue);
      await a.saw("CALL Scroll -2 vertical");
      expect(await item.contextMenu(1, 2), isTrue);
      await a.saw("CALL ContextMenu 1 2");

      // A KDE item: Qt's wheel angle, positive up.
      final Client kde = await Client.item(["--register", "name", "--id", "kde"]);
      await until(() => itemOf(tray, kde) != null);
      expect(itemOf(tray, kde)!.isAppIndicator, isFalse);
      expect(await itemOf(tray, kde)!.scroll(-2, TrayScrollOrientation.vertical), isTrue);
      await kde.saw("CALL Scroll 240 vertical");
      expect(await itemOf(tray, kde)!.scroll(1, TrayScrollOrientation.horizontal), isTrue);
      await kde.saw("CALL Scroll -120 horizontal");
      await kde.kill();

      final Client noActivate = await Client.item(["--register", "path", "--id", "ind", "--no-activate"]);
      await until(() => itemOf(tray, noActivate) != null);
      expect(await itemOf(tray, noActivate)!.activate(1, 1), isFalse);
      await noActivate.kill();
    });

    test("the dbusmenu: layout, events, updates, lazy submenus", () async {
      final DBusMenuClient menu = itemOf(tray, a)!.menu!;
      final DBusMenuNode root = (await menu.prepare())!;
      await a.saw("CALL AboutToShow 0");
      expect(root.shownChildren.map((e) => e.id), [1, 2, 3, 4, 7, 9, 11]);
      expect(root.find(1)!.displayLabel, "Show Window");
      expect(root.find(1)!.iconName, "window-new");
      expect(root.find(3)!.toggleType, DBusMenuToggleType.checkmark);
      expect(root.find(3)!.toggleState, isFalse);
      expect(root.find(4)!.children.map((e) => e.toggleState), [true, false]);
      expect(root.find(7)!.enabled, isFalse);
      expect(root.find(9)!.isSubmenu, isTrue);
      expect(root.find(9)!.children, isEmpty);

      menu.opened(0);
      await a.saw("EVENT 0 opened");

      // Clicking a checkmark: the item updates its properties.
      menu.clicked(3);
      await a.saw("EVENT 3 clicked");
      await until(() => menu.root!.find(3)!.toggleState == true, reason: "toggled");

      // Qt fills submenus when they are about to show.
      menu.opened(9);
      await a.saw("CALL AboutToShow 9");
      await until(() => menu.root!.find(10) != null, reason: "lazy entries");

      // Layout changes while open are read right away...
      a.send("addmenu Extra");
      await until(() => menu.root!.find(100) != null, reason: "new entry");

      menu.closed(9);
      menu.closed(0);
      await a.saw("EVENT 0 closed");

      // ...and when closed, the next time it opens.
      a.send("addmenu More");
      await a.saw("DONE addmenu");
      await Future.delayed(const Duration(milliseconds: 200));
      expect(menu.root!.find(101), isNull);
      expect((await menu.prepare())!.find(101), isNotNull);
    });

    test("items leave with their process", () async {
      final Client d = await Client.item(["--register", "name", "--id", "short-lived"]);
      await until(() => itemOf(tray, d) != null);
      final int count = tray.items.length;
      final String name = d.uniqueName;
      await d.kill();
      await until(() => tray.items.length == count - 1, reason: "item gone");
      expect(tray.items.where((e) => e.busName == name), isEmpty);
      expect((await registered(bus)).where((e) => e.contains("short-lived")), isEmpty);
    });

    test("misbehaving items don't break the tray", () async {
      final int count = tray.items.length;
      final Client evil = await Client.item(["--register", "path", "--id", "evil", "--misbehave", "evil"]);
      final Client silent = await Client.item(["--register", "path", "--id", "silent", "--misbehave", "silent"]);

      // Wrong types become defaults.
      await until(() => itemOf(tray, evil) != null, reason: "evil item");
      final TrayItem item = itemOf(tray, evil)!;
      expect(item.status, TrayItemStatus.active);
      expect(item.title, "");
      expect(item.icon.isEmpty, isTrue);
      expect(item.menu, isNull);
      expect(item.itemIsMenu, isFalse);

      // One that never answers isn't shown, and doesn't hold anything up.
      await silent.saw("SWALLOWED GetAll");
      final Client after = await Client.item(["--register", "path", "--id", "after"]);
      await until(() => itemOf(tray, after) != null);
      expect(itemOf(tray, silent), isNull);
      expect(tray.items.length, count + 2);

      await evil.kill();
      await silent.kill();
      await after.kill();
      await until(() => tray.items.length == count);
    });

    test("bad registrations are refused", () async {
      Future<void> registerItem(String value) => bus.callMethod(
            destination: _watcher,
            path: _watcherPath,
            interface: _watcher,
            name: "RegisterStatusNotifierItem",
            values: [DBusString(value)],
          );
      await expectLater(registerItem("org.example.NobodyHere"), throwsA(isA<DBusMethodResponseException>()));
      await expectLater(registerItem("not a name"), throwsA(isA<DBusMethodResponseException>()));
    });
  });

  group("next to another watcher", skip: _skip, () {
    test("registers as a host, then takes over when it leaves", () async {
      final Client watcher = await Client.start("watcher.py");
      expect(watcher.lines.first, startsWith("WATCHER True"));
      final Client early = await Client.item(["--register", "name", "--id", "early", "--reregister"]);
      await early.saw("REGISTERED ${early.lines.firstWhere((l) => l.startsWith("READY")).split(" ")[2]}");

      final TrayService tray = const TrayServiceFactory().build();
      await tray.start();
      await watcher.saw("HOST org.kde.StatusNotifierHost-$pid");
      await until(() => itemOf(tray, early) != null, reason: "item known to the watcher");

      final Client later = await Client.item(["--register", "name", "--id", "later", "--reregister"]);
      await until(() => itemOf(tray, later) != null, reason: "item registered later");

      final String laterEntry = "${later.lines.firstWhere((l) => l.startsWith("READY")).split(" ")[2]}/StatusNotifierItem";
      watcher.send("unregister $laterEntry");
      await until(() => itemOf(tray, later) == null, reason: "unregistered item");

      // kded quits: Pangolin becomes the watcher and keeps its items.
      final String? old = await bus.getNameOwner(_watcher);
      await watcher.kill();
      await until(() => tray.items.length == 2, reason: "items re-registered");
      final String? owner = await bus.getNameOwner(_watcher);
      expect(owner, isNotNull);
      expect(owner, isNot(old));
      expect(await registered(bus), hasLength(2));
      expect(itemOf(tray, early), isNotNull);

      await tray.stop();
      await Client.killAll();
    });

    test("finds the items of a watcher that went away (the shell restarting)", () async {
      final Client orphan = await Client.item(["--register", "none", "--id", "orphan"]);
      final TrayService tray = const TrayServiceFactory().build();
      await tray.start();
      await until(() => itemOf(tray, orphan) != null, reason: "adopted item");
      await tray.stop();
      await Client.killAll();
    });
  });
}
