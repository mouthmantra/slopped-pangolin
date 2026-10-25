import 'package:dahlia_apps/apps/disks/dialogs.dart';
import 'package:dahlia_apps/apps/disks/disks.dart';
import 'package:dahlia_apps/apps/disks/smart.dart';
import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dahlia_apps/kit/widgets.dart' show formatDuration;
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

const int gib = 1024 * mib;

DBusObjectPath _p(String name) => DBusObjectPath("/org/freedesktop/UDisks2/block_devices/$name");

UObject _block(
  String name,
  int size, {
  String idType = "",
  String label = "",
  String? table,
  String? tableType,
  int offset = 0,
  int number = 0,
  bool container = false,
  bool contained = false,
  String? backing,
  List<String> mountPoints = const [],
}) =>
    UObject(_p(name), {
      iBlock: {
        "Size": DBusUint64(size),
        "IdType": DBusString(idType),
        "IdUsage": DBusString(idType.isEmpty ? "" : "filesystem"),
        "IdLabel": DBusString(label),
        "Device": bytestring("/dev/$name"),
        "CryptoBackingDevice": backing == null ? DBusObjectPath("/") : _p(backing),
      },
      if (tableType != null) iTable: {"Type": DBusString(tableType)},
      if (table != null)
        iPartition: {
          "Table": _p(table),
          "Number": DBusUint32(number),
          "Offset": DBusUint64(offset),
          "Size": DBusUint64(size),
          "IsContainer": DBusBoolean(container),
          "IsContained": DBusBoolean(contained),
        },
      if (idType == "crypto_LUKS") iEncrypted: <String, DBusValue>{},
      if (idType == "ext4" || idType == "vfat" || idType == "btrfs")
        iFilesystem: {
          "MountPoints": DBusArray(DBusSignature("ay"), [for (final String m in mountPoints) bytestring(m)]),
        },
    });

UDisksClient _client(List<UObject> objects) =>
    UDisksClient(DBusClient(DBusAddress.unix(path: "/nonexistent")))
      ..objects = {for (final UObject o in objects) o.path: o};

/// A Drive.Ata.SmartGetAttributes entry.
DBusStruct _attr(int id, String name, int flags, int value, int worst, int threshold, int pretty, int unit) =>
    DBusStruct([
      DBusByte(id), DBusString(name), DBusUint16(flags), DBusInt32(value), DBusInt32(worst), //
      DBusInt32(threshold), DBusInt64(pretty), DBusInt32(unit), DBusDict.stringVariant({}),
    ]);

void main() {
  group('volume map', () {
    test('GPT: partitions, LUKS contents and trailing free space', () {
      const int size = 100 * 1000 * 1000 * 1000;
      final UDisksClient udisks = _client([
        _block("sda", size, tableType: "gpt"),
        _block("sda1", 512 * mib, idType: "vfat", table: "sda", offset: mib),
        _block("sda2", 50 * gib, idType: "crypto_LUKS", table: "sda", offset: 513 * mib),
        _block("dm_2d0", 50 * gib - 16 * mib, idType: "ext4", backing: "sda2"),
      ]);
      final List<Segment> s = udisks.layout(udisks[_p("sda")]!);
      expect(s.map((x) => x.block?.path.value.split("/").last), ["sda1", "sda2", null]);
      expect(s[1].children.single.block!.path, _p("dm_2d0"));
      // Free space from the end of sda2 (MiB aligned) to the GPT backup area.
      expect(s[2].offset, 513 * mib + 50 * gib);
      expect(s[2].offset + s[2].size, size - mib);
      expect(udisks.blocksOf(udisks[_p("sda")]!).length, 4);
    });

    test('MBR: free space around and inside an extended partition', () {
      const int size = 10 * gib;
      final UDisksClient udisks = _client([
        _block("sdb", size, tableType: "dos"),
        _block("sdb1", gib, idType: "ext4", table: "sdb", offset: mib),
        _block("sdb2", 4 * gib, table: "sdb", offset: 2 * gib, container: true),
        _block("sdb5", gib, idType: "ntfs", table: "sdb", offset: 2 * gib + mib, contained: true),
      ]);
      final List<Segment> s = udisks.layout(udisks[_p("sdb")]!);
      expect(s.length, 4);
      expect([s[0].block?.path, s[1].isFree, s[2].block?.path, s[3].isFree], [_p("sdb1"), true, _p("sdb2"), true]);
      expect((s[1].offset, s[1].size), (gib + mib, gib - mib));
      expect(s[2].children.map((c) => c.block?.path), [_p("sdb5"), null]);
      final Segment inner = s[2].children[1];
      expect((inner.offset, inner.offset + inner.size), (3 * gib + mib, 6 * gib));
      expect((s[3].offset, s[3].offset + s[3].size), (6 * gib, size));
    });

    test('an empty table is all free space after the first MiB', () {
      final UDisksClient udisks = _client([_block("sdc", 8 * gib, tableType: "dos")]);
      final Segment free = udisks.layout(udisks[_p("sdc")]!).single;
      expect((free.isFree, free.offset, free.size), (true, mib, 8 * gib - mib));
    });

    test('slack under a MiB between partitions is not free space', () {
      final UDisksClient udisks = _client([
        _block("sdd", 4 * gib, tableType: "gpt"),
        _block("sdd1", gib - 4096, idType: "ext4", table: "sdd", offset: mib),
        _block("sdd2", gib, idType: "ext4", table: "sdd", offset: gib + mib),
      ]);
      final List<Segment> s = udisks.layout(udisks[_p("sdd")]!);
      expect(s.where((x) => x.isFree).map((x) => x.offset), [2 * gib + mib]);
    });

    test('no partition table: the whole disk is one volume', () {
      final UDisksClient udisks = _client([_block("sdc", 16 * gib, idType: "exfat")]);
      final List<Segment> s = udisks.layout(udisks[_p("sdc")]!);
      expect(s.single.block!.path, _p("sdc"));
      expect(contentName(s.single.block!), "exFAT");
    });
  });

  group('confirmations name the disk and its contents', () {
    final UDisksClient udisks = _client([
      _block("sda", 100 * gib, tableType: "gpt"),
      _block("sda1", 512 * mib, idType: "vfat", table: "sda", offset: mib, number: 1, mountPoints: ["/boot/efi"]),
      _block("sda2", 50 * gib, idType: "crypto_LUKS", table: "sda", offset: 513 * mib, number: 2),
      _block("dm_2d0", 50 * gib - 16 * mib, idType: "ext4", label: "home", backing: "sda2", mountPoints: ["/home"]),
    ]);

    test('a volume, mounted, and what is unlocked inside', () {
      expect(udisks.describe(udisks[_p("sda1")]!), "“Partition 1” (537 MB FAT, mounted at /boot/efi)");
      expect(
        udisks.describe(udisks[_p("sda2")]!),
        "“Partition 2” (53.7 GB LUKS Encryption) holding “home” (53.7 GB Ext4, mounted at /home)",
      );
    });

    test('everything on a disk', () {
      expect(
        udisks.contents(udisks[_p("sda")]!),
        "It holds “Partition 1” (537 MB FAT, mounted at /boot/efi), "
        "“Partition 2” (53.7 GB LUKS Encryption) holding “home” (53.7 GB Ext4, mounted at /home).",
      );
      final UDisksClient empty = _client([_block("sdx", gib, tableType: "dos")]);
      expect(empty.contents(empty[_p("sdx")]!), "It has no partitions.");
      final UDisksClient blank = _client([_block("sdy", gib)]);
      expect(blank.contents(blank[_p("sdy")]!), "It looks empty.");
    });

    test('drive names, buses and volume names', () {
      final UObject drive = UObject(DBusObjectPath("/org/freedesktop/UDisks2/drives/x"), {
        iDrive: {
          "Vendor": const DBusString("Samsung"),
          "Model": const DBusString("SSD 980 PRO 1TB"),
          "ConnectionBus": const DBusString(""),
        },
        iNvme: <String, DBusValue>{},
      });
      expect(entryName(DriveEntry(drive, null)), "Samsung SSD 980 PRO 1TB");
      expect(busName(DriveEntry(drive, null)), "NVMe");
      final UObject usb = UObject(DBusObjectPath("/org/freedesktop/UDisks2/drives/u"), {
        iDrive: {"ConnectionBus": const DBusString("usb"), "Size": const DBusUint64(32 * gib)},
      });
      expect(entryName(DriveEntry(usb, null)), "34.4 GB Drive");
      expect(busName(DriveEntry(usb, null)), "USB");
      final UObject loop = _block("loop3", 64 * mib)
        ..ifaces[iLoop] = {"BackingFile": bytestring("/home/me/Fedora.iso")};
      expect(entryName(DriveEntry(null, loop)), "Fedora.iso");
      expect(busName(DriveEntry(null, loop)), "Disk image");
      expect(volumeName(udisks[_p("dm_2d0")]!), "home");
      expect(volumeName(_block("dm_2d1", gib, backing: "sda2")), "Unlocked volume");
    });
  });

  group('names and units', () {
    test('sizes in decimal units', () {
      expect(formatSize(500107862016), "500 GB");
      expect(formatSize(536870912), "537 MB");
      expect(formatSize(1500), "1.5 kB");
      expect(formatSize(999), "999 bytes");
      expect(formatSize(2000398934016), "2.0 TB");
    });

    test('partition types', () {
      expect(partTypeFor("vfat", "gpt"), "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7");
      expect(partTypeFor("ext4", "gpt"), "");
      expect(partTypeFor("ntfs", "dos"), "0x07");
      expect(partTypeFor("vfat", "dos"), "0x0c");
      expect(partTypeFor("ext4", "dos"), "");
      UObject part(String type) => UObject(_p("p"), {
            iPartition: {"Type": DBusString(type)},
          });
      expect(partTypeName(part("C12A7328-F81F-11D2-BA4B-00A0C93EC93B"), "gpt"), "EFI System");
      expect(partTypeName(part("0x83"), "dos"), "Linux");
      expect(partTypeName(part("0xc"), "dos"), "W95 FAT32 (LBA)");
      expect(partTypeName(part("0x42"), "dos"), "0x42");
    });

    test('content names', () {
      expect(contentName(_block("a", 1, idType: "ext4")), "Ext4");
      expect(contentName(_block("a", 1, idType: "crypto_LUKS")), "LUKS Encryption");
      expect(contentName(_block("a", 1, idType: "zfs_member")), "zfs_member");
      expect(contentName(_block("a", 1, table: "x", container: true)), "Extended Partition");
      expect(contentName(_block("a", 1)), "Unknown");
    });

    test('bytestrings', () {
      expect(decodeBytes([47, 100, 101, 118, 0]), "/dev");
      expect(decodeBytes([47, 100, 101, 118]), "/dev");
      expect(decodeBytes(bytestring("/run/media/émile").asByteArray().toList()), "/run/media/émile");
      expect(bytestring("ab").asByteArray(), [97, 98, 0]);
    });

    test('bytestring and array properties', () {
      final UObject fs = _block("sdd1", gib, idType: "ext4")
        ..ifaces[iFilesystem] = {
          "MountPoints": DBusArray(DBusSignature("ay"), [bytestring("/"), bytestring("/home")]),
        };
      expect(fs.device, "/dev/sdd1");
      expect(fs.mountPoints, ["/", "/home"]);
      expect(fs.mounted, isTrue);
    });

    test('job operations', () {
      expect(jobOperationName("format-mkfs"), "Formatting");
      expect(jobOperationName("ata-smart-selftest"), "Running a self-test");
      expect(jobOperationName("lvm-vg-create"), "lvm vg create");
    });
  });

  group('configuration', () {
    final DBusArray config = DBusArray(DBusSignature("(sa{sv})"), [
      DBusStruct([
        const DBusString("fstab"),
        DBusDict.stringVariant({
          "fsname": bytestring("UUID=1234"),
          "dir": bytestring("/data"),
          "type": bytestring("ext4"),
          "opts": bytestring("nofail,x-gvfs-show"),
          "freq": const DBusInt32(0),
          "passno": const DBusInt32(2),
        }),
      ]),
      DBusStruct([
        const DBusString("crypttab"),
        DBusDict.stringVariant({"name": bytestring("luks-1234"), "passphrase-path": bytestring("")}),
      ]),
    ]);

    test('fstab and crypttab entries decoded', () {
      expect(decodeConfiguration(config, "fstab"), {
        "fsname": "UUID=1234",
        "dir": "/data",
        "type": "ext4",
        "opts": "nofail,x-gvfs-show",
        "freq": 0,
        "passno": 2,
      });
      expect(decodeConfiguration(config, "crypttab")?["name"], "luks-1234");
      expect(decodeConfiguration(DBusArray(DBusSignature("(sa{sv})")), "fstab"), isNull);
      expect(decodeConfiguration(null, "fstab"), isNull);
      // The item exactly as reported, for Update/RemoveConfigurationItem.
      expect(findConfigItem(config, "crypttab"), config.children[1]);
    });

    test('options with their own switches split from the rest', () {
      const Set<String> own = {"noauto", "x-gvfs-show", "x-udisks-auth"};
      final (Set<String> mine, String rest) = splitOptions("defaults,noauto, nofail ,x-gvfs-show,uid=1000", own);
      expect(mine, {"noauto", "x-gvfs-show"});
      expect(rest, "nofail,uid=1000");
      expect(joinOptions(["x-udisks-auth"], rest), "nofail,uid=1000,x-udisks-auth");
      expect(joinOptions(const [], ""), "defaults");
      expect(joinOptions(const [], " , "), "defaults");
    });

    test('format options', () {
      expect(const FormatRequest(type: "ext4", label: "", erase: false).options.keys,
          ["take-ownership", "update-partition-type"]);
      final Map<String, DBusValue> o =
          const FormatRequest(type: "ext4", label: "Backup", erase: true, passphrase: "pw").options;
      expect(o["label"], const DBusString("Backup"));
      expect(o["erase"], const DBusString("zero"));
      expect(o["encrypt.passphrase"], const DBusString("pw"));
      expect(o["encrypt.type"], const DBusString("luks2"));
    });
  });

  group('SMART', () {
    test('ATA attributes: units and assessment', () {
      final List<List<String>> rows = ataAttributeRows(DBusArray(DBusSignature("(ysqiiixia{sv})"), [
        _attr(5, "reallocated-sector-count", 0x33, 200, 200, 140, 8, 3),
        _attr(9, "power-on-hours", 0x32, 61, 61, 0, 3600 * 1000 * 26, 2),
        _attr(194, "temperature-celsius-2", 0x22, 113, 99, 0, 310150, 4),
        _attr(1, "raw-read-error-rate", 0x0b, 40, 40, 51, 0, 1),
        _attr(10, "spin-retry-count", 0x12, 100, 20, 30, 0, 1),
        _attr(12, "power-cycle-count", 0x32, -1, -1, -1, 1520, 1),
      ]));
      expect(rows[0], ["5", "reallocated-sector-count", "8 sectors", "200", "140", "200", "Pre-fail", "OK"]);
      expect(rows[1][2], formatDuration(const Duration(hours: 26)));
      expect(rows[2][2], "37 °C");
      expect(rows[3].last, "FAILING");
      expect((rows[4][6], rows[4].last), ("Old-age", "Failed in the past"));
      expect(rows[5].sublist(3, 6), ["N/A", "N/A", "N/A"]);
    });

    test('NVMe attributes: known values only', () {
      final List<List<String>> rows = nvmeAttributeRows(DBusDict.stringVariant({
        "avail_spare": const DBusByte(100),
        "percent_used": const DBusByte(3),
        "total_data_written": const DBusUint64(29876543210987),
        "unsafe_shutdowns": const DBusUint64(1037),
      }));
      expect(rows, [
        ["Available spare", "100%"],
        ["Life used", "3%"],
        ["Data written", "29.9 TB"],
        ["Unsafe shutdowns", "1,037"],
      ]);
    });

    test('overall assessment', () {
      UObject ata(Map<String, DBusValue> props) => UObject(DBusObjectPath("/d"), {iAta: props});
      expect(
        smartAssessment(ata({
          "SmartEnabled": const DBusBoolean(true),
          "SmartTemperature": const DBusDouble(310.15),
        })),
        "Disk is OK, 37 °C",
      );
      expect(
        smartAssessment(ata({"SmartEnabled": const DBusBoolean(true), "SmartNumBadSectors": const DBusInt64(3)})),
        "Disk is OK, 3 bad sectors",
      );
      expect(
        smartAssessment(ata({"SmartEnabled": const DBusBoolean(true), "SmartFailing": const DBusBoolean(true)})),
        "Disk is failing",
      );
      expect(smartAssessment(ata({"SmartEnabled": const DBusBoolean(false)})), isNull);
      final UObject nvme = UObject(DBusObjectPath("/n"), {
        iNvme: {
          "SmartUpdated": const DBusUint64(1),
          "SmartCriticalWarning": DBusArray.string(["spare", "temperature"]),
          "SmartTemperature": const DBusUint16(350),
        },
      });
      expect(smartAssessment(nvme), "Warning: low spare capacity, temperature, 77 °C");
    });
  });

  group('errors', () {
    DBusMethodResponseException error(String name, [String? message]) => DBusMethodResponseException(
          DBusMethodErrorResponse(name, [if (message != null) DBusString(message)]),
        );

    test('UDisks errors read as their message', () {
      expect(
        describeError(error("org.freedesktop.UDisks2.Error.Failed", "Error unmounting /dev/sda1: target is busy")),
        "Error unmounting /dev/sda1: target is busy",
      );
      expect(describeError(error("org.freedesktop.UDisks2.Error.Failed")), "org.freedesktop.UDisks2.Error.Failed");
    });

    test('a dismissed polkit prompt or a cancelled job is not an error', () {
      expect(describeError(error("org.freedesktop.UDisks2.Error.NotAuthorizedDismissed", "dismissed")), isNull);
      expect(describeError(error("org.freedesktop.UDisks2.Error.Cancelled", "cancelled")), isNull);
    });
  });
}
