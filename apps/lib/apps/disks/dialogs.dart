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

import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

/// Frame of the Disks dialogs: a title, a form and Cancel/[action].
class DisksDialog extends StatelessWidget {
  const DisksDialog({
    required this.title,
    required this.action,
    required this.onAction,
    required this.children,
    this.destructive = false,
    this.width = 460,
    super.key,
  });

  final String title;
  final String action;

  /// Null disables the action (the form isn't complete).
  final VoidCallback? onAction;
  final List<Widget> children;
  final bool destructive;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          // Room for the first field's floating label.
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: onAction,
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          child: Text(action),
        ),
      ],
    );
  }
}

/// Asks before something that destroys data; [message] names the disk or
/// volume and what's on it.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => DisksDialog(
        title: title,
        action: action,
        destructive: true,
        onAction: () => Navigator.pop(context, true),
        children: [Text(message)],
      ),
    ) ==
    true;

Widget _gap([double h = 12]) => SizedBox(height: h);

/// The off track of switches and sliders, a shade off `surface`: dialogs are
/// drawn in `surface`, where Zenit's own track (also `surface`) vanishes.
Color trackColor(ThemeData theme) => Color.alphaBlend(
      theme.colorScheme.onSurface.withValues(alpha: 0.08),
      theme.colorScheme.surface,
    );

/// The track of progress bars: a light accent, so the bar shows how far it
/// got (Zenit's default track is the accent itself).
Color progressTrackColor(ThemeData theme) => theme.colorScheme.primary.withValues(alpha: 0.2);

Widget _switchRow(
  String title,
  bool value,
  ValueChanged<bool> onChanged, {
  String? subtitle,
}) =>
    Builder(
      builder: (context) => SettingsRow(
        title: title,
        subtitle: subtitle,
        trailing: ZenitSwitch(
          value: value,
          onChanged: onChanged,
          theme: ZenitTheme.switchTheme(context)
              .copyWith(inactiveTrackColor: trackColor(Theme.of(context))),
        ),
        onTap: () => onChanged(!value),
      ),
    );

Widget _choiceRow<T>(
  String title,
  T value,
  Map<T, String> items,
  ValueChanged<T> onChanged, {
  bool enabled = true,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 16),
          Flexible(
            flex: 2,
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              onChanged: enabled
                  ? (v) {
                      if (v != null) onChanged(v);
                    }
                  : null,
              items: [
                for (final MapEntry<T, String> e in items.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

/// A selectable option with a description (filesystem types, schemes).
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: selected,
      enabled: onTap != null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      leading: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

/// What a format dialog asks for.
class FormatRequest {
  const FormatRequest({
    required this.type,
    required this.label,
    required this.erase,
    this.passphrase,
    this.size,
  });

  /// Filesystem for Block.Format ("ext4", "vfat"…).
  final String type;
  final String label;
  final bool erase;

  /// Set: inside a LUKS volume with this passphrase.
  final String? passphrase;

  /// Bytes of a new partition.
  final int? size;

  Map<String, DBusValue> get options => {
        if (label.isNotEmpty) "label": DBusString(label),
        // The new filesystem belongs to the user formatting it, not root.
        "take-ownership": const DBusBoolean(true),
        "update-partition-type": const DBusBoolean(true),
        if (erase) "erase": const DBusString("zero"),
        if (passphrase != null) ...{
          "encrypt.passphrase": DBusString(passphrase!),
          "encrypt.type": const DBusString("luks2"),
        },
      };
}

/// FormatRequest.type of an MBR extended partition (not a filesystem).
const String extendedPartition = "extended";

const List<(String, String, String)> _filesystems = [
  ("ext4", "Ext4", "For Linux"),
  ("ntfs", "NTFS", "For Windows"),
  ("exfat", "exFAT", "For all systems and devices, files over 4 GB"),
  ("vfat", "FAT", "For all systems and devices"),
  ("btrfs", "Btrfs", "For Linux, with snapshots and compression"),
  ("xfs", "XFS", "For Linux, large files"),
  ("luks", "Ext4 with password", "Encrypted with LUKS, for Linux"),
  ("empty", "No filesystem", "Leave it unformatted"),
];

/// Format Volume and Create Partition (with [maxSize]).
class FormatDialog extends StatefulWidget {
  const FormatDialog({
    required this.udisks,
    required this.title,
    required this.action,
    this.maxSize,
    this.message,
    this.offerExtended = false,
    super.key,
  });

  final UDisksClient udisks;
  final String title;
  final String action;

  /// Names what's formatted and what's on it.
  final String? message;

  /// Creating a partition in free space of this many bytes.
  final int? maxSize;

  /// Offers an MBR extended partition (room for more than four).
  final bool offerExtended;

  @override
  State<FormatDialog> createState() => _FormatDialogState();
}

class _FormatDialogState extends State<FormatDialog> {
  String _type = "ext4";
  bool _erase = false;
  final TextEditingController _label = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _pass2 = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  late final TextEditingController _size = TextEditingController(
    text: widget.maxSize == null ? "" : (widget.maxSize! / 1e6).floor().toString(),
  );

  /// Programs UDisks lacks for a type (Manager.CanFormat).
  final Map<String, String> _missing = {};

  late final List<(String, String, String)> _types = [
    ..._filesystems,
    if (widget.offerExtended)
      (extendedPartition, "Extended partition", "Holds more partitions; MBR has room for four"),
  ];

  /// The type has a filesystem (and so a name).
  bool get _named => _type != "empty" && _type != extendedPartition;

  @override
  void initState() {
    super.initState();
    for (final (String type, _, _) in _filesystems) {
      if (type != "empty") unawaited(_check(type == "luks" ? "ext4" : type));
    }
  }

  Future<void> _check(String type) async {
    try {
      final List<DBusValue> r = await widget.udisks.call(
        managerPath,
        iManager,
        "CanFormat",
        [DBusString(type)],
        reply: "(bs)",
      );
      final List<DBusValue> v = (r.first as DBusStruct).children;
      if (!(v[0] as DBusBoolean).value && mounted) {
        setState(() => _missing[type] = (v[1] as DBusString).value);
      }
    } on Object {
      // Older UDisks: let Format report it.
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _pass.dispose();
    _pass2.dispose();
    _passFocus.dispose();
    _size.dispose();
    super.dispose();
  }

  void _choose(String type) {
    setState(() => _type = type);
    // The password fields come in below the list: focusing the first one
    // scrolls it into view.
    if (type == "luks") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passFocus.requestFocus();
      });
    }
  }

  int? get _bytes {
    if (widget.maxSize == null) return null;
    final double? mb = double.tryParse(_size.text.trim());
    if (mb == null || mb < 1) return null;
    return (mb * 1e6).round().clamp(0, widget.maxSize!);
  }

  bool get _valid =>
      (widget.maxSize == null || _bytes != null) &&
      (_type != "luks" || (_pass.text.isNotEmpty && _pass.text == _pass2.text));

  @override
  Widget build(BuildContext context) {
    return DisksDialog(
      title: widget.title,
      action: widget.action,
      destructive: widget.maxSize == null,
      onAction: !_valid
          ? null
          : () => Navigator.pop(
                context,
                FormatRequest(
                  type: _type == "luks" ? "ext4" : _type,
                  label: _named ? _label.text.trim() : "",
                  erase: _erase && _type != extendedPartition,
                  passphrase: _type == "luks" ? _pass.text : null,
                  size: _bytes,
                ),
              ),
      children: [
        if (widget.message != null) ...[Text(widget.message!), _gap(16)],
        if (widget.maxSize != null) ...[
          TextField(
            controller: _size,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[0-9.]"))],
            decoration: InputDecoration(
              labelText: "Size (MB)",
              helperText: "Up to ${formatSize(widget.maxSize!)}",
            ),
            onChanged: (_) => setState(() {}),
          ),
          _gap(),
        ],
        TextField(
          controller: _label,
          autofocus: widget.maxSize == null,
          enabled: _named,
          decoration: const InputDecoration(labelText: "Volume name"),
        ),
        _gap(16),
        for (final (String type, String title, String subtitle) in _types)
          _Option(
            title: title,
            subtitle: _missing[type == "luks" ? "ext4" : type] == null
                ? subtitle
                : "Needs ${_missing[type == "luks" ? "ext4" : type]}",
            selected: _type == type,
            onTap: _missing.containsKey(type == "luks" ? "ext4" : type) ? null : () => _choose(type),
          ),
        if (_type == "luks") ...[
          _gap(),
          TextField(
            controller: _pass,
            focusNode: _passFocus,
            obscureText: true,
            decoration: const InputDecoration(labelText: "Password"),
            onChanged: (_) => setState(() {}),
          ),
          _gap(),
          TextField(
            controller: _pass2,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Confirm password",
              errorText: _pass2.text.isNotEmpty && _pass.text != _pass2.text
                  ? "The passwords don't match"
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          _gap(4),
          Text(
            "If you forget this password, the data can't be recovered.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_type != extendedPartition) ...[
          _gap(),
          _switchRow(
            "Erase",
            _erase,
            (v) => setState(() => _erase = v),
            subtitle: "Overwrite the old data with zeroes (slow)",
          ),
        ],
      ],
    );
  }
}

/// Format Disk: the partitioning scheme, and whether to erase.
class FormatDiskDialog extends StatefulWidget {
  const FormatDiskDialog({required this.message, super.key});

  /// Names the disk and its contents.
  final String message;

  @override
  State<FormatDiskDialog> createState() => _FormatDiskDialogState();
}

class _FormatDiskDialogState extends State<FormatDiskDialog> {
  String _scheme = "gpt";
  bool _erase = false;

  @override
  Widget build(BuildContext context) {
    return DisksDialog(
      title: "Format Disk",
      action: "Format",
      destructive: true,
      onAction: () => Navigator.pop(context, (_scheme, _erase)),
      children: [
        Text(widget.message),
        _gap(16),
        for (final (String scheme, String title, String subtitle) in const [
          ("gpt", "GPT", "For modern systems and disks over 2 TB"),
          ("dos", "MBR / DOS", "For all systems and devices, including old ones"),
          ("empty", "No partitioning", "An empty disk"),
        ])
          _Option(
            title: title,
            subtitle: subtitle,
            selected: _scheme == scheme,
            onTap: () => setState(() => _scheme = scheme),
          ),
        _gap(),
        _switchRow(
          "Erase",
          _erase,
          (v) => setState(() => _erase = v),
          subtitle: "Overwrite the whole disk with zeroes (slow)",
        ),
      ],
    );
  }
}

/// Edit Partition: type, name (GPT) and flags.
class EditPartitionDialog extends StatefulWidget {
  const EditPartitionDialog({required this.partition, required this.tableType, super.key});

  final UObject partition;
  final String tableType;

  @override
  State<EditPartitionDialog> createState() => _EditPartitionDialogState();
}

class _EditPartitionDialogState extends State<EditPartitionDialog> {
  late String _type = widget.partition.partType.toLowerCase();
  late int _flags = widget.partition.partFlags;
  late final TextEditingController _name =
      TextEditingController(text: widget.partition.partName);

  bool get _gpt => widget.tableType == "gpt";

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _flag(String title, int bit, String subtitle) => _switchRow(
        title,
        _flags & bit != 0,
        (v) => setState(() => _flags = v ? _flags | bit : _flags & ~bit),
        subtitle: subtitle,
      );

  @override
  Widget build(BuildContext context) {
    final Map<String, String> types = {
      ...(_gpt ? gptTypes : dosTypes),
      if (!(_gpt ? gptTypes : dosTypes).containsKey(_type))
        _type: partTypeName(widget.partition, widget.tableType),
    };
    return DisksDialog(
      title: "Edit Partition",
      action: "Change",
      onAction: () => Navigator.pop(context, (_type, _name.text.trim(), _flags)),
      children: [
        _choiceRow<String>(
          "Type",
          _type,
          types,
          (v) => setState(() => _type = v),
          enabled: !widget.partition.isContainer,
        ),
        if (_gpt) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: "Name"),
            ),
          ),
          _gap(),
          _flag("System partition", 1, "Firmware and other systems leave it alone"),
          _flag("Hide from firmware", 2, "EFI firmware doesn't read it"),
          _flag("Legacy BIOS bootable", 4, "BIOS boots from it"),
        ] else
          _flag("Bootable", 0x80, "BIOS boots from it"),
      ],
    );
  }
}

/// One text field (a password, a label); returns its text.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  String initial = "",
  bool secret = false,
  String? message,
}) {
  final TextEditingController controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => DisksDialog(
      title: title,
      action: action,
      onAction: () => Navigator.pop(context, controller.text),
      children: [
        if (message != null) ...[Text(message), _gap()],
        TextField(
          controller: controller,
          autofocus: true,
          obscureText: secret,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Change Passphrase: the current one and the new one twice.
class ChangePassphraseDialog extends StatefulWidget {
  const ChangePassphraseDialog({super.key});

  @override
  State<ChangePassphraseDialog> createState() => _ChangePassphraseDialogState();
}

class _ChangePassphraseDialogState extends State<ChangePassphraseDialog> {
  final List<TextEditingController> _fields =
      List.generate(3, (_) => TextEditingController());

  @override
  void dispose() {
    for (final TextEditingController c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool match = _fields[1].text == _fields[2].text;
    return DisksDialog(
      title: "Change Password",
      action: "Change",
      onAction: _fields[0].text.isEmpty || _fields[1].text.isEmpty || !match
          ? null
          : () => Navigator.pop(context, (_fields[0].text, _fields[1].text)),
      children: [
        for (final (int i, String label) in const [
          (0, "Current password"),
          (1, "New password"),
          (2, "Confirm new password"),
        ]) ...[
          if (i > 0) _gap(),
          TextField(
            controller: _fields[i],
            autofocus: i == 0,
            obscureText: true,
            decoration: InputDecoration(
              labelText: label,
              errorText: i == 2 && _fields[2].text.isNotEmpty && !match
                  ? "The passwords don't match"
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ],
    );
  }
}

/// The options of an fstab/crypttab entry that have their own switch,
/// split from the rest.
(Set<String>, String) splitOptions(String opts, Set<String> own) {
  final List<String> all = [
    for (final String o in opts.split(",")) if (o.trim().isNotEmpty) o.trim(),
  ];
  return (
    all.where(own.contains).toSet(),
    all.where((o) => !own.contains(o) && o != "defaults").join(","),
  );
}

String joinOptions(Iterable<String> own, String rest) {
  final List<String> all = [
    for (final String o in rest.split(",")) if (o.trim().isNotEmpty) o.trim(),
    ...own,
  ];
  return all.isEmpty ? "defaults" : all.join(",");
}

/// Mount Options: the block's fstab entry. Pops the record `(null,)` for
/// session defaults (no entry) or `(fields,)` for the new entry.
class MountOptionsDialog extends StatefulWidget {
  const MountOptionsDialog({required this.block, super.key});

  final UObject block;

  @override
  State<MountOptionsDialog> createState() => _MountOptionsDialogState();
}

class _MountOptionsDialogState extends State<MountOptionsDialog> {
  late final Map<String, Object?>? _entry = widget.block.configuration("fstab");
  late bool _defaults = _entry == null;
  late final (Set<String>, String) _split = splitOptions(
    _entry?["opts"] as String? ?? "nosuid,nodev,nofail,x-gvfs-show",
    const {"noauto", "x-gvfs-show", "x-udisks-auth"},
  );
  late bool _startup = !_split.$1.contains("noauto");
  late bool _show = _split.$1.contains("x-gvfs-show");
  late bool _auth = _split.$1.contains("x-udisks-auth");
  late final TextEditingController _options = TextEditingController(text: _split.$2);
  late final TextEditingController _dir = TextEditingController(
    text: _entry?["dir"] as String? ??
        "/mnt/${widget.block.label.isNotEmpty ? widget.block.label.replaceAll(RegExp(r"\s"), "_") : widget.block.str(iBlock, "IdUUID")}",
  );
  late final TextEditingController _type = TextEditingController(
    text: _entry?["type"] as String? ?? (widget.block.idType.isEmpty ? "auto" : widget.block.idType),
  );
  late final Map<String, String> _ids = {
    if (widget.block.str(iBlock, "IdUUID").isNotEmpty)
      "UUID=${widget.block.str(iBlock, "IdUUID")}": "UUID",
    if (widget.block.label.isNotEmpty) "LABEL=${widget.block.label}": "Label",
    if (widget.block.str(iPartition, "UUID").isNotEmpty)
      "PARTUUID=${widget.block.str(iPartition, "UUID")}": "Partition UUID",
    widget.block.bytes(iBlock, "Device"): widget.block.bytes(iBlock, "Device"),
  };
  late String _fsname = _ids.containsKey(_entry?["fsname"])
      ? _entry!["fsname"]! as String
      : _ids.keys.first;

  @override
  void dispose() {
    _options.dispose();
    _dir.dispose();
    _type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DisksDialog(
      title: "Mount Options",
      action: "OK",
      onAction: !_defaults && !_dir.text.startsWith("/")
          ? null
          : () => Navigator.pop(
                context,
                (
                  _defaults
                      ? null
                      : {
                          "fsname": _fsname,
                          "dir": _dir.text.trim(),
                          "type": _type.text.trim().isEmpty ? "auto" : _type.text.trim(),
                          "opts": joinOptions(
                            [
                              if (!_startup) "noauto",
                              if (_show) "x-gvfs-show",
                              if (_auth) "x-udisks-auth",
                            ],
                            _options.text,
                          ),
                        },
                ),
              ),
      children: [
        _switchRow(
          "Session defaults",
          _defaults,
          (v) => setState(() => _defaults = v),
          subtitle: "Mounted when you open it, under /run/media",
        ),
        if (!_defaults) ...[
          _switchRow("Mount at system startup", _startup, (v) => setState(() => _startup = v)),
          _switchRow("Show in Files", _show, (v) => setState(() => _show = v)),
          _switchRow(
            "Require authorization to mount",
            _auth,
            (v) => setState(() => _auth = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _dir,
                  decoration: InputDecoration(
                    labelText: "Mount point",
                    errorText: _dir.text.startsWith("/") ? null : "A full path, like /mnt/data",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                _gap(),
                TextField(
                  controller: _options,
                  decoration: const InputDecoration(labelText: "Options"),
                ),
                _gap(),
                TextField(
                  controller: _type,
                  decoration: const InputDecoration(labelText: "Filesystem type"),
                ),
              ],
            ),
          ),
          _choiceRow<String>("Identify as", _fsname, _ids, (v) => setState(() => _fsname = v)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text("Saved in /etc/fstab.", style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }
}

/// Encryption Options: the block's crypttab entry. Pops the record
/// `(null,)` for session defaults or `(fields,)` for the new entry.
class EncryptionOptionsDialog extends StatefulWidget {
  const EncryptionOptionsDialog({required this.block, this.passphrase, super.key});

  final UObject block;

  /// The contents of the entry's key file (Block.GetSecretConfiguration).
  final String? passphrase;

  @override
  State<EncryptionOptionsDialog> createState() => _EncryptionOptionsDialogState();
}

class _EncryptionOptionsDialogState extends State<EncryptionOptionsDialog> {
  late final Map<String, Object?>? _entry = widget.block.configuration("crypttab");
  late bool _defaults = _entry == null;
  late final (Set<String>, String) _split =
      splitOptions(_entry?["options"] as String? ?? "", const {"noauto", "x-udisks-auth"});
  late bool _startup = !_split.$1.contains("noauto");
  late bool _auth = _split.$1.contains("x-udisks-auth");
  late final TextEditingController _options = TextEditingController(text: _split.$2);
  late final TextEditingController _name = TextEditingController(
    text: _entry?["name"] as String? ?? "luks-${widget.block.str(iBlock, "IdUUID")}",
  );
  late final TextEditingController _pass = TextEditingController(text: widget.passphrase ?? "");

  /// Where the key file goes: where it is, or a new one in /etc/luks-keys
  /// (the only place UDisks creates key files).
  String _keyPath(String name) {
    final String current = _entry?["passphrase-path"] as String? ?? "";
    return current.isNotEmpty ? current : "/etc/luks-keys/$name";
  }

  @override
  void dispose() {
    _options.dispose();
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String name = _name.text.trim();
    return DisksDialog(
      title: "Encryption Options",
      action: "OK",
      onAction: !_defaults && name.isEmpty
          ? null
          : () => Navigator.pop(
                context,
                (
                  _defaults
                      ? null
                      : {
                          "name": name,
                          "device": _entry?["device"] as String? ??
                              "UUID=${widget.block.str(iBlock, "IdUUID")}",
                          "passphrase-path": _pass.text.isEmpty ? "" : _keyPath(name),
                          "passphrase-contents": _pass.text,
                          "options": joinOptions(
                            [if (!_startup) "noauto", if (_auth) "x-udisks-auth"],
                            _options.text,
                          ),
                        },
                ),
              ),
      children: [
        _switchRow(
          "Session defaults",
          _defaults,
          (v) => setState(() => _defaults = v),
          subtitle: "Unlocked when you open it",
        ),
        if (!_defaults) ...[
          _switchRow("Unlock at system startup", _startup, (v) => setState(() => _startup = v)),
          _switchRow(
            "Require authorization to unlock",
            _auth,
            (v) => setState(() => _auth = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: "Name"),
                  onChanged: (_) => setState(() {}),
                ),
                _gap(),
                TextField(
                  controller: _options,
                  decoration: const InputDecoration(labelText: "Options"),
                ),
                _gap(),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password",
                    helperText: "Optional; stored in /etc/luks-keys, readable by root",
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Resize: a new size between [min] and [max] bytes.
class ResizeDialog extends StatefulWidget {
  const ResizeDialog({required this.current, required this.min, required this.max, super.key});

  final int current;
  final int min;
  final int max;

  @override
  State<ResizeDialog> createState() => _ResizeDialogState();
}

class _ResizeDialogState extends State<ResizeDialog> {
  late double _value = widget.current.toDouble();
  late final TextEditingController _mb =
      TextEditingController(text: (widget.current / 1e6).floor().toString());

  @override
  void dispose() {
    _mb.dispose();
    super.dispose();
  }

  void _set(double v) => setState(() {
        _value = v.clamp(widget.min.toDouble(), widget.max.toDouble());
        _mb.text = (_value / 1e6).floor().toString();
      });

  @override
  Widget build(BuildContext context) {
    final int bytes = _value.round();
    return DisksDialog(
      title: "Resize",
      action: "Resize",
      onAction: bytes == widget.current ? null : () => Navigator.pop(context, bytes),
      children: [
        // ZenitSlider runs from 0 to 1.
        if (widget.max > widget.min)
          ZenitSlider(
            value: (_value - widget.min) / (widget.max - widget.min),
            trackColor: trackColor(Theme.of(context)),
            onChanged: (f) => _set(widget.min + f * (widget.max - widget.min)),
          ),
        _gap(),
        TextField(
          controller: _mb,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: "Size (MB)",
            helperText:
                "${formatSize(widget.min)} to ${formatSize(widget.max)}, free after: ${formatSize(widget.max - bytes)}",
          ),
          onSubmitted: (v) => _set((int.tryParse(v) ?? 0) * 1e6),
          onChanged: (v) {
            final int? mb = int.tryParse(v);
            if (mb != null && mb * 1e6 >= widget.min && mb * 1e6 <= widget.max) {
              setState(() => _value = mb * 1e6);
            }
          },
        ),
      ],
    );
  }
}

/// Drive Settings (ATA): standby timeout, power management, write cache.
/// Pops the new Drive.Configuration.
class DriveSettingsDialog extends StatefulWidget {
  const DriveSettingsDialog({required this.drive, super.key});

  final UObject drive;

  @override
  State<DriveSettingsDialog> createState() => _DriveSettingsDialogState();
}

class _DriveSettingsDialogState extends State<DriveSettingsDialog> {
  late final Map<String, Object?> _config = {
    for (final MapEntry<String, DBusValue> e
        in (widget.drive.ifaces[iDrive]?["Configuration"]?.asStringVariantDict() ?? {})
            .entries)
      e.key: e.value.toNative(),
  };

  // hdparm -S: 1-240 are 5 s steps, 241-251 are 30 min steps.
  static const Map<int, String> _standby = {
    12: "1 minute",
    60: "5 minutes",
    120: "10 minutes",
    180: "15 minutes",
    241: "30 minutes",
    242: "1 hour",
    244: "2 hours",
  };
  static const Map<int, String> _apm = {
    1: "Lowest power, spins down",
    127: "Balanced, spins down",
    128: "Low power, no spin down",
    254: "Best performance",
  };

  bool _supported(String prop) => widget.drive.flag(iAta, prop);

  Widget _setting<T>(
    String key,
    String title,
    String choiceTitle,
    T fallback,
    Map<T, String> choices,
  ) {
    final bool on = _config.containsKey(key);
    final T value = choices.containsKey(_config[key]) ? _config[key] as T : fallback;
    return Column(
      children: [
        _switchRow(
          title,
          on,
          (v) => setState(() => v ? _config[key] = fallback : _config.remove(key)),
          subtitle: on ? null : "Left as the drive starts",
        ),
        if (on) _choiceRow<T>(choiceTitle, value, choices, (v) => setState(() => _config[key] = v)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DisksDialog(
      title: "Drive Settings",
      action: "OK",
      onAction: () => Navigator.pop(context, _config),
      children: [
        if (_supported("PmSupported"))
          _setting<int>("ata-pm-standby", "Standby timeout", "Spin down after", 120, _standby),
        if (_supported("ApmSupported"))
          _setting<int>("ata-apm-level", "Power management", "Level", 127, _apm),
        if (_supported("WriteCacheSupported"))
          _setting<bool>("ata-write-cache-enabled", "Write cache", "Cache", true, const {
            true: "On",
            false: "Off",
          }),
      ],
    );
  }
}

/// Attach Disk Image: whether the loop device is read-only. Pops the choice.
class AttachImageDialog extends StatefulWidget {
  const AttachImageDialog({required this.name, super.key});

  /// The image file's name.
  final String name;

  @override
  State<AttachImageDialog> createState() => _AttachImageDialogState();
}

class _AttachImageDialogState extends State<AttachImageDialog> {
  bool _readOnly = true;

  @override
  Widget build(BuildContext context) {
    return DisksDialog(
      title: "Attach Disk Image",
      action: "Attach",
      onAction: () => Navigator.pop(context, _readOnly),
      children: [
        Text("${widget.name} will show up as a drive until it's detached."),
        _gap(),
        _switchRow(
          "Read-only",
          _readOnly,
          (v) => setState(() => _readOnly = v),
          subtitle: "Nothing can change the image",
        ),
      ],
    );
  }
}

/// New Disk Image: a name and a size. Pops (name, bytes).
class NewImageDialog extends StatefulWidget {
  const NewImageDialog({super.key});

  @override
  State<NewImageDialog> createState() => _NewImageDialogState();
}

class _NewImageDialogState extends State<NewImageDialog> {
  final TextEditingController _name = TextEditingController(text: "Disk Image");
  final TextEditingController _size = TextEditingController(text: "1000");

  @override
  void dispose() {
    _name.dispose();
    _size.dispose();
    super.dispose();
  }

  int? get _bytes {
    final double? mb = double.tryParse(_size.text.trim());
    return mb == null || mb < 1 ? null : (mb * 1e6).round() ~/ 512 * 512;
  }

  @override
  Widget build(BuildContext context) {
    final String name = _name.text.trim();
    return DisksDialog(
      title: "New Disk Image",
      action: "Next",
      onAction: name.isEmpty || name.contains("/") || _bytes == null
          ? null
          : () => Navigator.pop(context, (name, _bytes!)),
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Name"),
          onChanged: (_) => setState(() {}),
        ),
        _gap(),
        TextField(
          controller: _size,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp("[0-9.]"))],
          decoration: const InputDecoration(
            labelText: "Size (MB)",
            helperText: "Sparse: the file only takes the space written to it",
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// Take Ownership: makes the user the owner of a filesystem's files. Pops
/// whether to do it for everything inside.
class TakeOwnershipDialog extends StatefulWidget {
  const TakeOwnershipDialog({required this.volume, super.key});

  /// Names the volume.
  final String volume;

  @override
  State<TakeOwnershipDialog> createState() => _TakeOwnershipDialogState();
}

class _TakeOwnershipDialogState extends State<TakeOwnershipDialog> {
  bool _recursive = false;

  @override
  Widget build(BuildContext context) {
    return DisksDialog(
      title: "Take Ownership",
      action: "Take Ownership",
      destructive: _recursive,
      onAction: () => Navigator.pop(context, _recursive),
      children: [
        Text("You become the owner of the top folder of ${widget.volume}."),
        _gap(),
        _switchRow(
          "Everything inside",
          _recursive,
          (v) => setState(() => _recursive = v),
          subtitle: "Every file and folder on it becomes yours; this can't be undone",
        ),
      ],
    );
  }
}
