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

// A fake UDisks2 (org.freedesktop.UDisks2) for the Disks app's tests: an
// NVMe drive with an encrypted root, a SATA hard disk with SMART, a USB
// stick and a loop device, the methods the app calls, and jobs with
// progress. Nothing touches a real disk: the Open* calls hand out sparse
// files in the data folder.
//
// Every call is checked against the method signatures of UDisks 2.11
// (data/org.freedesktop.UDisks2.xml) and must allow interactive
// authorization, as polkit needs for the prompt. Unlock accepts
// "secret123".
//
// In a test: FakeUDisks(bus, dataDir: dir).start(). Standalone, for a
// headless run of the app on a private system bus:
//   DBUS_SYSTEM_BUS_ADDRESS=... UDISKS_LOG=calls.log UDISKS_DATA=dir \
//     dart run test/disks/fake_udisks.dart
// It logs "ready" once it owns the name.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

const String _u = 'org.freedesktop.UDisks2';
const int _mib = 1024 * 1024;
const int _gib = 1024 * _mib;

/// The passphrase of every LUKS volume of the fake.
const String fakePassphrase = 'secret123';

/// In-signatures of the UDisks 2.11 methods the fake answers.
const Map<String, String> udisksSignatures = {
  'Manager.CanFormat': 's',
  'Manager.CanResize': 's',
  'Manager.CanCheck': 's',
  'Manager.CanRepair': 's',
  'Manager.LoopSetup': 'ha{sv}',
  'Drive.Eject': 'a{sv}',
  'Drive.SetConfiguration': 'a{sv}a{sv}',
  'Drive.PowerOff': 'a{sv}',
  'Drive.Ata.SmartUpdate': 'a{sv}',
  'Drive.Ata.SmartGetAttributes': 'a{sv}',
  'Drive.Ata.SmartSelftestStart': 'sa{sv}',
  'Drive.Ata.SmartSelftestAbort': 'a{sv}',
  'Drive.Ata.SmartSetEnabled': 'ba{sv}',
  'Drive.Ata.PmStandby': 'a{sv}',
  'Drive.Ata.PmWakeup': 'a{sv}',
  'NVMe.Controller.SmartUpdate': 'a{sv}',
  'NVMe.Controller.SmartGetAttributes': 'a{sv}',
  'NVMe.Controller.SmartSelftestStart': 'sa{sv}',
  'NVMe.Controller.SmartSelftestAbort': 'a{sv}',
  'Block.AddConfigurationItem': '(sa{sv})a{sv}',
  'Block.RemoveConfigurationItem': '(sa{sv})a{sv}',
  'Block.UpdateConfigurationItem': '(sa{sv})(sa{sv})a{sv}',
  'Block.GetSecretConfiguration': 'a{sv}',
  'Block.Format': 'sa{sv}',
  'Block.OpenForBackup': 'a{sv}',
  'Block.OpenForRestore': 'a{sv}',
  'Block.OpenForBenchmark': 'a{sv}',
  'PartitionTable.CreatePartition': 'ttssa{sv}',
  'PartitionTable.CreatePartitionAndFormat': 'ttssa{sv}sa{sv}',
  'Partition.SetType': 'sa{sv}',
  'Partition.SetName': 'sa{sv}',
  'Partition.SetFlags': 'ta{sv}',
  'Partition.Resize': 'ta{sv}',
  'Partition.Delete': 'a{sv}',
  'Filesystem.SetLabel': 'sa{sv}',
  'Filesystem.Mount': 'a{sv}',
  'Filesystem.Unmount': 'a{sv}',
  'Filesystem.Resize': 'ta{sv}',
  'Filesystem.Check': 'a{sv}',
  'Filesystem.Repair': 'a{sv}',
  'Filesystem.TakeOwnership': 'a{sv}',
  'Swapspace.Start': 'a{sv}',
  'Swapspace.Stop': 'a{sv}',
  'Encrypted.Unlock': 'sa{sv}',
  'Encrypted.Lock': 'a{sv}',
  'Encrypted.ChangePassphrase': 'ssa{sv}',
  'Encrypted.Resize': 'ta{sv}',
  'Loop.Delete': 'a{sv}',
  'Loop.SetAutoclear': 'ba{sv}',
  'Job.Cancel': 'a{sv}',
};

/// Methods UDisks answers without asking polkit.
const Set<String> _unprivileged = {
  'Manager.CanFormat',
  'Manager.CanResize',
  'Manager.CanCheck',
  'Manager.CanRepair',
  'Drive.Ata.SmartGetAttributes',
  'NVMe.Controller.SmartGetAttributes',
};

DBusArray _bs(String s) => DBusArray.byte([...utf8.encode(s), 0]);
String _unbs(DBusValue v) => utf8.decode(v.asByteArray().where((b) => b != 0).toList());
DBusObjectPath _bp(String name) => DBusObjectPath('/org/freedesktop/UDisks2/block_devices/$name');
DBusObjectPath _dp(String id) => DBusObjectPath('/org/freedesktop/UDisks2/drives/$id');
DBusMethodErrorResponse _failed(String m) => DBusMethodErrorResponse('$_u.Error.Failed', [DBusString(m)]);

/// One object of the fake: its interfaces and their properties.
class FakeObject extends DBusObject {
  FakeObject(this.fake, DBusObjectPath path, this.ifaces) : super(path);

  final FakeUDisks fake;
  final Map<String, Map<String, DBusValue>> ifaces;

  /// The last part of the path ("sda1", "nvme").
  String get name => path.value.split('/').last;

  @override
  Map<String, Map<String, DBusValue>> get interfacesAndProperties => ifaces;

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async =>
      DBusGetAllPropertiesResponse(ifaces[interface] ?? {});

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final DBusValue? v = ifaces[interface]?[name];
    return v == null ? DBusMethodErrorResponse.unknownProperty() : DBusGetPropertyResponse(v);
  }

  Future<void> set(String iface, Map<String, DBusValue> values) async {
    ifaces[iface]!.addAll(values);
    await emitPropertiesChanged(iface, changedProperties: values);
  }

  /// Interfaces were added or removed: clients reload on the signal.
  Future<void> reshaped() => fake._manager.emitInterfacesAdded(path, ifaces);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    final String method = '${call.interface?.replaceFirst('$_u.', '')}.${call.name}';
    String show(DBusValue v) => switch (v) {
          DBusArray(childSignature: DBusSignature(value: 'y')) => _unbs(v),
          DBusUnixFd() => 'fd',
          _ => '${v.toNative()}',
        };
    final List<String> shown = [
      for (final DBusValue v in call.values)
        if (v is! DBusDict || v.children.isNotEmpty) show(v),
    ];
    fake._record('$method $name ${shown.join(' ')}'.trimRight());
    final String? expected = udisksSignatures[method];
    if (expected == null) return DBusMethodErrorResponse.unknownMethod();
    if (call.signature.value != expected) {
      return DBusMethodErrorResponse.invalidArgs(
        "Type of message, '(${call.signature.value})', does not match expected type '($expected)'",
      );
    }
    if (!_unprivileged.contains(method)) {
      if (!call.allowInteractiveAuthorization) {
        return DBusMethodErrorResponse(
          '$_u.Error.NotAuthorizedCanObtain',
          [const DBusString('Not authorized to perform operation')],
        );
      }
      if (fake.dismiss.contains(method)) {
        return DBusMethodErrorResponse(
          '$_u.Error.NotAuthorizedDismissed',
          [const DBusString('The authentication dialog was dismissed')],
        );
      }
    }
    try {
      return await fake._handle(this, method, call);
    } on DBusMethodErrorResponse catch (e) {
      return e;
    }
  }
}

class _Job extends FakeObject {
  _Job(super.fake, super.path, super.ifaces, this.cancel);

  final void Function() cancel;
}

/// The fake service on [bus].
class FakeUDisks {
  FakeUDisks(this.bus, {required this.dataDir, this.log});

  final DBusClient bus;

  /// Where Open* calls create the devices' data files.
  final String dataDir;

  /// Also gets every call, as recorded in [calls].
  final void Function(String line)? log;

  /// Every method call: "Interface.Method object arguments…".
  final List<String> calls = [];

  /// Methods whose polkit prompt the user dismisses.
  final Set<String> dismiss = {};

  /// How long jobs (format, check…) take.
  Duration jobLength = const Duration(milliseconds: 300);

  late final DBusObject _manager =
      DBusObject(DBusObjectPath('/org/freedesktop/UDisks2'), isObjectManager: true);
  final Map<String, FakeObject> objects = {};
  int _jobs = 0;

  void _record(String line) {
    calls.add(line);
    log?.call(line);
  }

  FakeObject? operator [](String name) =>
      objects['/org/freedesktop/UDisks2/block_devices/$name'] ??
      objects['/org/freedesktop/UDisks2/drives/$name'];

  Future<FakeObject> _add(FakeObject o) async {
    objects[o.path.value] = o;
    await bus.registerObject(o);
    return o;
  }

  Future<void> _remove(FakeObject o) async {
    objects.remove(o.path.value);
    await bus.unregisterObject(o);
    await _manager.emitInterfacesRemoved(o.path, o.ifaces.keys.toList());
  }

  FakeObject? _byPath(DBusValue? p) => p is DBusObjectPath ? objects[p.value] : null;

  static String _usageOf(String type) => switch (type) {
        '' => '',
        'crypto_LUKS' => 'crypto',
        'swap' => 'other',
        _ => 'filesystem',
      };

  /// The Block interfaces for content [type] (Filesystem, Encrypted, Swapspace).
  static void _setContent(FakeObject b, String type, {String label = ''}) {
    b.ifaces['$_u.Block']!.addAll({
      'IdType': DBusString(type),
      'IdUsage': DBusString(_usageOf(type)),
      'IdLabel': DBusString(label),
      'IdUUID': DBusString(type.isEmpty ? '' : '${b.name}-0000-4000-8000-000000000001'),
      'IdVersion': DBusString(type == 'ext4' ? '1.0' : type == 'crypto_LUKS' ? '2' : ''),
    });
    b.ifaces.remove('$_u.Filesystem');
    b.ifaces.remove('$_u.Encrypted');
    b.ifaces.remove('$_u.Swapspace');
    if (_usageOf(type) == 'filesystem') {
      b.ifaces['$_u.Filesystem'] = {'MountPoints': DBusArray(DBusSignature('ay')), 'Size': const DBusUint64(0)};
    } else if (type == 'crypto_LUKS') {
      b.ifaces['$_u.Encrypted'] = {
        'CleartextDevice': DBusObjectPath('/'),
        'HintEncryptionType': const DBusString('luks2'),
      };
    } else if (type == 'swap') {
      b.ifaces['$_u.Swapspace'] = {'Active': const DBusBoolean(false)};
    }
  }

  FakeObject _block(
    String name,
    int size, {
    String? drive,
    String type = '',
    String label = '',
    String? table,
    (String table, int number, int offset, String type)? part,
    String partName = '',
    bool container = false,
    bool contained = false,
    String? backing,
    String? loopFile,
    bool readOnly = false,
  }) {
    final String dev = '/dev/${name.replaceAll('_2d', '-')}';
    final FakeObject b = FakeObject(this, _bp(name), {
      '$_u.Block': {
        // A loop device's node is its data file here, as the Open* calls
        // hand that out (the benchmark matches the descriptor to the node).
        'Device': _bs(loopFile != null ? '$dataDir/$name.img' : dev),
        'PreferredDevice': _bs(dev),
        'Size': DBusUint64(size),
        'ReadOnly': DBusBoolean(readOnly),
        'Drive': drive == null ? DBusObjectPath('/') : _dp(drive),
        'CryptoBackingDevice': backing == null ? DBusObjectPath('/') : _bp(backing),
        'Configuration': DBusArray(DBusSignature('(sa{sv})')),
        'HintSystem': DBusBoolean(drive != 'usb'),
      },
      if (table != null)
        '$_u.PartitionTable': {'Type': DBusString(table), 'Partitions': DBusArray(DBusSignature('o'))},
      if (part != null)
        '$_u.Partition': {
          'Table': _bp(part.$1),
          'Number': DBusUint32(part.$2),
          'Offset': DBusUint64(part.$3),
          'Size': DBusUint64(size),
          'Type': DBusString(part.$4),
          'Name': DBusString(partName),
          'Flags': const DBusUint64(0),
          'UUID': DBusString('$name-part-uuid'),
          'IsContainer': DBusBoolean(container),
          'IsContained': DBusBoolean(contained),
        },
      if (loopFile != null)
        '$_u.Loop': {'BackingFile': _bs(loopFile), 'Autoclear': const DBusBoolean(false)},
    });
    _setContent(b, type, label: label);
    return b;
  }

  FakeObject _drive(
    String id,
    String vendor,
    String model,
    int size, {
    String bus = '',
    int rotation = 0,
    bool removable = false,
    String serial = 'S4EWNX0R123456',
    List<String> compat = const [],
    String sortKey = '00',
  }) =>
      FakeObject(this, _dp(id), {
        '$_u.Drive': {
          'Vendor': DBusString(vendor),
          'Model': DBusString(model),
          'Serial': DBusString(serial),
          'Size': DBusUint64(size),
          'ConnectionBus': DBusString(bus),
          'RotationRate': DBusInt32(rotation),
          'Removable': DBusBoolean(removable),
          'MediaRemovable': DBusBoolean(removable),
          'Ejectable': DBusBoolean(removable),
          'CanPowerOff': DBusBoolean(removable),
          'MediaAvailable': const DBusBoolean(true),
          'MediaCompatibility': DBusArray.string(compat),
          'SortKey': DBusString(sortKey),
          'Id': DBusString('$vendor-$model-$serial'),
          'Configuration': DBusDict.stringVariant({}),
        },
      });

  /// A job on [on] for [jobLength]; false when cancelled.
  Future<bool> _job(String operation, List<FakeObject> on) async {
    final int start = DateTime.now().microsecondsSinceEpoch;
    bool cancelled = false;
    final _Job j = _Job(this, DBusObjectPath('/org/freedesktop/UDisks2/jobs/${++_jobs}'), {
      '$_u.Job': {
        'Operation': DBusString(operation),
        'Progress': const DBusDouble(0),
        'ProgressValid': const DBusBoolean(true),
        'Objects': DBusArray.objectPath(on.map((o) => o.path)),
        'Cancelable': const DBusBoolean(true),
        'StartTime': DBusUint64(start),
        'ExpectedEndTime': DBusUint64(start + jobLength.inMicroseconds),
        'StartedByUID': const DBusUint32(1000),
      },
    }, () => cancelled = true);
    await _add(j);
    const int steps = 10;
    for (int i = 1; i <= steps && !cancelled; i++) {
      await Future<void>.delayed(jobLength ~/ steps);
      await j.set('$_u.Job', {'Progress': DBusDouble(i / steps)});
    }
    await _remove(j);
    return !cancelled;
  }

  /// The partitions of the table [table].
  Iterable<FakeObject> _partitionsOf(FakeObject table) => objects.values
      .where((p) => (p.ifaces['$_u.Partition']?['Table'] as DBusObjectPath?)?.value == table.path.value);

  /// A new partition of [table] at [offset].
  Future<FakeObject> _newPartition(
    FakeObject table,
    int offset,
    int size,
    String type,
    String partName, {
    String content = '',
    String label = '',
    bool container = false,
  }) async {
    final int n = _partitionsOf(table).length + 1;
    final bool contained = _partitionsOf(table).any((p) {
      final Map<String, DBusValue> pi = p.ifaces['$_u.Partition']!;
      final int at = pi['Offset']!.asUint64();
      return pi['IsContainer']!.asBoolean() && at <= offset && offset < at + pi['Size']!.asUint64();
    });
    final FakeObject p = _block(
      '${table.name}${table.name.startsWith('nvme') ? 'p' : ''}${n + 10}',
      size,
      drive: (table.ifaces['$_u.Block']!['Drive']! as DBusObjectPath).value.split('/').last,
      type: content,
      label: label,
      part: (table.name, n + 10, offset, type),
      partName: partName,
      container: container,
      contained: contained,
    );
    await _job('partition-create', [table]);
    await _add(p);
    return p;
  }

  /// The path of a file descriptor just received: the highest number that
  /// points at a regular file of [length] bytes outside the data folder.
  String _receivedFile(int length) {
    int best = -1;
    String path = '';
    for (final FileSystemEntity e in Directory('/proc/self/fd').listSync()) {
      final int? n = int.tryParse(e.path.split('/').last);
      if (n == null || n <= best) continue;
      try {
        final String target = Link(e.path).targetSync();
        if (!target.startsWith('/') || target.startsWith(dataDir)) continue;
        if (FileSystemEntity.typeSync(target) != FileSystemEntityType.file) continue;
        if (File(target).lengthSync() != length) continue;
        best = n;
        path = target;
      } on FileSystemException {
        // The listing's own descriptor.
      }
    }
    return path;
  }

  Future<DBusMethodResponse> _handle(FakeObject o, String method, DBusMethodCall call) async {
    final List<DBusValue> a = call.values;
    final DBusMethodSuccessResponse ok = DBusMethodSuccessResponse();
    final Map<String, DBusValue>? blk = o.ifaces['$_u.Block'];
    Map<String, DBusValue> opts(DBusValue v) => v.asStringVariantDict();
    String driveOf(FakeObject b) => (b.ifaces['$_u.Block']!['Drive']! as DBusObjectPath).value.split('/').last;

    if (o is _Job && method == 'Job.Cancel') {
      o.cancel();
      return ok;
    }
    switch (method) {
      case 'Manager.CanFormat':
        final bool have = a[0].asString() != 'xfs';
        return DBusMethodSuccessResponse([
          DBusStruct([DBusBoolean(have), DBusString(have ? '' : 'mkfs.xfs')]),
        ]);
      case 'Manager.CanResize':
        final bool have = a[0].asString() != 'vfat';
        return DBusMethodSuccessResponse([
          DBusStruct([DBusBoolean(have), const DBusUint64(2 | 4 | 16), DBusString(have ? '' : 'fatresize')]),
        ]);
      case 'Manager.CanCheck' || 'Manager.CanRepair':
        final bool have = a[0].asString() != 'ntfs';
        return DBusMethodSuccessResponse([
          DBusStruct([DBusBoolean(have), DBusString(have ? '' : 'ntfsfix')]),
        ]);
      case 'Manager.LoopSetup':
        final RandomAccessFile file = (a[0] as DBusUnixFd).handle.toFile();
        final int size = file.lengthSync();
        final String backing = _receivedFile(size);
        file.closeSync();
        int n = 1;
        while (this['loop$n'] != null) {
          n++;
        }
        final bool readOnly = opts(a[1])['read-only']?.asBoolean() ?? false;
        final FakeObject loop = await _add(_block('loop$n', size, loopFile: backing, readOnly: readOnly));
        return DBusMethodSuccessResponse([loop.path]);
      case 'Filesystem.Mount':
        final String label = blk!['IdLabel']!.asString();
        final String at = '/run/media/test/${label.isEmpty ? o.name : label}';
        await o.set('$_u.Filesystem', {'MountPoints': DBusArray(DBusSignature('ay'), [_bs(at)])});
        return DBusMethodSuccessResponse([DBusString(at)]);
      case 'Filesystem.Unmount':
        if (o.name == 'dm_2d0') throw _failed('Error unmounting /dev/dm-0: target is busy');
        await o.set('$_u.Filesystem', {'MountPoints': DBusArray(DBusSignature('ay'))});
        return ok;
      case 'Filesystem.SetLabel':
        await o.set('$_u.Block', {'IdLabel': a[0]});
        return ok;
      case 'Filesystem.TakeOwnership':
        return ok;
      case 'Filesystem.Check' || 'Filesystem.Repair':
        await _job(method == 'Filesystem.Check' ? 'filesystem-check' : 'filesystem-repair', [o]);
        return DBusMethodSuccessResponse([const DBusBoolean(true)]);
      case 'Filesystem.Resize':
        await _job('filesystem-resize', [o]);
        return ok;
      case 'Encrypted.Unlock':
        if (a[0].asString() != fakePassphrase) {
          throw _failed('Error unlocking /dev/${o.name}: Failed to activate device: Incorrect passphrase.');
        }
        int n = 1;
        while (this['dm_2d$n'] != null) {
          n++;
        }
        final FakeObject clear = await _add(_block(
          'dm_2d$n',
          blk!['Size']!.asUint64() - 16 * _mib,
          type: 'ext4',
          label: 'Backup',
          backing: o.name,
          drive: driveOf(o),
        ));
        await o.set('$_u.Encrypted', {'CleartextDevice': clear.path});
        return DBusMethodSuccessResponse([clear.path]);
      case 'Encrypted.Lock':
        final FakeObject? clear = _byPath(o.ifaces['$_u.Encrypted']!['CleartextDevice']);
        if (clear != null) {
          if ((clear.ifaces['$_u.Filesystem']?['MountPoints'] as DBusArray?)?.children.isNotEmpty ?? false) {
            throw _failed('Error locking /dev/${o.name}: the unlocked device is mounted');
          }
          await _remove(clear);
        }
        await o.set('$_u.Encrypted', {'CleartextDevice': DBusObjectPath('/')});
        return ok;
      case 'Encrypted.ChangePassphrase':
        if (a[0].asString() != fakePassphrase) {
          throw _failed('Error changing passphrase on /dev/${o.name}: No keyslot with that passphrase');
        }
        return ok;
      case 'Encrypted.Resize':
        if (opts(a[1])['passphrase']?.asString() != fakePassphrase) {
          throw _failed('Error resizing encrypted device /dev/${o.name}: Failed to resize device');
        }
        final FakeObject? clear = _byPath(o.ifaces['$_u.Encrypted']!['CleartextDevice']);
        if (clear == null) throw _failed('Device is not unlocked');
        final int size = a[0].asUint64() == 0 ? blk!['Size']!.asUint64() - 16 * _mib : a[0].asUint64();
        await clear.set('$_u.Block', {'Size': DBusUint64(size)});
        return ok;
      case 'Swapspace.Start' || 'Swapspace.Stop':
        await o.set('$_u.Swapspace', {'Active': DBusBoolean(method == 'Swapspace.Start')});
        return ok;
      case 'Block.Format':
        final String type = a[0].asString();
        final Map<String, DBusValue> f = opts(a[1]);
        if (!await _job('format-mkfs', [o])) {
          throw DBusMethodErrorResponse('$_u.Error.Cancelled', [const DBusString('The job was cancelled')]);
        }
        if (type == 'gpt' || type == 'dos' || type == 'empty') {
          for (final FakeObject p in _partitionsOf(o).toList()) {
            await _remove(p);
          }
          o.ifaces.remove('$_u.PartitionTable');
          if (type != 'empty') {
            o.ifaces['$_u.PartitionTable'] = {'Type': DBusString(type), 'Partitions': DBusArray(DBusSignature('o'))};
          }
          _setContent(o, '');
        } else {
          _setContent(o, f.containsKey('encrypt.passphrase') ? 'crypto_LUKS' : type,
              label: f['label']?.asString() ?? '');
        }
        await o.reshaped();
        return ok;
      case 'Block.AddConfigurationItem' || 'Block.RemoveConfigurationItem' || 'Block.UpdateConfigurationItem':
        final List<DBusValue> items = [...(blk!['Configuration']! as DBusArray).children];
        if (method != 'Block.AddConfigurationItem') {
          // UDisks finds the entry to change by all its fields.
          final int before = items.length;
          items.removeWhere((i) => i == a[0]);
          if (items.length == before) throw _failed("Didn't find entry to remove");
        }
        if (method != 'Block.RemoveConfigurationItem') {
          final DBusStruct item = a[method == 'Block.AddConfigurationItem' ? 0 : 1] as DBusStruct;
          final Map<String, DBusValue> fields = item.children[1].asStringVariantDict();
          if ((item.children[0] as DBusString).value == 'crypttab' && !fields.containsKey('passphrase-contents')) {
            throw _failed('Missing options or passphrase-contents parameter in entry to add');
          }
          // Like /etc/crypttab, the visible entry has no secret.
          items.add(DBusStruct([
            item.children[0],
            DBusDict.stringVariant({...fields}..remove('passphrase-contents')),
          ]));
          _secrets[o.name] = fields['passphrase-contents'] == null ? '' : _unbs(fields['passphrase-contents']!);
        }
        await o.set('$_u.Block', {'Configuration': DBusArray(DBusSignature('(sa{sv})'), items)});
        return ok;
      case 'Block.GetSecretConfiguration':
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(sa{sv})'), [
            for (final DBusValue i in (blk!['Configuration']! as DBusArray).children)
              if (((i as DBusStruct).children[0] as DBusString).value == 'crypttab')
                DBusStruct([
                  i.children[0],
                  DBusDict.stringVariant({
                    ...i.children[1].asStringVariantDict(),
                    'passphrase-contents': _bs(_secrets[o.name] ?? ''),
                  }),
                ])
              else
                i,
          ]),
        ]);
      case 'Block.OpenForBackup' || 'Block.OpenForRestore' || 'Block.OpenForBenchmark':
        final File f = File('$dataDir/${o.name}.img');
        if (!f.existsSync()) {
          f.createSync(recursive: true);
          f.openSync(mode: FileMode.write)
            ..truncateSync(blk!['Size']!.asUint64())
            ..closeSync();
        }
        final RandomAccessFile raf =
            f.openSync(mode: method == 'Block.OpenForRestore' ? FileMode.writeOnlyAppend : FileMode.read);
        if (method == 'Block.OpenForRestore') raf.setPositionSync(0);
        return DBusMethodSuccessResponse([DBusUnixFd(ResourceHandle.fromFile(raf))]);
      case 'PartitionTable.CreatePartition':
        final bool extended = opts(a[4])['partition-type']?.asString() == 'extended';
        final FakeObject p = await _newPartition(o, a[0].asUint64(), a[1].asUint64(),
            extended ? '0x05' : a[2].asString(), a[3].asString(),
            container: extended);
        return DBusMethodSuccessResponse([p.path]);
      case 'PartitionTable.CreatePartitionAndFormat':
        final Map<String, DBusValue> f = opts(a[6]);
        final String fstype = a[5].asString();
        final String table = o.ifaces['$_u.PartitionTable']!['Type']!.asString();
        final String type = a[2].asString().isNotEmpty
            ? a[2].asString()
            : table == 'gpt'
                ? '0fc63daf-8483-4772-8e79-3d69d8477de4'
                : '0x83';
        final FakeObject p = await _newPartition(
          o,
          a[0].asUint64(),
          a[1].asUint64(),
          type,
          a[3].asString(),
          content: fstype == 'empty' ? '' : f.containsKey('encrypt.passphrase') ? 'crypto_LUKS' : fstype,
          label: f['label']?.asString() ?? '',
        );
        return DBusMethodSuccessResponse([p.path]);
      case 'Partition.Delete':
        await _remove(o);
        return ok;
      case 'Partition.SetType':
        await o.set('$_u.Partition', {'Type': a[0]});
        return ok;
      case 'Partition.SetName':
        await o.set('$_u.Partition', {'Name': a[0]});
        return ok;
      case 'Partition.SetFlags':
        await o.set('$_u.Partition', {'Flags': a[0]});
        return ok;
      case 'Partition.Resize':
        await o.set('$_u.Partition', {'Size': a[0]});
        await o.set('$_u.Block', {'Size': a[0]});
        return ok;
      case 'Loop.Delete':
        await _remove(o);
        return ok;
      case 'Loop.SetAutoclear':
        await o.set('$_u.Loop', {'Autoclear': a[0]});
        return ok;
      case 'Drive.Eject':
        return ok;
      case 'Drive.PowerOff':
        for (final FakeObject b in objects.values.toList()) {
          if ((b.ifaces['$_u.Block']?['Drive'] as DBusObjectPath?)?.value == o.path.value) await _remove(b);
        }
        await _remove(o);
        return ok;
      case 'Drive.SetConfiguration':
        await o.set('$_u.Drive', {'Configuration': a[0]});
        return ok;
      case 'Drive.Ata.SmartGetAttributes':
        DBusStruct attr(int id, String name, int flags, int value, int worst, int thresh, int pretty, int unit) =>
            DBusStruct([
              DBusByte(id), DBusString(name), DBusUint16(flags), DBusInt32(value), DBusInt32(worst), //
              DBusInt32(thresh), DBusInt64(pretty), DBusInt32(unit), DBusDict.stringVariant({}),
            ]);
        return DBusMethodSuccessResponse([
          DBusArray(DBusSignature('(ysqiiixia{sv})'), [
            attr(1, 'raw-read-error-rate', 0x0b, 200, 200, 51, 0, 1),
            attr(3, 'spin-up-time', 0x07, 172, 170, 21, 4325, 2),
            attr(5, 'reallocated-sector-count', 0x33, 200, 200, 140, 0, 3),
            attr(9, 'power-on-hours', 0x32, 61, 61, 0, 28600 * 3600 * 1000, 2),
            attr(194, 'temperature-celsius-2', 0x22, 113, 99, 0, 310150, 4),
            attr(197, 'current-pending-sector', 0x32, 200, 200, 0, 0, 3),
          ]),
        ]);
      case 'NVMe.Controller.SmartGetAttributes':
        return DBusMethodSuccessResponse([
          DBusDict.stringVariant({
            'avail_spare': const DBusByte(100),
            'spare_thresh': const DBusByte(10),
            'percent_used': const DBusByte(3),
            'total_data_read': const DBusUint64(41234567890123),
            'total_data_written': const DBusUint64(29876543210987),
            'ctrl_busy_time': const DBusUint64(1234),
            'power_cycles': const DBusUint64(1520),
            'unsafe_shutdowns': const DBusUint64(37),
            'media_errors': const DBusUint64(0),
            'num_err_log_entries': const DBusUint64(4),
            'warning_temp_time': const DBusUint32(0),
            'critical_temp_time': const DBusUint32(0),
          }),
        ]);
      case 'Drive.Ata.SmartSelftestStart' || 'NVMe.Controller.SmartSelftestStart':
        final String iface = call.interface!;
        await o.set(iface, {
          'SmartSelftestStatus': const DBusString('inprogress'),
          'SmartSelftestPercentRemaining': const DBusInt32(90),
        });
        unawaited(() async {
          for (int left = 80; left >= 0; left -= 10) {
            await Future<void>.delayed(jobLength);
            if (!objects.containsKey(o.path.value)) return;
            if ((o.ifaces[iface]!['SmartSelftestStatus']! as DBusString).value != 'inprogress') return;
            await o.set(iface, {'SmartSelftestPercentRemaining': DBusInt32(left)});
          }
          await o.set(iface, {
            'SmartSelftestStatus': const DBusString('success'),
            'SmartSelftestPercentRemaining': const DBusInt32(-1),
          });
        }());
        return ok;
      case 'Drive.Ata.SmartSelftestAbort' || 'NVMe.Controller.SmartSelftestAbort':
        await o.set(call.interface!, {
          'SmartSelftestStatus': const DBusString('aborted'),
          'SmartSelftestPercentRemaining': const DBusInt32(-1),
        });
        return ok;
      case 'Drive.Ata.SmartUpdate' || 'NVMe.Controller.SmartUpdate':
        await o.set(call.interface!, {'SmartUpdated': DBusUint64(DateTime.now().millisecondsSinceEpoch ~/ 1000)});
        return ok;
      case 'Drive.Ata.SmartSetEnabled':
        await o.set('$_u.Drive.Ata', {'SmartEnabled': a[0]});
        return ok;
      case 'Drive.Ata.PmStandby' || 'Drive.Ata.PmWakeup':
        return ok;
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  /// Key file contents of crypttab entries, by block.
  final Map<String, String> _secrets = {};

  /// Registers the objects and takes the name.
  Future<void> start() async {
    await bus.registerObject(_manager);
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _add(FakeObject(this, DBusObjectPath('/org/freedesktop/UDisks2/Manager'), {
      '$_u.Manager': {
        'Version': const DBusString('2.11.2'),
        'SupportedFilesystems': DBusArray.string(['ext4', 'vfat', 'ntfs', 'exfat', 'btrfs']),
      },
    }));

    // NVMe system disk: EFI, /boot, LUKS with a Btrfs root, free space.
    const int nvmeSize = 1000204886016;
    final FakeObject nvme =
        _drive('nvme', 'Samsung', 'SSD 980 PRO 1TB', nvmeSize, serial: 'S5GXNX0T912345', sortKey: '00nvme');
    nvme.ifaces['$_u.NVMe.Controller'] = {
      'SmartUpdated': DBusUint64(now),
      'SmartCriticalWarning': DBusArray.string([]),
      'SmartPowerOnHours': const DBusUint64(5321),
      'SmartTemperature': const DBusUint16(311),
      'SmartSelftestStatus': const DBusString('success'),
      'SmartSelftestPercentRemaining': const DBusInt32(-1),
    };
    await _add(nvme);
    await _add(_block('nvme0n1', nvmeSize, drive: 'nvme', table: 'gpt'));
    await _add(_block('nvme0n1p1', 600 * _mib,
        drive: 'nvme',
        type: 'vfat',
        part: ('nvme0n1', 1, _mib, 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'),
        partName: 'EFI System Partition'));
    await _add(_block('nvme0n1p2', _gib,
        drive: 'nvme', type: 'ext4', part: ('nvme0n1', 2, 601 * _mib, '0fc63daf-8483-4772-8e79-3d69d8477de4')));
    final FakeObject luks = _block('nvme0n1p3', 900 * _gib,
        drive: 'nvme',
        type: 'crypto_LUKS',
        part: ('nvme0n1', 3, 601 * _mib + _gib, 'ca7d7ccb-63ed-4c53-861c-1742536059cc'));
    luks.ifaces['$_u.Encrypted']!['CleartextDevice'] = _bp('dm_2d0');
    luks.ifaces['$_u.Block']!['Configuration'] = DBusArray(DBusSignature('(sa{sv})'), [
      DBusStruct([
        const DBusString('crypttab'),
        DBusDict.stringVariant({
          'name': _bs('luks-nvme0n1p3'),
          'device': _bs('UUID=nvme0n1p3-0000-4000-8000-000000000001'),
          'passphrase-path': _bs('/etc/luks-keys/luks-nvme0n1p3'),
          'options': _bs('discard'),
        }),
      ]),
    ]);
    _secrets['nvme0n1p3'] = fakePassphrase;
    await _add(luks);
    final FakeObject root =
        _block('dm_2d0', 900 * _gib - 16 * _mib, drive: 'nvme', type: 'btrfs', label: 'fedora', backing: 'nvme0n1p3');
    root.ifaces['$_u.Filesystem']!['MountPoints'] = DBusArray(DBusSignature('ay'), [_bs('/'), _bs('/home')]);
    root.ifaces['$_u.Block']!['Configuration'] = DBusArray(DBusSignature('(sa{sv})'), [
      DBusStruct([
        const DBusString('fstab'),
        DBusDict.stringVariant({
          'fsname': _bs('UUID=dm_2d0-0000-4000-8000-000000000001'),
          'dir': _bs('/'),
          'type': _bs('btrfs'),
          'opts': _bs('subvol=root,compress=zstd:1'),
          'freq': const DBusInt32(0),
          'passno': const DBusInt32(1),
        }),
      ]),
    ]);
    await _add(root);
    for (final (String n, String mp) in [('nvme0n1p1', '/boot/efi'), ('nvme0n1p2', '/boot')]) {
      objects[_bp(n).value]!.ifaces['$_u.Filesystem']!['MountPoints'] = DBusArray(DBusSignature('ay'), [_bs(mp)]);
    }

    // SATA hard disk with ATA SMART: NTFS, swap, a locked LUKS volume.
    const int hddSize = 1000204886016;
    final FakeObject hdd =
        _drive('hdd', 'WDC', 'WD10EZEX-08WN4A0', hddSize, rotation: 7200, serial: 'WD-WCC6Y0123456', sortKey: '01hdd');
    hdd.ifaces['$_u.Drive.Ata'] = {
      'SmartSupported': const DBusBoolean(true),
      'SmartEnabled': const DBusBoolean(true),
      'SmartUpdated': DBusUint64(now),
      'SmartFailing': const DBusBoolean(false),
      'SmartPowerOnSeconds': const DBusUint64(28600 * 3600),
      'SmartTemperature': const DBusDouble(310.15),
      'SmartNumBadSectors': const DBusInt64(0),
      'SmartSelftestStatus': const DBusString('success'),
      'SmartSelftestPercentRemaining': const DBusInt32(-1),
      'PmSupported': const DBusBoolean(true),
      'ApmSupported': const DBusBoolean(true),
      'WriteCacheSupported': const DBusBoolean(true),
      'WriteCacheEnabled': const DBusBoolean(true),
    };
    await _add(hdd);
    await _add(_block('sda', hddSize, drive: 'hdd', table: 'gpt'));
    await _add(_block('sda1', 400 * _gib,
        drive: 'hdd',
        type: 'ntfs',
        label: 'Data',
        part: ('sda', 1, _mib, 'ebd0a0a2-b9e5-4433-87c0-68b6b72699c7'),
        partName: 'Basic data partition'));
    await _add(_block('sda2', 8 * _gib,
        drive: 'hdd', type: 'swap', part: ('sda', 2, _mib + 400 * _gib, '0657fd6d-a4ab-43c4-84e5-0933c84b4f4f')));
    await _add(_block('sda3', 300 * _gib,
        drive: 'hdd',
        type: 'crypto_LUKS',
        part: ('sda', 3, _mib + 408 * _gib, 'ca7d7ccb-63ed-4c53-861c-1742536059cc')));

    // USB stick: MBR with one FAT partition.
    const int usbSize = 32017047552;
    await _add(_drive('usb', 'SanDisk', 'Ultra', usbSize,
        bus: 'usb', removable: true, serial: '4C530001230512345678', compat: ['thumb'], sortKey: '02usb'));
    await _add(_block('sdb', usbSize, drive: 'usb', table: 'dos'));
    await _add(_block('sdb1', 16 * _gib, drive: 'usb', type: 'vfat', label: 'SANDISK', part: ('sdb', 1, _mib, '0x0c')));

    // A small disk image attached as a loop device.
    await _add(_block('loop0', 64 * _mib, type: 'ext4', label: 'image', loopFile: '$dataDir/backing.img'));

    await bus.requestName(_u, flags: {DBusRequestNameFlag.doNotQueue});
    _record('ready');
  }
}

Future<void> main() async {
  final Map<String, String> env = Platform.environment;
  final File? log = env['UDISKS_LOG'] == null ? null : File(env['UDISKS_LOG']!);
  final FakeUDisks fake = FakeUDisks(
    DBusClient(DBusAddress(env['DBUS_SYSTEM_BUS_ADDRESS']!)),
    dataDir: env['UDISKS_DATA'] ?? Directory.systemTemp.createTempSync('fake-udisks').path,
    log: log == null ? print : (line) => log.writeAsStringSync('$line\n', mode: FileMode.append),
  );
  if (env['UDISKS_JOB_MS'] != null) fake.jobLength = Duration(milliseconds: int.parse(env['UDISKS_JOB_MS']!));
  fake.dismiss.addAll((env['UDISKS_DISMISS'] ?? '').split(',').where((m) => m.isNotEmpty));
  await fake.start();
}
