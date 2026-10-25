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
import 'dart:io';
import 'dart:math' as math;

import 'package:dahlia_apps/apps/disks/dialogs.dart';
import 'package:dahlia_apps/apps/disks/imaging.dart';
import 'package:dahlia_apps/apps/disks/smart.dart';
import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;
import 'package:dbus/dbus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

final DahliaAppSpec disksApp = DahliaAppSpec(
  name: "disks",
  title: "Disks",
  builder: (context, args) => const DisksPage(),
);

/// Drives and their volumes over UDisks2, with GNOME Disks' feature set.
/// UDisks asks polkit for whatever needs authorization.
class DisksPage extends StatefulWidget {
  const DisksPage({super.key});

  @override
  State<DisksPage> createState() => _DisksPageState();
}

class _DisksPageState extends State<DisksPage> {
  DBusClient? _bus;
  UDisksClient? _udisks;
  bool _loading = true;
  String? _error;
  DBusObjectPath? _entryPath;
  DBusObjectPath? _volume;
  int? _free;

  UDisksClient get udisks => _udisks!;

  @override
  void initState() {
    super.initState();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    final UDisksClient client = UDisksClient(_bus = DBusClient.system());
    try {
      await client.start().timeout(const Duration(seconds: 5));
    } on Object {
      client.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "The disk service (UDisks) isn't running on this system.";
        });
      }
      return;
    }
    client.addListener(_changed);
    if (mounted) {
      setState(() {
        _udisks = client;
        _loading = false;
      });
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _udisks?.removeListener(_changed);
    _udisks?.dispose();
    unawaited(_bus?.close());
    super.dispose();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// Runs [op], reporting a failure as "[what]: reason".
  Future<void> _run(String what, Future<void> Function() op) async {
    try {
      await op();
    } on Object catch (e) {
      final String? reason = e is FileSystemException
          ? e.osError?.message ?? e.message
          : describeError(e);
      if (reason != null && mounted) _toast("$what: $reason");
    }
  }

  /// A UDisks method with its trailing options argument.
  Future<List<DBusValue>> _call(
    UObject o,
    String iface,
    String method, [
    List<DBusValue> args = const [],
    Map<String, DBusValue> opts = const {},
    String? reply,
  ]) =>
      udisks.call(o.path, iface, method, [...args, options(opts)], reply: reply);

  /// Unmounts, stops swap and locks everything inside [root], innermost
  /// first, so it can be formatted, deleted or written.
  Future<void> _release(UObject root) async {
    for (final UObject b in udisks.blocksOf(root).reversed) {
      if (b.mounted) await _call(b, iFilesystem, "Unmount");
      if (b.flag(iSwap, "Active")) await _call(b, iSwap, "Stop");
      if (b.has(iEncrypted) && udisks.cleartextOf(b) != null) {
        await _call(b, iEncrypted, "Lock");
      }
    }
  }

  // Drive actions.

  Future<void> _formatDisk(DriveEntry e) async {
    final UObject disk = e.disk!;
    final (String, bool)? choice = await showDialog<(String, bool)>(
      context: context,
      builder: (context) => FormatDiskDialog(
        message: "Everything on ${entryName(e)} (${formatSize(disk.size)}) will be "
            "erased. ${udisks.contents(disk)}",
      ),
    );
    if (choice == null) return;
    await _run("Couldn't format the disk", () async {
      await _release(disk);
      await _call(disk, iBlock, "Format", [DBusString(choice.$1)], {
        if (choice.$2) "erase": const DBusString("zero"),
      });
    });
  }

  Future<void> _eject(DriveEntry e, {required bool powerOff}) async {
    await _run(powerOff ? "Couldn't power off" : "Couldn't eject", () async {
      if (e.disk != null) await _release(e.disk!);
      if (e.drive == null) {
        await _call(e.disk!, iLoop, "Delete");
      } else {
        await _call(e.drive!, iDrive, powerOff ? "PowerOff" : "Eject");
      }
    });
  }

  Future<void> _driveSettings(UObject drive) async {
    final Map<String, Object?>? config = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => DriveSettingsDialog(drive: drive),
    );
    if (config == null) return;
    await _run("Couldn't change the drive settings", () async {
      await _call(drive, iDrive, "SetConfiguration", [
        options({
          for (final MapEntry<String, Object?> c in config.entries)
            c.key: c.value is bool ? DBusBoolean(c.value! as bool) : DBusInt32(c.value! as int),
        }),
      ]);
    });
  }

  // Volume actions.

  Future<void> _mount(UObject b, bool mount) => _run(
        mount ? "Couldn't mount" : "Couldn't unmount",
        () => _call(b, iFilesystem, mount ? "Mount" : "Unmount"),
      );

  Future<void> _unlock(UObject b) async {
    final String? passphrase = await askText(
      context,
      title: "Unlock ${volumeName(b)}",
      label: "Password",
      action: "Unlock",
      secret: true,
    );
    if (passphrase == null) return;
    await _run("Couldn't unlock", () => _call(b, iEncrypted, "Unlock", [DBusString(passphrase)], {}, "o"));
  }

  Future<void> _lock(UObject b) => _run("Couldn't lock", () async {
        final UObject? clear = udisks.cleartextOf(b);
        if (clear != null) await _release(clear);
        await _call(b, iEncrypted, "Lock");
      });

  Future<void> _delete(DriveEntry e, UObject p) async {
    if (!await confirmDestructive(
      context,
      title: "Delete Partition",
      message: "Delete ${udisks.describe(p)} from ${entryName(e)}? Everything on it will be lost.",
      action: "Delete",
    )) {
      return;
    }
    await _run("Couldn't delete the partition", () async {
      await _release(p);
      await _call(p, iPartition, "Delete");
    });
  }

  Future<void> _format(DriveEntry e, UObject b) async {
    final FormatRequest? request = await showDialog<FormatRequest>(
      context: context,
      builder: (context) => FormatDialog(
        udisks: udisks,
        title: "Format Volume",
        action: "Format",
        message: "Everything on ${udisks.describe(b)} on ${entryName(e)} will be erased.",
      ),
    );
    if (request == null) return;
    await _run("Couldn't format", () async {
      await _release(b);
      await _call(b, iBlock, "Format", [DBusString(request.type)], request.options);
    });
  }

  Future<void> _create(UObject disk, Segment free) async {
    final String table = disk.str(iTable, "Type");
    // MBR holds four partitions; more go inside one extended partition.
    final bool insideExtended = udisks
        .partitionsOf(disk)
        .any((p) => p.isContainer && p.offset <= free.offset && free.offset < p.offset + p.size);
    final bool canExtend = table == "dos" &&
        !insideExtended &&
        !udisks.partitionsOf(disk).any((p) => p.isContainer);
    final FormatRequest? request = await showDialog<FormatRequest>(
      context: context,
      builder: (context) => FormatDialog(
        udisks: udisks,
        title: "Create Partition",
        action: "Create",
        maxSize: free.size,
        offerExtended: canExtend,
      ),
    );
    if (request == null) return;
    await _run("Couldn't create the partition", () async {
      final List<DBusValue> created;
      if (request.type == extendedPartition) {
        created = await _call(disk, iTable, "CreatePartition", [
          DBusUint64(free.offset),
          DBusUint64(request.size!),
          const DBusString("0x05"),
          const DBusString(""),
        ], {
          "partition-type": const DBusString("extended"),
        }, "o");
      } else {
        // (ttssa{sv}sa{sv}): the format options come last, not the usual
        // trailing options.
        created = await udisks.call(
          disk.path,
          iTable,
          "CreatePartitionAndFormat",
          [
            DBusUint64(free.offset),
            DBusUint64(request.size!),
            DBusString(partTypeFor(request.type, table)),
            DBusString(table == "gpt" ? request.label : ""),
            options(),
            DBusString(request.type),
            options(request.options),
          ],
          reply: "o",
        );
      }
      // The new partition is selected once UDisks lists it.
      if (mounted) {
        setState(() {
          _volume = created.first as DBusObjectPath;
          _free = null;
        });
      }
    });
  }

  Future<void> _editPartition(UObject disk, UObject p) async {
    final (String, String, int)? edit = await showDialog<(String, String, int)>(
      context: context,
      builder: (context) =>
          EditPartitionDialog(partition: p, tableType: disk.str(iTable, "Type")),
    );
    if (edit == null) return;
    await _run("Couldn't change the partition", () async {
      if (edit.$1 != p.partType.toLowerCase()) {
        await _call(p, iPartition, "SetType", [DBusString(edit.$1)]);
      }
      if (edit.$2 != p.partName && disk.str(iTable, "Type") == "gpt") {
        await _call(p, iPartition, "SetName", [DBusString(edit.$2)]);
      }
      if (edit.$3 != p.partFlags) {
        await _call(p, iPartition, "SetFlags", [DBusUint64(edit.$3)]);
      }
    });
  }

  Future<void> _rename(UObject b) async {
    final String? label = await askText(
      context,
      title: "Edit Filesystem",
      label: "Label",
      action: "Change",
      initial: b.label,
    );
    if (label == null) return;
    await _run("Couldn't change the label", () => _call(b, iFilesystem, "SetLabel", [DBusString(label)]));
  }

  Future<void> _takeOwnership(UObject b) async {
    final bool? recursive = await showDialog<bool>(
      context: context,
      builder: (context) => TakeOwnershipDialog(volume: udisks.describe(b)),
    );
    if (recursive == null) return;
    await _run(
      "Couldn't take ownership",
      () => _call(b, iFilesystem, "TakeOwnership", [], {"recursive": DBusBoolean(recursive)}),
    );
  }

  Future<void> _changePassphrase(UObject b) async {
    final (String, String)? change = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const ChangePassphraseDialog(),
    );
    if (change == null) return;
    await _run(
      "Couldn't change the password",
      () => _call(b, iEncrypted, "ChangePassphrase", [DBusString(change.$1), DBusString(change.$2)]),
    );
  }

  Future<int> _used(String mountPoint) async {
    final ProcessResult r = await Process.run("df", ["-B1", "--output=used", mountPoint]);
    return int.tryParse(r.stdout.toString().trim().split("\n").last.trim()) ?? 0;
  }

  /// What the resize tool of [fs]'s type can do: Manager.CanResize's flags
  /// (2 shrink and 4 grow unmounted, 8 shrink and 16 grow mounted).
  Future<int> _resizeMode(UObject fs) async {
    final List<DBusValue> r = await udisks.call(
      managerPath,
      iManager,
      "CanResize",
      [DBusString(fs.idType)],
      reply: "(bts)",
    );
    final List<DBusValue> v = (r.first as DBusStruct).children;
    if (!(v[0] as DBusBoolean).value) {
      throw FileSystemException("Resizing ${contentName(fs)} needs ${(v[2] as DBusString).value}");
    }
    return (v[1] as DBusUint64).value;
  }

  /// Resizes a partition with what's in it: the filesystem, or the LUKS
  /// volume and the filesystem inside it (grown after the partition, shrunk
  /// before it).
  Future<void> _resize(List<Segment> row, UObject p) async {
    await _run("Couldn't resize", () async {
      final bool encrypted = p.has(iEncrypted);
      final UObject? clear = encrypted ? udisks.cleartextOf(p) : null;
      if (encrypted && clear == null) {
        throw FileSystemException("Unlock ${volumeName(p)} to resize it");
      }
      // The block with the filesystem, and what the LUKS header takes.
      final UObject inner = clear ?? p;
      final int overhead = p.size - inner.size;
      final bool hasFs = inner.has(iFilesystem);
      int mode = 2 | 4; // Without a filesystem only the containers change.
      if (hasFs) {
        mode = await _resizeMode(inner);
      } else if (inner.idUsage.isNotEmpty) {
        throw FileSystemException("${contentName(inner)} volumes can't be resized here");
      }
      final int index = row.indexWhere((s) => s.block?.path == p.path);
      final Segment? next = index + 1 < row.length ? row[index + 1] : null;
      final int room = next != null && next.isFree ? next.offset + next.size - (p.offset + p.size) : 0;
      // shortcut: an unmounted filesystem's used space is unknown, so the
      // resize tool refuses a size below it; mount it to see the minimum.
      final int min = mode & (2 | 8) == 0
          ? p.size
          : math.max(mib, (inner.mounted ? await _used(inner.mountPoints.first) : mib) + overhead);
      final int max = mode & (4 | 16) == 0 ? p.size : p.size + room;
      if (min >= max) throw FileSystemException("${volumeName(p)} can't be made smaller or larger");
      if (!mounted) return;
      final int? chosen = await showDialog<int>(
        context: context,
        builder: (context) => ResizeDialog(current: p.size, min: min, max: max),
      );
      if (chosen == null) return;
      final int size = chosen ~/ mib * mib;
      final bool grow = size > p.size;
      // LUKS2 keeps the volume key in the kernel keyring: resizing needs
      // the passphrase again.
      String? passphrase;
      if (encrypted && p.str(iBlock, "IdVersion").startsWith("2")) {
        if (!mounted) return;
        passphrase = await askText(
          context,
          title: "Resize ${volumeName(p)}",
          label: "Password",
          action: "Resize",
          secret: true,
          message: "Resizing the encrypted volume needs its password.",
        );
        if (passphrase == null) return;
      }
      final Map<String, DBusValue> crypt = {
        if (passphrase != null) "passphrase": DBusString(passphrase),
      };
      final bool online = mode & (grow ? 16 : 8) != 0;
      final bool offline = mode & (grow ? 4 : 2) != 0;
      final bool wasMounted = inner.mounted;
      if (hasFs && wasMounted && !online) await _call(inner, iFilesystem, "Unmount");
      if (hasFs && !wasMounted && !offline) await _call(inner, iFilesystem, "Mount");
      if (grow) {
        await _call(p, iPartition, "Resize", [DBusUint64(size)]);
        if (encrypted) await _call(p, iEncrypted, "Resize", [const DBusUint64(0)], crypt);
        if (hasFs) await _call(inner, iFilesystem, "Resize", [const DBusUint64(0)]);
      } else {
        if (hasFs) await _call(inner, iFilesystem, "Resize", [DBusUint64(size - overhead)]);
        if (encrypted) await _call(p, iEncrypted, "Resize", [DBusUint64(size - overhead)], crypt);
        await _call(p, iPartition, "Resize", [DBusUint64(size)]);
      }
      if (hasFs && wasMounted && !online) await _call(inner, iFilesystem, "Mount");
      if (hasFs && !wasMounted && !offline) await _call(inner, iFilesystem, "Unmount");
    });
  }

  /// Manager.CanCheck or CanRepair: throws naming the missing program.
  Future<void> _canCheck(UObject fs, {required bool repair}) async {
    final List<DBusValue> r = await udisks.call(
      managerPath,
      iManager,
      repair ? "CanRepair" : "CanCheck",
      [DBusString(fs.idType)],
      reply: "(bs)",
    );
    final List<DBusValue> v = (r.first as DBusStruct).children;
    if (!(v[0] as DBusBoolean).value) {
      final String needs = (v[1] as DBusString).value;
      throw FileSystemException(
        needs.isEmpty
            ? "${contentName(fs)} can't be ${repair ? "repaired" : "checked"}"
            : "${repair ? "Repairing" : "Checking"} ${contentName(fs)} needs $needs",
      );
    }
  }

  Future<void> _check(UObject b, {required bool repair}) async {
    if (repair &&
        !await confirmDestructive(
          context,
          title: "Repair Filesystem",
          message: "Repairing ${udisks.describe(b)} can lose data in damaged files. "
              "Back it up first if you can.",
          action: "Repair",
        )) {
      return;
    }
    await _run(repair ? "Couldn't repair" : "Couldn't check", () async {
      await _canCheck(b, repair: repair);
      final bool wasMounted = b.mounted;
      if (wasMounted) await _call(b, iFilesystem, "Unmount");
      final List<DBusValue> r = await _call(b, iFilesystem, repair ? "Repair" : "Check", [], {}, "b");
      if (wasMounted) await _call(b, iFilesystem, "Mount");
      final bool ok = (r.first as DBusBoolean).value;
      if (mounted) {
        _toast(switch ((repair, ok)) {
          (false, true) => "${volumeName(b)} has no errors",
          (false, false) => "${volumeName(b)} has errors: repair it",
          (true, true) => "${volumeName(b)} was repaired",
          (true, false) => "${volumeName(b)} couldn't be repaired",
        });
      }
    });
  }

  /// The passphrase in the key file of [b]'s crypttab entry. UDisks deletes
  /// an entry's key file when it changes the entry and writes the new one
  /// from the passphrase it's given, so it has to be read first (polkit asks
  /// for an administrator). Null when there's no key file; throws when it
  /// can't be read.
  Future<String?> _crypttabSecret(UObject b) async {
    final String path = b.configuration("crypttab")?["passphrase-path"] as String? ?? "";
    if (path.isEmpty) return null;
    final List<DBusValue> r = await _call(b, iBlock, "GetSecretConfiguration", [], {}, "a(sa{sv})");
    final Map<String, Object?>? secret = decodeConfiguration(r.first, "crypttab");
    final Object? contents = secret?["passphrase-contents"];
    if (contents is! String) throw FileSystemException("Couldn't read the key file $path");
    return contents;
  }

  Future<void> _configure(UObject b, String kind) async {
    String? secret;
    if (kind == "crypttab") {
      try {
        secret = await _crypttabSecret(b);
      } on Object catch (e) {
        final String? reason = e is FileSystemException ? e.message : describeError(e);
        if (reason != null && mounted) _toast("Couldn't read the encryption options: $reason");
        return;
      }
    }
    if (!mounted) return;
    final (Map<String, String>?,)? result = await showDialog<(Map<String, String>?,)>(
      context: context,
      builder: (context) => kind == "fstab"
          ? MountOptionsDialog(block: b)
          : EncryptionOptionsDialog(block: b, passphrase: secret),
    );
    if (result == null) return;
    final DBusStruct? old = b.configItem(kind);
    final Map<String, String>? fields = result.$1;
    await _run("Couldn't save the options", () async {
      if (fields == null) {
        if (old != null) await _call(b, iBlock, "RemoveConfigurationItem", [old]);
        return;
      }
      final DBusStruct item = DBusStruct([
        DBusString(kind),
        options({
          for (final MapEntry<String, String> f in fields.entries) f.key: bytestring(f.value),
          // Dump and fsck order stay as they were (0 for a new entry).
          if (kind == "fstab") ...{
            "freq": DBusInt32(b.configuration(kind)?["freq"] as int? ?? 0),
            "passno": DBusInt32(b.configuration(kind)?["passno"] as int? ?? 0),
          },
        }),
      ]);
      await (old == null
          ? _call(b, iBlock, "AddConfigurationItem", [item])
          : _call(b, iBlock, "UpdateConfigurationItem", [old, item]));
    });
  }

  String _imageName(DriveEntry e, UObject b) {
    final String stamp = DateFormat("yyyy-MM-dd HHmm").format(DateTime.now());
    final String name = b.has(iPartition) || b.cryptoBacking != null
        ? volumeName(b)
        : p.basenameWithoutExtension(entryName(e));
    return "$name ($stamp)".replaceAll("/", "-");
  }

  Future<void> _createImage(DriveEntry e, UObject b) =>
      _run("Couldn't create the image", () => createImage(context, udisks, b, _imageName(e, b)));

  Future<void> _restoreImage(DriveEntry e, UObject b) => _run("Couldn't restore the image", () async {
        final bool done = await restoreImage(
          context,
          udisks,
          b,
          target: b.has(iPartition) ? "${udisks.describe(b)} on ${entryName(e)}" : "${entryName(e)}. ${udisks.contents(b)}",
          prepare: () => _release(b),
        );
        if (!done && mounted) _toast("Restore stopped: ${entryName(e)} is only partly written");
      });

  Future<void> _benchmark(DriveEntry e, UObject b) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => BenchmarkDialog(
          udisks: udisks,
          block: b,
          name: b.has(iPartition) ? volumeName(b) : entryName(e),
        ),
      );

  // Disk images.

  /// Attach Disk Image: sets up a loop device for an image file.
  Future<void> _attachImage() async {
    final String? path = await showFileDialog(
      context,
      title: "Attach Disk Image",
      extensions: imageExtensions,
    );
    if (path == null || !mounted) return;
    final bool? readOnly = await showDialog<bool>(
      context: context,
      builder: (context) => AttachImageDialog(name: p.basename(path)),
    );
    if (readOnly == null) return;
    await _run("Couldn't attach the image", () => _loopSetup(path, readOnly: readOnly));
  }

  /// New Disk Image: an empty image file of a chosen size, attached.
  Future<void> _newImage() async {
    final (String, int)? image = await showDialog<(String, int)>(
      context: context,
      builder: (context) => const NewImageDialog(),
    );
    if (image == null || !mounted) return;
    final String? path = await showFileDialog(
      context,
      mode: FileDialogMode.save,
      title: "New Disk Image",
      suggestedName: "${image.$1}.img",
    );
    if (path == null) return;
    await _run("Couldn't create the image", () async {
      // Sparse: the space is taken only as it gets written.
      final RandomAccessFile file = await File(path).open(mode: FileMode.write);
      try {
        await file.truncate(image.$2);
      } finally {
        await file.close();
      }
      await _loopSetup(path, readOnly: false);
    });
  }

  /// Manager.LoopSetup on [path], selecting the new loop device.
  Future<void> _loopSetup(String path, {required bool readOnly}) async {
    final RandomAccessFile file =
        await File(path).open(mode: readOnly ? FileMode.read : FileMode.append);
    try {
      final List<DBusValue> r = await udisks.call(
        managerPath,
        iManager,
        "LoopSetup",
        [
          DBusUnixFd(ResourceHandle.fromFile(file)),
          options({"read-only": DBusBoolean(readOnly)}),
        ],
        reply: "o",
      );
      if (mounted) {
        setState(() {
          _entryPath = r.first as DBusObjectPath;
          _volume = null;
          _free = null;
        });
      }
    } finally {
      // UDisks keeps its own descriptor.
      await file.close();
    }
  }

  void _select(DriveEntry e) => setState(() {
        _entryPath = e.path;
        _volume = null;
        _free = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const DahliaScaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return DahliaScaffold(
        body: EmptyState(icon: Icons.storage_rounded, title: "Disks aren't available", subtitle: _error),
      );
    }
    final List<DriveEntry> entries = udisks.entries;
    final DriveEntry? entry =
        entries.where((e) => e.path == _entryPath).firstOrNull ?? entries.firstOrNull;
    // The drive list continues the title bar, as Settings' rail does.
    return ListenableBuilder(
      listenable: Listenable.merge([ZenitBlur.state, PreferencesService.current]),
      builder: (context, _) => DahliaScaffold(
        titlebarColor: DahliaRail.colorOf(context),
        titlebarLeading: [
          PopupMenuButton<VoidCallback>(
            tooltip: "Disk images",
            icon: const Icon(Icons.add_rounded),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(value: _attachImage, child: const Text("Attach Disk Image…")),
              PopupMenuItem(value: _newImage, child: const Text("New Disk Image…")),
            ],
          ),
        ],
        titlebarActions: entry == null ? const [] : _driveActions(entry),
        body: Row(
          children: [
            _DriveList(
              children: [
                for (final DriveEntry e in entries)
                  _DriveTile(
                    icon: _driveIcon(e),
                    title: entryName(e),
                    subtitle: entrySize(e) > 0
                        ? [formatSize(entrySize(e)), busName(e)].where((s) => s.isNotEmpty).join(" · ")
                        : "No media",
                    selected: e.path == entry?.path,
                    onTap: () => _select(e),
                  ),
              ],
            ),
            Expanded(
              child: entry == null
                  ? const EmptyState(
                      icon: Icons.storage_rounded,
                      title: "No drives",
                      subtitle: "Attach a disk image with + in the title bar",
                    )
                  : KeyedSubtree(key: ValueKey(entry.path), child: _drivePage(entry)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _driveIcon(DriveEntry e) {
    final UObject? d = e.drive;
    if (d == null) return Icons.insert_drive_file_rounded;
    final Object? media = d.get(iDrive, "MediaCompatibility");
    final List<String> compat = media is List ? media.cast<String>() : const [];
    if (compat.any((m) => m.startsWith("optical"))) return Icons.album_rounded;
    if (compat.any((m) => m.startsWith("flash_sd") || m.startsWith("flash_m"))) {
      return Icons.sd_card_rounded;
    }
    if (d.str(iDrive, "ConnectionBus") == "usb") return Icons.usb_rounded;
    if (d.integer(iDrive, "RotationRate") != 0) return Icons.storage_rounded;
    // Solid state: flash chips.
    return Icons.memory_rounded;
  }


  List<Widget> _driveActions(DriveEntry e) {
    final UObject? drive = e.drive;
    final UObject? disk = e.disk;
    final bool media = disk != null && disk.size > 0;
    final bool smart = drive != null &&
        (drive.flag(iAta, "SmartSupported") || drive.has(iNvme));
    final bool ataSettings = drive != null &&
        const ["PmSupported", "ApmSupported", "WriteCacheSupported"].any((p) => drive.flag(iAta, p));
    return [
      if (drive != null && drive.flag(iDrive, "Ejectable") && media)
        IconButton(
          tooltip: "Eject",
          icon: const Icon(Icons.eject_rounded),
          onPressed: () => _eject(e, powerOff: false),
        ),
      if (drive != null && drive.flag(iDrive, "CanPowerOff"))
        IconButton(
          tooltip: "Power Off",
          icon: const Icon(Icons.power_settings_new_rounded),
          onPressed: () => _eject(e, powerOff: true),
        ),
      if (drive == null)
        IconButton(
          tooltip: "Detach",
          icon: const Icon(Icons.eject_rounded),
          onPressed: () => _eject(e, powerOff: false),
        ),
      PopupMenuButton<VoidCallback>(
        tooltip: "Drive options",
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (media && !disk.readOnly)
            PopupMenuItem(value: () => _formatDisk(e), child: const Text("Format Disk…")),
          if (media)
            PopupMenuItem(value: () => _createImage(e, disk), child: const Text("Create Disk Image…")),
          if (media && !disk.readOnly)
            PopupMenuItem(value: () => _restoreImage(e, disk), child: const Text("Restore Disk Image…")),
          if (media)
            PopupMenuItem(value: () => _benchmark(e, disk), child: const Text("Benchmark Disk…")),
          if (smart)
            PopupMenuItem(
              value: () => showDialog<void>(
                context: this.context,
                builder: (context) => SmartDialog(udisks: udisks, drive: drive.path),
              ),
              child: const Text("SMART Data & Self-Tests…"),
            ),
          if (ataSettings)
            PopupMenuItem(value: () => _driveSettings(drive), child: const Text("Drive Settings…")),
          if (drive == null && disk != null && disk.has(iLoop))
            CheckedPopupMenuItem(
              checked: disk.flag(iLoop, "Autoclear"),
              value: () => _run(
                "Couldn't change the loop device",
                () => _call(disk, iLoop, "SetAutoclear", [DBusBoolean(!disk.flag(iLoop, "Autoclear"))]),
              ),
              child: const Text("Detach When Unmounted"),
            ),
          if (drive != null && drive.flag(iAta, "PmSupported")) ...[
            PopupMenuItem(
              value: () => _run("Couldn't put the drive in standby", () => _call(drive, iAta, "PmStandby")),
              child: const Text("Standby Now"),
            ),
            PopupMenuItem(
              value: () => _run("Couldn't wake up the drive", () => _call(drive, iAta, "PmWakeup")),
              child: const Text("Wake Up from Standby"),
            ),
          ],
        ],
      ),
    ];
  }

  Widget _drivePage(DriveEntry e) {
    final ThemeData theme = Theme.of(context);
    final UObject? drive = e.drive;
    final UObject? disk = e.disk;
    final bool media = disk != null && disk.size > 0;
    final List<UObject> jobs = udisks.jobsOn(media ? udisks.blocksOf(disk) : const [], drive);
    final String? health = drive == null ? null : smartAssessment(drive);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      children: [
        Row(
          children: [
            RailIcon(icon: _driveIcon(e), size: 52),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entryName(e), style: theme.textTheme.headlineSmall),
                  Text(
                    [
                      if (entrySize(e) > 0) formatSize(entrySize(e)),
                      busName(e),
                      if (disk != null) disk.device,
                    ].where((s) => s.isNotEmpty).join(" · "),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (jobs.isNotEmpty) SettingsGroup(children: [for (final UObject j in jobs) _JobRow(udisks: udisks, job: j)]),
        SettingsGroup(
          children: [
            if (drive != null && drive.model.isNotEmpty) InfoRow(label: "Model", value: drive.model),
            if (drive != null && drive.str(iDrive, "Serial").isNotEmpty)
              InfoRow(label: "Serial number", value: drive.str(iDrive, "Serial")),
            if (disk != null && disk.bytes(iLoop, "BackingFile").isNotEmpty)
              InfoRow(label: "Backing file", value: disk.bytes(iLoop, "BackingFile")),
            InfoRow(
              label: "Size",
              value: media ? "${formatSize(disk.size)} (${NumberFormat.decimalPattern().format(disk.size)} bytes)" : "No media",
            ),
            if (media)
              InfoRow(
                label: "Partitioning",
                value: switch (disk.str(iTable, "Type")) {
                  "gpt" => "GUID Partition Table",
                  "dos" => "Master Boot Record",
                  "" => "None",
                  final String t => t,
                },
              ),
            if (health != null) InfoRow(label: "Assessment", value: health),
          ],
        ),
        if (media) _volumes(e, disk),
      ],
    );
  }

  Widget _volumes(DriveEntry e, UObject disk) {
    final List<Segment> segments = udisks.layout(disk);
    final List<Segment> all = [];
    void walk(List<Segment> s) {
      for (final Segment x in s) {
        all.add(x);
        walk(x.children);
      }
    }

    walk(segments);
    Segment? selected = all
        .where((s) => s.isFree ? s.offset == _free && _volume == null : s.block!.path == _volume)
        .firstOrNull;
    selected ??= all.firstOrNull;
    // The row the selection is in, for the free space after it (Resize).
    List<Segment> rowOf(List<Segment> s) {
      if (s.contains(selected)) return s;
      for (final Segment x in s) {
        final List<Segment> r = rowOf(x.children);
        if (r.isNotEmpty) return r;
      }
      return const [];
    }

    return SettingsGroup(
      title: "Volumes",
      padding: const EdgeInsets.all(12),
      children: [
        _VolumeMap(
          segments: segments,
          selected: selected,
          name: (b) => volumeName(b),
          onSelect: (s) => setState(() {
            _volume = s.block?.path;
            _free = s.isFree ? s.offset : null;
          }),
        ),
        const SizedBox(height: 8),
        if (selected != null) ...[
          // Full width: the group centers what's narrower.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _volumeActions(e, disk, selected, rowOf(segments)),
            ),
          ),
          ..._volumeDetails(disk, selected),
        ],
      ],
    );
  }

  List<Widget> _volumeActions(DriveEntry e, UObject disk, Segment s, List<Segment> row) {
    Widget button(String label, IconData icon, VoidCallback? onPressed) => FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    if (s.isFree) {
      return [
        if (disk.has(iTable) && !disk.readOnly)
          button("Create Partition", Icons.add_rounded, () => _create(disk, s)),
      ];
    }
    final UObject b = s.block!;
    final bool fs = b.has(iFilesystem);
    final bool encrypted = b.has(iEncrypted);
    final bool unlocked = encrypted && udisks.cleartextOf(b) != null;
    final bool partition = b.has(iPartition);
    final bool writable = !b.readOnly;
    return [
      if (fs && b.mounted)
        button("Unmount", Icons.stop_rounded, () => _mount(b, false))
      else if (fs)
        button("Mount", Icons.play_arrow_rounded, () => _mount(b, true)),
      if (b.flag(iSwap, "Active"))
        button("Stop Swap", Icons.stop_rounded, () => _run("Couldn't stop swap", () => _call(b, iSwap, "Stop")))
      else if (b.has(iSwap))
        button("Start Swap", Icons.play_arrow_rounded, () => _run("Couldn't start swap", () => _call(b, iSwap, "Start"))),
      if (unlocked)
        button("Lock", Icons.lock_rounded, () => _lock(b))
      else if (encrypted)
        button("Unlock", Icons.lock_open_rounded, () => _unlock(b)),
      if (partition && writable)
        button("Delete", Icons.delete_outline_rounded, () => _delete(e, b)),
      _MenuButton(
        label: "More",
        icon: Icons.tune_rounded,
        items: [
          if (writable && !(partition && b.isContainer))
            PopupMenuItem(value: () => _format(e, b), child: const Text("Format Volume…")),
          if (partition && writable)
            PopupMenuItem(value: () => _editPartition(disk, b), child: const Text("Edit Partition…")),
          if (fs && writable)
            PopupMenuItem(value: () => _rename(b), child: const Text("Edit Filesystem…")),
          if (fs && writable && b.mounted)
            PopupMenuItem(value: () => _takeOwnership(b), child: const Text("Take Ownership…")),
          if (encrypted && writable)
            PopupMenuItem(value: () => _changePassphrase(b), child: const Text("Change Password…")),
          if (partition && writable && !b.isContainer)
            PopupMenuItem(value: () => _resize(row, b), child: const Text("Resize…")),
          if (fs) ...[
            PopupMenuItem(value: () => _check(b, repair: false), child: const Text("Check Filesystem…")),
            if (writable)
              PopupMenuItem(value: () => _check(b, repair: true), child: const Text("Repair Filesystem…")),
            PopupMenuItem(value: () => _configure(b, "fstab"), child: const Text("Edit Mount Options…")),
          ],
          if (encrypted)
            PopupMenuItem(value: () => _configure(b, "crypttab"), child: const Text("Edit Encryption Options…")),
          if (!(partition && b.isContainer)) ...[
            PopupMenuItem(value: () => _createImage(e, b), child: const Text("Create Partition Image…")),
            if (writable)
              PopupMenuItem(value: () => _restoreImage(e, b), child: const Text("Restore Partition Image…")),
            PopupMenuItem(value: () => _benchmark(e, b), child: const Text("Benchmark Partition…")),
          ],
        ],
      ),
    ];
  }

  List<Widget> _volumeDetails(UObject disk, Segment s) {
    if (s.isFree) {
      return [
        InfoRow(label: "Size", value: formatSize(s.size)),
        const InfoRow(label: "Contents", value: "Unallocated space"),
      ];
    }
    final UObject b = s.block!;
    final String version = b.str(iBlock, "IdVersion");
    final String state = b.has(iFilesystem)
        ? b.mounted
            ? "Mounted at ${b.mountPoints.join(", ")}"
            : "Not mounted"
        : b.has(iEncrypted)
            ? udisks.cleartextOf(b) != null
                ? "Unlocked"
                : "Locked"
            : b.has(iSwap)
                ? b.flag(iSwap, "Active")
                    ? "Active"
                    : "Not active"
                : "";
    return [
      InfoRow(
        label: "Size",
        value: "${formatSize(b.size)} (${NumberFormat.decimalPattern().format(b.size)} bytes)",
      ),
      InfoRow(label: "Device", value: b.device),
      if (b.str(iBlock, "IdUUID").isNotEmpty) InfoRow(label: "UUID", value: b.str(iBlock, "IdUUID")),
      if (b.has(iPartition))
        InfoRow(label: "Partition type", value: partTypeName(b, disk.str(iTable, "Type"))),
      if (b.partName.isNotEmpty) InfoRow(label: "Partition name", value: b.partName),
      InfoRow(
        label: "Contents",
        value: [
          "${contentName(b)}${version.isEmpty ? "" : " (version $version)"}",
          if (state.isNotEmpty) state,
        ].join(" — "),
      ),
    ];
  }
}

/// The drive list at the window's side: the tint of Settings' rail
/// (continuing the title bar, frosted over river's blur), with names.
class _DriveList extends StatelessWidget {
  const _DriveList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final Widget list = ColoredBox(
      color: DahliaRail.colorOf(context),
      child: SizedBox(
        width: 272,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: children,
        ),
      ),
    );
    if (!ZenitBlur.active) return list;
    return BlurRegion(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(DahliaTitlebar.windowRadius),
      ),
      child: list,
    );
  }
}

/// A drive in the [_DriveList]: its icon on an accent circle, name and size,
/// highlighted around when selected (as a [RailItem]).
class _DriveTile extends StatelessWidget {
  const _DriveTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: dark ? 0.32 : 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                RailIcon(icon: icon, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A UDisks job (Job.Operation) as the running row says it.
String jobOperationName(String op) => switch (op) {
      "format-mkfs" => "Formatting",
      "format-erase" => "Erasing",
      "filesystem-mount" => "Mounting",
      "filesystem-unmount" => "Unmounting",
      "filesystem-check" => "Checking the filesystem",
      "filesystem-repair" => "Repairing the filesystem",
      "filesystem-resize" => "Resizing the filesystem",
      "partition-create" => "Creating a partition",
      "partition-delete" => "Deleting a partition",
      "partition-modify" => "Changing a partition",
      "partition-resize" => "Resizing a partition",
      "encrypted-unlock" => "Unlocking",
      "encrypted-lock" => "Locking",
      "encrypted-modify" => "Changing the password",
      "ata-smart-selftest" => "Running a self-test",
      "drive-eject" => "Ejecting",
      "drive-power-off" => "Powering off",
      _ => op.replaceAll("-", " "),
    };

/// A running UDisks job: what, how far, Cancel.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.udisks, required this.job});

  final UDisksClient udisks;
  final UObject job;

  @override
  Widget build(BuildContext context) {
    final bool known = job.flag(iJob, "ProgressValid");
    final int end = job.integer(iJob, "ExpectedEndTime");
    final int left = end > 0 ? end ~/ 1000000 - DateTime.now().millisecondsSinceEpoch ~/ 1000 : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${jobOperationName(job.str(iJob, "Operation"))}…"
                  "${left > 0 ? " ${formatDuration(Duration(seconds: left))} left" : ""}",
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: known ? (job.get(iJob, "Progress")! as double) : null,
                  backgroundColor: progressTrackColor(Theme.of(context)),
                ),
              ],
            ),
          ),
          if (job.flag(iJob, "Cancelable"))
            IconButton(
              tooltip: "Cancel",
              icon: const Icon(Icons.close_rounded),
              onPressed: () => unawaited(
                udisks.call(job.path, iJob, "Cancel", [options()]).catchError((Object _) => <DBusValue>[]),
              ),
            ),
        ],
      ),
    );
  }
}

/// The partitions of a disk side by side, sized by how big they are (with
/// a minimum so small ones stay clickable), what's inside each under it.
class _VolumeMap extends StatelessWidget {
  const _VolumeMap({
    required this.segments,
    required this.selected,
    required this.name,
    required this.onSelect,
  });

  final List<Segment> segments;
  final Segment? selected;
  final String Function(UObject) name;
  final ValueChanged<Segment> onSelect;

  static const double _row = 52;
  static const double _gap = 4;

  static int _depth(List<Segment> s) =>
      s.isEmpty ? 0 : 1 + s.map((x) => _depth(x.children)).reduce(math.max);

  /// Widths summing to [total]: a minimum each (room for a short name),
  /// the rest by size.
  static List<double> _widths(List<Segment> s, double total) {
    const double min = 112;
    final double spare = total - _gap * (s.length - 1) - min * s.length;
    if (spare <= 0) return List.filled(s.length, (total - _gap * (s.length - 1)) / s.length);
    final int sum = s.fold(0, (a, x) => a + x.size);
    return [for (final Segment x in s) min + spare * x.size / math.max(1, sum)];
  }

  Widget _buildRow(BuildContext context, List<Segment> s, double width, double height) {
    final List<double> widths = _widths(s, width);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < s.length; i++) ...[
          if (i > 0) const SizedBox(width: _gap),
          SizedBox(
            width: widths[i],
            height: height,
            child: s[i].children.isEmpty
                ? _box(context, s[i])
                : Column(
                    children: [
                      SizedBox(height: _row, child: _box(context, s[i])),
                      const SizedBox(height: _gap),
                      _buildRow(context, s[i].children, widths[i], height - _row - _gap),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _box(BuildContext context, Segment s) {
    final ThemeData theme = Theme.of(context);
    final bool isSelected = identical(s, selected);
    final UObject? b = s.block;
    final Color fill = isSelected
        ? theme.colorScheme.primary
        : s.isFree
            ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
            : theme.colorScheme.primary.withValues(alpha: 0.14);
    final Color text = isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelect(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (b != null && b.mounted) ...[
                    Icon(Icons.folder_open_rounded, size: 14, color: text),
                    const SizedBox(width: 4),
                  ],
                  if (b != null && b.has(iEncrypted)) ...[
                    Icon(Icons.lock_rounded, size: 14, color: text),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      b == null ? "Free Space" : name(b),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: text, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Text(
                b == null ? formatSize(s.size) : "${formatSize(s.size)} ${contentName(b)}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: text.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final int depth = _depth(segments);
    final double height = depth * _row + (depth - 1) * _gap;
    return LayoutBuilder(
      builder: (context, constraints) =>
          SizedBox(height: height, child: _buildRow(context, segments, constraints.maxWidth, height)),
    );
  }
}

/// A tonal button that opens a menu of actions under it.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.label, required this.icon, required this.items});

  final String label;
  final IconData icon;
  final List<PopupMenuEntry<VoidCallback>> items;

  Future<void> _open(BuildContext context) async {
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Offset at = button.localToGlobal(Offset(0, button.size.height + 4), ancestor: overlay);
    final VoidCallback? action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
      items: items,
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: items.isEmpty ? null : () => _open(context),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
