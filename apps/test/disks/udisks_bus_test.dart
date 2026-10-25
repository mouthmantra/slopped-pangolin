// The Disks app's UDisks layer against the fake UDisks2 (fake_udisks.dart)
// on a private bus: a dbus-daemon of its own, so it needs neither a system
// bus nor real disks. Skipped when dbus-daemon isn't installed.

import 'dart:io';

import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udisks.dart';

const int gib = 1024 * mib;

DBusObjectPath _bp(String name) => DBusObjectPath("/org/freedesktop/UDisks2/block_devices/$name");

void main() {
  final bool haveDaemon = Process.runSync("sh", ["-c", "command -v dbus-daemon"]).exitCode == 0;

  late Directory dir;
  late Process daemon;
  late DBusClient serviceBus;
  late DBusClient appBus;
  late FakeUDisks fake;
  late UDisksClient udisks;

  /// Waits until [udisks] reloaded and [done] holds.
  Future<void> until(bool Function() done) async {
    final DateTime end = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail("timed out waiting for UDisks objects");
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync("disks-bus-test");
    final String socket = "${dir.path}/bus";
    daemon = await Process.start("dbus-daemon", [
      "--session",
      "--nofork",
      "--nopidfile",
      "--address=unix:path=$socket",
    ]);
    for (int i = 0; i < 100 && !File(socket).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    serviceBus = DBusClient(DBusAddress.unix(path: socket));
    fake = FakeUDisks(serviceBus, dataDir: "${dir.path}/data")..jobLength = const Duration(milliseconds: 50);
    await fake.start();
    appBus = DBusClient(DBusAddress.unix(path: socket));
    udisks = UDisksClient(appBus);
    await udisks.start();
  });

  tearDown(() async {
    udisks.dispose();
    await appBus.close();
    await serviceBus.close();
    daemon.kill();
    await daemon.exitCode;
    dir.deleteSync(recursive: true);
  });

  UObject block(String name) => udisks[_bp(name)]!;

  group("UDisks on a private bus", skip: haveDaemon ? false : "dbus-daemon isn't installed", () {
    test("drives in UDisks' order, then loop devices, with their layout", () {
      final List<DriveEntry> entries = udisks.entries;
      expect(entries.map(entryName), ["Samsung SSD 980 PRO 1TB", "WDC WD10EZEX-08WN4A0", "SanDisk Ultra", "backing.img"]);
      expect(entries.map((e) => e.disk?.device), ["/dev/nvme0n1", "/dev/sda", "/dev/sdb", "/dev/loop0"]);
      expect(entries.map(busName), ["NVMe", "SATA", "USB", "Disk image"]);

      final List<Segment> nvme = udisks.layout(entries[0].disk!);
      expect(nvme.map((s) => s.block == null ? "free" : volumeName(s.block!)),
          ["EFI System Partition", "Partition 2", "Partition 3", "free"]);
      expect(volumeName(nvme[2].children.single.block!), "fedora");
      expect(nvme[2].children.single.block!.mountPoints, ["/", "/home"]);
      expect(udisks.contents(entries[2].disk!), "It holds “SANDISK” (17.2 GB FAT).");
    });

    test("property changes reach the client", () async {
      await udisks.call(_bp("sdb1"), iFilesystem, "Mount", [options()], reply: "s");
      await until(() => block("sdb1").mounted);
      expect(block("sdb1").mountPoints, ["/run/media/test/SANDISK"]);
      await udisks.call(_bp("sdb1"), iFilesystem, "Unmount", [options()]);
      await until(() => !block("sdb1").mounted);
    });

    test("unlock: a wrong password reads as UDisks' message, the right one adds the volume", () async {
      Object? error;
      try {
        await udisks.call(_bp("sda3"), iEncrypted, "Unlock", [const DBusString("wrong"), options()], reply: "o");
      } on DBusMethodResponseException catch (e) {
        error = e;
      }
      expect(describeError(error!), contains("Incorrect passphrase"));

      final List<DBusValue> r = await udisks.call(
        _bp("sda3"),
        iEncrypted,
        "Unlock",
        [const DBusString(fakePassphrase), options()],
        reply: "o",
      );
      await until(() => udisks.cleartextOf(block("sda3")) != null);
      expect(udisks.cleartextOf(block("sda3"))!.path, r.first);
      final Segment luks = udisks.layout(block("sda")).firstWhere((s) => s.block?.path == _bp("sda3"));
      expect(volumeName(luks.children.single.block!), "Backup");
    });

    test("create a partition in free space, then delete it", () async {
      final Segment free = udisks.layout(block("sdb")).firstWhere((s) => s.isFree);
      expect(free.offset, 16 * gib + mib);
      final List<DBusValue> r = await udisks.call(
        _bp("sdb"),
        iTable,
        "CreatePartitionAndFormat",
        [
          DBusUint64(free.offset),
          const DBusUint64(gib),
          const DBusString(""),
          const DBusString(""),
          options(),
          const DBusString("ext4"),
          options({"label": const DBusString("Test")}),
        ],
        reply: "o",
      );
      final DBusObjectPath created = r.first as DBusObjectPath;
      await until(() => udisks[created] != null);
      expect(fake.calls.last, startsWith("PartitionTable.CreatePartitionAndFormat sdb ${16 * gib + mib} $gib"));
      expect(udisks.layout(block("sdb")).map((s) => s.block?.label), ["SANDISK", "Test", null]);

      await udisks.call(created, iPartition, "Delete", [options()]);
      await until(() => udisks[created] == null);
    });

    test("a call UDisks' signature doesn't match is refused", () async {
      // The trailing options of most methods don't belong after
      // CreatePartitionAndFormat's format options.
      await expectLater(
        udisks.call(_bp("sdb"), iTable, "CreatePartitionAndFormat", [
          const DBusUint64(16 * gib + mib),
          const DBusUint64(gib),
          const DBusString(""),
          const DBusString(""),
          options(),
          const DBusString("ext4"),
          options(),
          options(),
        ]),
        throwsA(isA<DBusMethodResponseException>()
            .having((e) => e.errorName, "errorName", "org.freedesktop.DBus.Error.InvalidArgs")),
      );
    });

    test("calls allow polkit's prompt; a dismissed prompt is no error", () async {
      // Without the flag polkit can't ask.
      await expectLater(
        DBusRemoteObject(appBus, name: udisksName, path: _bp("sdb1"))
            .callMethod(iFilesystem, "Mount", [options()], replySignature: DBusSignature("s")),
        throwsA(isA<DBusMethodResponseException>()
            .having((e) => e.errorName, "errorName", "org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain")),
      );
      fake.dismiss.add("Filesystem.Mount");
      Object? error;
      try {
        await udisks.call(_bp("sdb1"), iFilesystem, "Mount", [options()], reply: "s");
      } on DBusMethodResponseException catch (e) {
        error = e;
      }
      expect(describeError(error!), isNull);
    });

    test("format runs as a job on the volume", () async {
      // Longer than the client's coalescing of signals.
      fake.jobLength = const Duration(milliseconds: 600);
      final Future<void> format =
          udisks.call(_bp("sdb1"), iBlock, "Format", [const DBusString("exfat"), options()]);
      await until(() => udisks.jobsOn([block("sdb1")]).isNotEmpty);
      expect(udisks.jobsOn([block("sdb1")]).single.str(iJob, "Operation"), "format-mkfs");
      await format;
      await until(() => block("sdb1").idType == "exfat");
      expect(udisks.jobsOn([block("sdb1")]), isEmpty);
    });

    test("mount options: add, change and remove an fstab entry", () async {
      DBusStruct entry(String dir) => DBusStruct([
            const DBusString("fstab"),
            options({
              "fsname": bytestring("UUID=x"),
              "dir": bytestring(dir),
              "type": bytestring("vfat"),
              "opts": bytestring("nofail"),
              "freq": const DBusInt32(0),
              "passno": const DBusInt32(0),
            }),
          ]);
      await udisks.call(_bp("sdb1"), iBlock, "AddConfigurationItem", [entry("/mnt/a"), options()]);
      await until(() => block("sdb1").configuration("fstab") != null);
      expect(block("sdb1").configuration("fstab")!["dir"], "/mnt/a");
      await udisks.call(_bp("sdb1"), iBlock, "UpdateConfigurationItem",
          [block("sdb1").configItem("fstab")!, entry("/mnt/b"), options()]);
      await until(() => block("sdb1").configuration("fstab")?["dir"] == "/mnt/b");
      await udisks.call(_bp("sdb1"), iBlock, "RemoveConfigurationItem", [block("sdb1").configItem("fstab")!, options()]);
      await until(() => block("sdb1").configuration("fstab") == null);
    });

    test("encryption options: the key file's passphrase comes from GetSecretConfiguration", () async {
      final Map<String, Object?> visible = block("nvme0n1p3").configuration("crypttab")!;
      expect(visible["passphrase-path"], "/etc/luks-keys/luks-nvme0n1p3");
      expect(visible.containsKey("passphrase-contents"), isFalse);
      final List<DBusValue> r = await udisks.call(
        _bp("nvme0n1p3"),
        iBlock,
        "GetSecretConfiguration",
        [options()],
        reply: "a(sa{sv})",
      );
      expect(decodeConfiguration(r.first, "crypttab")!["passphrase-contents"], fakePassphrase);
    });

    test("disk images: back up through the passed descriptor, attach a file as a loop device", () async {
      final List<DBusValue> r = await udisks.call(_bp("loop0"), iBlock, "OpenForBackup", [options()], reply: "h");
      final RandomAccessFile device = (r.first as DBusUnixFd).handle.toFile();
      expect(device.lengthSync(), 64 * mib);
      await device.close();

      final File image = File("${dir.path}/new.img");
      image.openSync(mode: FileMode.write)
        ..truncateSync(32 * mib)
        ..closeSync();
      final RandomAccessFile file = image.openSync();
      final List<DBusValue> loop = await udisks.call(
        managerPath,
        iManager,
        "LoopSetup",
        [DBusUnixFd(ResourceHandle.fromFile(file)), options({"read-only": const DBusBoolean(true)})],
        reply: "o",
      );
      file.closeSync();
      await until(() => udisks[loop.first as DBusObjectPath] != null);
      final DriveEntry entry = udisks.entries.last;
      expect((entryName(entry), entry.disk!.size, entry.disk!.readOnly), ("new.img", 32 * mib, true));
    });

    test("SMART: attributes of both kinds of drive, a self-test with progress", () async {
      final UObject hdd = udisks[DBusObjectPath("/org/freedesktop/UDisks2/drives/hdd")]!;
      final List<DBusValue> ata = await udisks.call(hdd.path, iAta, "SmartGetAttributes", [options()]);
      expect((ata.first as DBusArray).children.length, 6);
      final List<DBusValue> nvme = await udisks.call(
          DBusObjectPath("/org/freedesktop/UDisks2/drives/nvme"), iNvme, "SmartGetAttributes", [options()]);
      expect(nvme.first.asStringVariantDict()["percent_used"], const DBusByte(3));

      await udisks.call(hdd.path, iAta, "SmartSelftestStart", [const DBusString("short"), options()]);
      UObject drive() => udisks[hdd.path]!;
      await until(() => drive().str(iAta, "SmartSelftestStatus") == "inprogress");
      await until(() => drive().integer(iAta, "SmartSelftestPercentRemaining") < 90);
      await udisks.call(hdd.path, iAta, "SmartSelftestAbort", [options()]);
      await until(() => drive().str(iAta, "SmartSelftestStatus") == "aborted");
    });
  });
}
