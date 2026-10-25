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
import 'dart:math' as math;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

const String udisksName = "org.freedesktop.UDisks2";
const String iDrive = "$udisksName.Drive";
const String iAta = "$udisksName.Drive.Ata";
const String iNvme = "$udisksName.NVMe.Controller";
const String iBlock = "$udisksName.Block";
const String iPartition = "$udisksName.Partition";
const String iTable = "$udisksName.PartitionTable";
const String iFilesystem = "$udisksName.Filesystem";
const String iEncrypted = "$udisksName.Encrypted";
const String iSwap = "$udisksName.Swapspace";
const String iLoop = "$udisksName.Loop";
const String iJob = "$udisksName.Job";
const String iManager = "$udisksName.Manager";

final DBusObjectPath managerPath = DBusObjectPath("/org/freedesktop/UDisks2/Manager");

const int mib = 1024 * 1024;

/// Raw disk image files, offered by Attach and Restore.
const List<String> imageExtensions = ["img", "iso", "raw", "bin"];

/// One object of UDisks2's object manager: its interfaces and properties.
class UObject {
  UObject(this.path, this.ifaces);

  final DBusObjectPath path;
  final Map<String, Map<String, DBusValue>> ifaces;

  bool has(String iface) => ifaces.containsKey(iface);

  Object? get(String iface, String name) => _native(ifaces[iface]?[name]?.toNative());

  // package:dbus gives arrays as lazy Iterables.
  static Object? _native(Object? v) => v is Iterable ? v.map(_native).toList() : v;

  String str(String iface, String name) {
    final Object? v = get(iface, name);
    return v is String ? v : "";
  }

  int integer(String iface, String name) {
    final Object? v = get(iface, name);
    return v is int ? v : v is double ? v.round() : 0;
  }

  bool flag(String iface, String name) => get(iface, name) == true;

  /// A bytestring property (`ay`, NUL terminated).
  String bytes(String iface, String name) {
    final Object? v = get(iface, name);
    return v is List ? decodeBytes(v.cast<int>()) : "";
  }

  DBusObjectPath? ref(String iface, String name) {
    final DBusValue? v = ifaces[iface]?[name];
    return v is DBusObjectPath && v.value != "/" ? v : null;
  }

  List<DBusObjectPath> refs(String iface, String name) {
    final DBusValue? v = ifaces[iface]?[name];
    return v is DBusArray ? v.children.whereType<DBusObjectPath>().toList() : [];
  }

  // Drive.
  String get model => [str(iDrive, "Vendor"), str(iDrive, "Model")]
      .where((s) => s.trim().isNotEmpty)
      .join(" ")
      .trim();

  // Block.
  String get device => bytes(iBlock, "PreferredDevice").isNotEmpty
      ? bytes(iBlock, "PreferredDevice")
      : bytes(iBlock, "Device");
  int get size => has(iPartition) && !has(iBlock)
      ? integer(iPartition, "Size")
      : integer(iBlock, "Size");
  String get idUsage => str(iBlock, "IdUsage");
  String get idType => str(iBlock, "IdType");
  String get label => str(iBlock, "IdLabel");
  DBusObjectPath? get drivePath => ref(iBlock, "Drive");
  DBusObjectPath? get cryptoBacking => ref(iBlock, "CryptoBackingDevice");
  bool get readOnly => flag(iBlock, "ReadOnly");

  // Partition.
  int get number => integer(iPartition, "Number");
  int get offset => integer(iPartition, "Offset");
  String get partType => str(iPartition, "Type");
  String get partName => str(iPartition, "Name");
  int get partFlags => integer(iPartition, "Flags");
  DBusObjectPath? get table => ref(iPartition, "Table");
  bool get isContainer => flag(iPartition, "IsContainer");
  bool get isContained => flag(iPartition, "IsContained");

  /// Filesystem.MountPoints.
  List<String> get mountPoints {
    final Object? v = get(iFilesystem, "MountPoints");
    return v is List
        ? [for (final Object? m in v) if (m is List) decodeBytes(m.cast<int>())]
        : const [];
  }

  bool get mounted => mountPoints.isNotEmpty;

  /// The `fstab` or `crypttab` entry UDisks found for this block, as it
  /// reported it (UDisks matches the whole item to change or remove it).
  DBusStruct? configItem(String kind) => findConfigItem(ifaces[iBlock]?["Configuration"], kind);

  /// [configItem] decoded: bytestrings as strings.
  Map<String, Object?>? configuration(String kind) =>
      decodeConfiguration(ifaces[iBlock]?["Configuration"], kind);
}

/// The [kind] item (`fstab`, `crypttab`) of a Block.Configuration value
/// (`a(sa{sv})`).
DBusStruct? findConfigItem(DBusValue? configuration, String kind) {
  if (configuration is! DBusArray) return null;
  return configuration.children
      .whereType<DBusStruct>()
      .where((item) => item.children.length == 2 && item.children[0] is DBusString)
      .where((item) => (item.children[0] as DBusString).value == kind)
      .firstOrNull;
}

/// The [kind] item of a Block.Configuration value, its bytestrings decoded.
Map<String, Object?>? decodeConfiguration(DBusValue? configuration, String kind) {
  final DBusStruct? item = findConfigItem(configuration, kind);
  if (item == null) return null;
  return {
    for (final MapEntry<String, DBusValue> e in item.children[1].asStringVariantDict().entries)
      e.key: e.value is DBusArray && (e.value as DBusArray).childSignature.value == "y"
          ? decodeBytes(e.value.asByteArray().toList())
          : e.value.toNative(),
  };
}

String decodeBytes(List<int> b) {
  final int end = b.indexOf(0);
  return utf8.decode(end < 0 ? b : b.sublist(0, end), allowMalformed: true);
}

DBusArray bytestring(String s) => DBusArray.byte([...utf8.encode(s), 0]);

DBusDict options([Map<String, DBusValue> values = const {}]) =>
    DBusDict.stringVariant(values);

/// The objects of UDisks2, kept up to date from its signals.
class UDisksClient extends ChangeNotifier {
  UDisksClient(this.bus);

  final DBusClient bus;
  late final DBusRemoteObjectManager _manager = DBusRemoteObjectManager(
    bus,
    name: udisksName,
    path: DBusObjectPath("/org/freedesktop/UDisks2"),
  );
  StreamSubscription<DBusSignal>? _signals;
  Timer? _reload;
  Map<DBusObjectPath, UObject> objects = {};

  Future<void> start() async {
    _signals = _manager.signals.listen((_) => _scheduleReload(), onError: (Object _) {});
    await reload();
  }

  // Signals come in bursts (a job updates several objects): one reload each.
  void _scheduleReload() {
    _reload ??= Timer(const Duration(milliseconds: 50), () {
      _reload = null;
      unawaited(reload().catchError((Object _) {}));
    });
  }

  Future<void> reload() async {
    final Map<DBusObjectPath, Map<String, Map<String, DBusValue>>> all =
        await _manager.getManagedObjects();
    objects = {
      for (final MapEntry<DBusObjectPath, Map<String, Map<String, DBusValue>>> e
          in all.entries)
        e.key: UObject(e.key, e.value),
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _reload?.cancel();
    unawaited(_signals?.cancel());
    super.dispose();
  }

  UObject? operator [](DBusObjectPath? path) => path == null ? null : objects[path];

  Iterable<UObject> withIface(String iface) =>
      objects.values.where((o) => o.has(iface));

  Future<List<DBusValue>> call(
    DBusObjectPath path,
    String iface,
    String method,
    List<DBusValue> args, {
    String? reply,
  }) async {
    final DBusMethodSuccessResponse r =
        await DBusRemoteObject(bus, name: udisksName, path: path).callMethod(
      iface,
      method,
      args,
      replySignature: reply == null ? null : DBusSignature(reply),
      allowInteractiveAuthorization: true,
    );
    return r.values;
  }

  /// Drives, in UDisks' order, followed by set up loop devices.
  List<DriveEntry> get entries => [
        for (final UObject d in withIface(iDrive).toList()
          ..sort((a, b) => a.str(iDrive, "SortKey").compareTo(b.str(iDrive, "SortKey"))))
          DriveEntry(d, wholeBlockOf(d)),
        for (final UObject b in withIface(iLoop).toList()
          ..sort((a, b) => a.device.compareTo(b.device)))
          if (b.has(iBlock) && !b.has(iPartition) && b.size > 0) DriveEntry(null, b),
      ];

  UObject? wholeBlockOf(UObject drive) => withIface(iBlock)
      .where((b) =>
          b.drivePath == drive.path &&
          !b.has(iPartition) &&
          b.cryptoBacking == null)
      .firstOrNull;

  List<UObject> partitionsOf(UObject table) =>
      withIface(iPartition).where((p) => p.table == table.path).toList()
        ..sort((a, b) => a.offset.compareTo(b.offset));

  /// The unlocked device of a LUKS block.
  UObject? cleartextOf(UObject block) =>
      withIface(iBlock).where((b) => b.cryptoBacking == block.path).firstOrNull;

  /// Every block of a drive: the disk, its partitions and what's unlocked
  /// inside them.
  List<UObject> blocksOf(UObject disk) {
    final List<UObject> out = [disk];
    for (int i = 0; i < out.length; i++) {
      final UObject b = out[i];
      if (b.has(iTable)) out.addAll(partitionsOf(b));
      final UObject? clear = cleartextOf(b);
      if (clear != null) out.add(clear);
    }
    return out;
  }

  // Names for messages and confirmations.

  /// “Name” (size type, mounted at /x), and what's unlocked inside.
  String describe(UObject b) {
    final UObject? clear = cleartextOf(b);
    return "“${volumeName(b)}” (${formatSize(b.size)} ${contentName(b)}"
        "${b.mounted ? ", mounted at ${b.mountPoints.first}" : ""})"
        "${clear == null ? "" : " holding ${describe(clear)}"}";
  }

  /// What's on [disk], for the confirmation of something that erases it.
  String contents(UObject disk) {
    if (!disk.has(iTable)) {
      return disk.idUsage.isEmpty ? "It looks empty." : "It holds ${describe(disk)}.";
    }
    final List<UObject> parts = partitionsOf(disk).where((p) => !p.isContainer).toList();
    return parts.isEmpty ? "It has no partitions." : "It holds ${parts.map(describe).join(", ")}.";
  }

  List<UObject> jobsOn(Iterable<UObject> blocks, [UObject? drive]) {
    final Set<DBusObjectPath> paths = {
      for (final UObject b in blocks) b.path,
      if (drive != null) drive.path,
    };
    return withIface(iJob)
        .where((j) => j.refs(iJob, "Objects").any(paths.contains))
        .toList();
  }

  /// The blocks of [disk] laid out as GNOME Disks shows them: partitions and
  /// free space, each with what sits inside it (logical partitions of an
  /// extended partition, the unlocked device of a LUKS volume).
  List<Segment> layout(UObject disk) {
    if (disk.has(iTable)) {
      final bool gpt = disk.str(iTable, "Type") == "gpt";
      final List<UObject> parts = partitionsOf(disk);
      // The first MiB holds the partition table (and an extended
      // partition's first MiB its boot record): never free space.
      return _fill(
        parts.where((p) => !p.isContained).toList(),
        start: mib,
        // GPT keeps its backup header in the last sectors.
        end: gpt ? disk.size - mib : disk.size,
        inner: (p) => p.isContainer
            ? _fill(
                parts.where((c) => c.isContained).toList(),
                start: p.offset + mib,
                end: p.offset + p.size,
                inner: _inside,
              )
            : _inside(p),
      );
    }
    return [Segment(disk, disk.size, children: _inside(disk))];
  }

  List<Segment> _inside(UObject block) {
    final UObject? clear = cleartextOf(block);
    return clear == null ? const [] : [Segment(clear, clear.size, children: _inside(clear))];
  }

  static List<Segment> _fill(
    List<UObject> parts, {
    required int start,
    required int end,
    required List<Segment> Function(UObject) inner,
  }) {
    final List<Segment> out = [];
    int at = start;
    void gap(int to) {
      // Free space starts on a MiB boundary (as partitions are aligned);
      // anything under a MiB is alignment slack, not free space.
      final int from = (at + mib - 1) ~/ mib * mib;
      if (to - from >= mib) out.add(Segment.free(from, to - from));
    }

    for (final UObject p in parts) {
      gap(p.offset);
      out.add(Segment(p, p.size, children: inner(p)));
      at = math.max(at, p.offset + p.size);
    }
    gap(end);
    return out;
  }
}

/// One entry of the drive list: a drive (with its disk when there's media),
/// or a loop device without a drive.
class DriveEntry {
  const DriveEntry(this.drive, this.disk);

  final UObject? drive;
  final UObject? disk;

  DBusObjectPath get path => (drive ?? disk)!.path;
}

/// The drive's model, a loop device's image file, or its size.
String entryName(DriveEntry e) {
  final String model = e.drive?.model ?? "";
  if (model.isNotEmpty) return model;
  if (e.drive == null && e.disk != null) {
    final String file = e.disk!.bytes(iLoop, "BackingFile");
    return file.isEmpty ? e.disk!.device : file.split("/").last;
  }
  return "${formatSize(entrySize(e))} Drive";
}

int entrySize(DriveEntry e) => e.disk?.size ?? e.drive?.integer(iDrive, "Size") ?? 0;

/// How the drive is connected ("NVMe", "USB", "SATA"…).
String busName(DriveEntry e) {
  final UObject? d = e.drive;
  if (d == null) return "Disk image";
  if (d.has(iNvme)) return "NVMe";
  return switch (d.str(iDrive, "ConnectionBus")) {
    "usb" => "USB",
    "sdio" => "SD card",
    "ieee1394" => "FireWire",
    "" => d.has(iAta) ? "SATA" : "",
    final String bus => bus.toUpperCase(),
  };
}

/// A volume's label, partition name or number.
String volumeName(UObject b) {
  if (b.label.isNotEmpty) return b.label;
  if (b.partName.isNotEmpty) return b.partName;
  if (b.has(iPartition)) return "Partition ${b.number}";
  if (b.cryptoBacking != null) return "Unlocked volume";
  return "Volume";
}

/// A piece of the volume map: a block, or free space at [offset].
class Segment {
  const Segment(this.block, this.size, {this.children = const []}) : offset = 0;
  const Segment.free(this.offset, this.size)
      : block = null,
        children = const [];

  final UObject? block;
  final int offset;
  final int size;
  final List<Segment> children;

  bool get isFree => block == null;
}

/// Decimal units, as drives are sold and GNOME Disks shows them.
String formatSize(int bytes) {
  const List<String> units = ["bytes", "kB", "MB", "GB", "TB", "PB"];
  double v = bytes.toDouble();
  int u = 0;
  while (v >= 1000 && u < units.length - 1) {
    v /= 1000;
    u++;
  }
  if (u == 0) return "$bytes bytes";
  return "${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[u]}";
}

/// Readable name of a filesystem or other content type (Block.IdType).
String contentName(UObject b) {
  final String t = b.idType;
  return switch (t) {
    "ext2" || "ext3" || "ext4" => "Ext${t.substring(3)}",
    "vfat" => "FAT",
    "exfat" => "exFAT",
    "ntfs" => "NTFS",
    "btrfs" => "Btrfs",
    "xfs" => "XFS",
    "f2fs" => "F2FS",
    "iso9660" => "ISO 9660",
    "udf" => "UDF",
    "swap" => "Swap",
    "crypto_LUKS" => "LUKS Encryption",
    "LVM2_member" => "LVM2 Physical Volume",
    "linux_raid_member" => "RAID Member",
    "hfsplus" => "HFS+",
    "apfs" => "APFS",
    "" => b.has(iPartition) && b.isContainer ? "Extended Partition" : "Unknown",
    _ => t,
  };
}

/// Partition types offered in Edit Partition, by table type.
const Map<String, String> gptTypes = {
  "0fc63daf-8483-4772-8e79-3d69d8477de4": "Linux Filesystem",
  "933ac7e1-2eb4-4f13-b844-0e14e2aef915": "Linux Home",
  "4f68bce3-e8cd-4db1-96e7-fbcaf984b709": "Linux Root (x86-64)",
  "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f": "Linux Swap",
  "e6d6d379-f507-44c2-a23c-238f2a3df928": "Linux LVM",
  "a19d880f-05fc-4d3b-a006-743f0f84911e": "Linux RAID",
  "ca7d7ccb-63ed-4c53-861c-1742536059cc": "Linux LUKS",
  "c12a7328-f81f-11d2-ba4b-00a0c93ec93b": "EFI System",
  "21686148-6449-6e6f-744e-656564454649": "BIOS Boot",
  "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7": "Microsoft Basic Data",
  "e3c9e316-0b5c-4db8-817d-f92df00215ae": "Microsoft Reserved",
  "de94bba4-06d1-4d40-a16a-bfd50179d6ac": "Windows Recovery",
  "48465300-0000-11aa-aa11-00306543ecac": "Apple HFS/HFS+",
  "7c3457ef-0000-11aa-aa11-00306543ecac": "Apple APFS",
};

const Map<String, String> dosTypes = {
  "0x83": "Linux",
  "0x82": "Linux Swap",
  "0x8e": "Linux LVM",
  "0xfd": "Linux RAID Autodetect",
  "0x07": "HPFS/NTFS/exFAT",
  "0x0c": "W95 FAT32 (LBA)",
  "0x0b": "W95 FAT32",
  "0x0e": "W95 FAT16 (LBA)",
  "0xef": "EFI (FAT-12/16/32)",
  "0x05": "Extended",
  "0x0f": "W95 Extended (LBA)",
};

String partTypeName(UObject p, String tableType) {
  final String t = p.partType.toLowerCase();
  final Map<String, String> names = tableType == "gpt" ? gptTypes : dosTypes;
  return names[t] ?? names["0x${t.replaceFirst("0x", "").padLeft(2, "0")}"] ?? t;
}

/// Partition type for a new filesystem: Windows types for what Windows
/// reads, Linux otherwise.
String partTypeFor(String fsType, String tableType) {
  final bool windows = const {"vfat", "ntfs", "exfat"}.contains(fsType);
  if (tableType == "gpt") {
    return windows ? "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7" : "";
  }
  return switch (fsType) {
    "vfat" => "0x0c",
    "ntfs" || "exfat" => "0x07",
    _ => "",
  };
}

/// A UDisks error as one readable line (polkit dismissals are null: the
/// user cancelled, nothing to report).
String? describeError(Object e) {
  if (e is DBusMethodResponseException) {
    if (e.errorName.endsWith(".NotAuthorizedDismissed") ||
        e.errorName.endsWith(".Cancelled")) {
      return null;
    }
    final DBusValue? message = e.response.values.firstOrNull;
    return message is DBusString ? message.value : e.errorName;
  }
  return "$e";
}
