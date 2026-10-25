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
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dahlia_apps/apps/disks/dialogs.dart';
import 'package:dahlia_apps/apps/disks/udisks.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dbus/dbus.dart';
import 'package:path/path.dart' as p;

/// The block device, opened by UDisks (OpenForBackup, OpenForRestore,
/// OpenForBenchmark) after asking polkit.
Future<RandomAccessFile> openBlock(UDisksClient udisks, UObject block, String method) async {
  final List<DBusValue> r =
      await udisks.call(block.path, iBlock, method, [options()], reply: "h");
  return (r.first as DBusUnixFd).handle.toFile();
}

/// Copies a disk to a file or back, with progress and Cancel. Pops true when
/// everything was copied.
class TransferDialog extends StatefulWidget {
  const TransferDialog({
    required this.title,
    required this.from,
    required this.to,
    required this.length,
    super.key,
  });

  final String title;
  final RandomAccessFile from;
  final RandomAccessFile to;
  final int length;

  @override
  State<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<TransferDialog> {
  final Stopwatch _clock = Stopwatch()..start();
  int _done = 0;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final Uint8List buffer = Uint8List(4 * mib);
    int shown = 0;
    try {
      while (_done < widget.length && !_cancelled) {
        final int n = await widget.from
            .readInto(buffer, 0, math.min(buffer.length, widget.length - _done));
        if (n == 0) throw const FileSystemException("Unexpected end of data");
        await widget.to.writeFrom(buffer, 0, n);
        _done += n;
        if (_clock.elapsedMilliseconds - shown > 200 && mounted) {
          shown = _clock.elapsedMilliseconds;
          setState(() {});
        }
      }
      await widget.to.flush();
      if (mounted) Navigator.pop(context, !_cancelled);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is FileSystemException ? e.osError?.message ?? e.message : "$e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double rate = _done / math.max(1, _clock.elapsedMicroseconds); // MB/s
    final int left = rate > 0 ? ((widget.length - _done) / rate / 1e6).round() : 0;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: _done / math.max(1, widget.length),
              backgroundColor: progressTrackColor(Theme.of(context)),
            ),
            const SizedBox(height: 12),
            Text(
              _error ??
                  "${formatSize(_done)} of ${formatSize(widget.length)}"
                      "${_done > 0 ? ", ${rate.toStringAsFixed(1)} MB/s, ${formatDuration(Duration(seconds: left))} left" : ""}",
              style: _error == null ? null : TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
      actions: [
        if (_error != null)
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text("Close"))
        else
          TextButton(
            onPressed: _cancelled ? null : () => setState(() => _cancelled = true),
            child: const Text("Cancel"),
          ),
      ],
    );
  }
}

Future<bool> _transfer(
  BuildContext context,
  String title,
  RandomAccessFile from,
  RandomAccessFile to,
  int length,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TransferDialog(title: title, from: from, to: to, length: length),
    ) ==
    true;

/// Create Disk Image: copies [block] into a raw .img file.
Future<void> createImage(
  BuildContext context,
  UDisksClient udisks,
  UObject block,
  String name,
) async {
  final String? path = await showFileDialog(
    context,
    mode: FileDialogMode.save,
    title: "Create Disk Image",
    suggestedName: "$name.img",
  );
  if (path == null || !context.mounted) return;
  final RandomAccessFile source = await openBlock(udisks, block, "OpenForBackup");
  RandomAccessFile? target;
  try {
    target = await File(path).open(mode: FileMode.write);
    if (!context.mounted ||
        !await _transfer(context, "Creating ${p.basename(path)}", source, target, block.size)) {
      await target.close();
      target = null;
      await File(path).delete();
    }
  } finally {
    await source.close();
    await target?.close();
  }
}

/// Restore Disk Image: writes an image file over [block] after [confirm]
/// (which names the disk and its contents) and [prepare] (unmounting it).
/// False when it stopped part way.
Future<bool> restoreImage(
  BuildContext context,
  UDisksClient udisks,
  UObject block, {
  required String target,
  required Future<void> Function() prepare,
}) async {
  final String? path = await showFileDialog(
    context,
    title: "Restore Disk Image",
    extensions: imageExtensions,
  );
  if (path == null || !context.mounted) return true;
  final int length = await File(path).length();
  if (length > block.size) {
    throw FileSystemException(
      "The image (${formatSize(length)}) is bigger than $target (${formatSize(block.size)})",
    );
  }
  if (!context.mounted ||
      !await confirmDestructive(
        context,
        title: "Restore Disk Image",
        message: "Everything on $target will be replaced by ${p.basename(path)} "
            "(${formatSize(length)}).",
        action: "Restore",
      )) {
    return true;
  }
  await prepare();
  final RandomAccessFile source = await File(path).open();
  try {
    final RandomAccessFile disk = await openBlock(udisks, block, "OpenForRestore");
    try {
      return context.mounted &&
          await _transfer(context, "Restoring ${p.basename(path)}", source, disk, length);
    } finally {
      await disk.close();
    }
  } finally {
    await source.close();
  }
}

// The benchmark reads with O_DIRECT (UDisks opens the device that way), which
// needs aligned buffers Dart can't allocate: it runs on its own isolate with
// pread() on page aligned memory.
typedef _Buffer = ffi.Pointer<ffi.Void>;
final ffi.DynamicLibrary _libc = ffi.DynamicLibrary.process();
final int Function(ffi.Pointer<_Buffer>, int, int) _memalign = _libc.lookupFunction<
    ffi.Int32 Function(ffi.Pointer<_Buffer>, ffi.Size, ffi.Size),
    int Function(ffi.Pointer<_Buffer>, int, int)>("posix_memalign");
final _Buffer Function(int) _malloc =
    _libc.lookupFunction<_Buffer Function(ffi.Size), _Buffer Function(int)>("malloc");
final void Function(_Buffer) _free =
    _libc.lookupFunction<ffi.Void Function(_Buffer), void Function(_Buffer)>("free");
final int Function(int, _Buffer, int, int) _pread = _libc.lookupFunction<
    ffi.IntPtr Function(ffi.Int32, _Buffer, ffi.Size, ffi.Int64),
    int Function(int, _Buffer, int, int)>("pread");

const int _align = 4096;
const int _rateSamples = 100;
const int _accessSamples = 1000;

/// Reads [size] bytes of the device on [fd]: transfer rate at evenly spread
/// positions (`(0, position, MB/s)`), then access time at random ones
/// (`(1, position, ms)`), as GNOME Disks measures them. Errors are strings.
void _benchmark((SendPort, int, int) args) {
  final (SendPort out, int fd, int size) = args;
  final int sample = math.min(10 * mib, size ~/ _rateSamples ~/ _align * _align);
  final ffi.Pointer<_Buffer> slot = _malloc(8).cast();
  if (sample < _align || _memalign(slot, _align, sample) != 0) {
    _free(slot.cast());
    out.send("The device is too small to benchmark");
    return;
  }
  final _Buffer buffer = slot.value;
  final Stopwatch clock = Stopwatch();
  bool read(int offset, int length) {
    clock
      ..reset()
      ..start();
    if (_pread(fd, buffer, length, offset) == length) return true;
    out.send("Couldn't read at ${formatSize(offset)}");
    return false;
  }

  try {
    for (int i = 0; i < _rateSamples; i++) {
      final int offset = (size - sample) * i ~/ (_rateSamples - 1) ~/ _align * _align;
      if (!read(offset, sample)) return;
      out.send((0, offset / size, sample / math.max(1, clock.elapsedMicroseconds)));
    }
    final math.Random random = math.Random();
    for (int i = 0; i < _accessSamples; i++) {
      final int offset = (random.nextDouble() * (size - _align)).floor() ~/ _align * _align;
      if (!read(offset, _align)) return;
      out.send((1, offset / size, clock.elapsedMicroseconds / 1000));
    }
  } finally {
    _free(buffer);
    _free(slot.cast());
  }
}

/// The descriptor number behind a file UDisks passed (needed for pread):
/// the one in /proc/self/fd that newly points at the device, else the only
/// one that appeared during the call (a device node under another name, or
/// a test's image file). Numbers are compared with their targets: the passed
/// descriptor can reuse the number the previous listing itself had open.
Future<(RandomAccessFile, int)> _openRaw(UDisksClient udisks, UObject block) async {
  Map<String, String> fds() => {
        for (final FileSystemEntity e in Directory("/proc/self/fd").listSync())
          p.basename(e.path): () {
            try {
              return Link(e.path).targetSync();
            } on FileSystemException {
              return ""; // The listing's own descriptor, closed by now.
            }
          }(),
      };
  final Map<String, String> before = fds();
  final RandomAccessFile file = await openBlock(udisks, block, "OpenForBenchmark");
  final String device = File(block.bytes(iBlock, "Device")).resolveSymbolicLinksSync();
  final List<MapEntry<String, String>> appeared =
      fds().entries.where((fd) => fd.value.isNotEmpty && before[fd.key] != fd.value).toList();
  final MapEntry<String, String>? passed = appeared.where((fd) => fd.value == device).firstOrNull ??
      (appeared.length == 1 ? appeared.single : null);
  if (passed != null) return (file, int.parse(passed.key));
  await file.close();
  throw const FileSystemException("Couldn't open the device for reading");
}

/// Benchmark: read rate and access time across [block].
class BenchmarkDialog extends StatefulWidget {
  const BenchmarkDialog({required this.udisks, required this.block, required this.name, super.key});

  final UDisksClient udisks;
  final UObject block;
  final String name;

  @override
  State<BenchmarkDialog> createState() => _BenchmarkDialogState();
}

class _BenchmarkDialogState extends State<BenchmarkDialog> {
  final List<Offset> _rates = [];
  final List<Offset> _access = [];
  bool _running = false;
  String? _error;
  Isolate? _isolate;
  ReceivePort? _port;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  Future<void> _start() async {
    setState(() {
      _rates.clear();
      _access.clear();
      _error = null;
      _running = true;
    });
    final RandomAccessFile file;
    final int fd;
    try {
      (file, fd) = await _openRaw(widget.udisks, widget.block);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = describeError(e is FileSystemException ? e.message : e);
        });
      }
      return;
    }
    final ReceivePort port = _port = ReceivePort();
    final ReceivePort exit = ReceivePort();
    port.listen((message) {
      if (!mounted) return;
      setState(() {
        if (message is String) {
          _error = message;
        } else if (message case (0, final double at, final double rate)) {
          _rates.add(Offset(at, rate));
        } else if (message case (1, final double at, final double ms)) {
          _access.add(Offset(at, ms));
        }
      });
    });
    // The descriptor is closed only once the isolate stopped reading it.
    exit.listen((_) {
      exit.close();
      port.close();
      unawaited(file.close());
      if (mounted && identical(_port, port)) setState(() => _running = false);
    });
    _isolate = await Isolate.spawn(
      _benchmark,
      (port.sendPort, fd, widget.block.size),
      onExit: exit.sendPort,
      onError: exit.sendPort,
    );
    if (!mounted) _stop();
  }

  static Color _opposite(Color c) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl.withHue((hsl.hue + 180) % 360).toColor();
  }

  static double _mean(Iterable<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Iterable<double> rates = _rates.map((o) => o.dy);
    final Iterable<double> access = _access.map((o) => o.dy);
    return AlertDialog(
      title: Text("Benchmark ${widget.name}"),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              children: [
                InfoRow(
                  label: "Average read rate",
                  value: rates.isEmpty
                      ? "–"
                      : "${_mean(rates).toStringAsFixed(1)} MB/s "
                          "(${rates.reduce(math.min).toStringAsFixed(1)}–${rates.reduce(math.max).toStringAsFixed(1)}, "
                          "${rates.length} of $_rateSamples samples)",
                ),
                InfoRow(
                  label: "Average access time",
                  value: access.isEmpty
                      ? "–"
                      : "${_mean(access).toStringAsFixed(2)} ms (${access.length} of $_accessSamples samples)",
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            SizedBox(
              height: 220,
              child: CustomPaint(
                painter: _BenchmarkChart(
                  rates: _rates,
                  access: _access,
                  rateColor: theme.colorScheme.primary,
                  // Zenit's tertiary is the accent too: the opposite hue.
                  accessColor: _opposite(theme.colorScheme.primary),
                  gridColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  textStyle: theme.textTheme.bodySmall!,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Reads only; nothing on the device changes.",
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        if (_running)
          TextButton(
            onPressed: () {
              _stop();
            },
            child: const Text("Stop"),
          )
        else
          TextButton(onPressed: _start, child: Text(_rates.isEmpty ? "Start Benchmark" : "Run Again")),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
      ],
    );
  }
}

/// Read rate (line, left scale) and access times (dots, right scale) over
/// the position on the device.
class _BenchmarkChart extends CustomPainter {
  const _BenchmarkChart({
    required this.rates,
    required this.access,
    required this.rateColor,
    required this.accessColor,
    required this.gridColor,
    required this.textStyle,
  });

  final List<Offset> rates;
  final List<Offset> access;
  final Color rateColor;
  final Color accessColor;
  final Color gridColor;
  final TextStyle textStyle;

  void _label(Canvas canvas, String text, Offset at, {bool right = false, Color? color}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: textStyle.copyWith(color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, right ? at - Offset(tp.width, 0) : at);
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double pad = 48;
    final Rect area = Rect.fromLTRB(pad, 8, size.width - pad, size.height - 20);
    final double maxRate = rates.isEmpty ? 1 : rates.map((o) => o.dy).reduce(math.max) * 1.1;
    final double maxMs = access.isEmpty ? 1 : access.map((o) => o.dy).reduce(math.max) * 1.1;
    final Paint grid = Paint()..color = gridColor;
    for (int i = 0; i <= 4; i++) {
      final double y = area.bottom - area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
      if (rates.isNotEmpty) {
        _label(canvas, (maxRate * i / 4).toStringAsFixed(0), Offset(area.left - 6, y - 8),
            right: true, color: rateColor);
      }
      if (access.isNotEmpty) {
        _label(canvas, (maxMs * i / 4).toStringAsFixed(maxMs < 1 ? 2 : maxMs < 10 ? 1 : 0),
            Offset(area.right + 6, y - 8), color: accessColor);
      }
    }
    _label(canvas, "MB/s", Offset(area.left - 6, size.height - 16), right: true, color: rateColor);
    _label(canvas, "ms", Offset(area.right + 6, size.height - 16), color: accessColor);
    _label(canvas, "0%", Offset(area.left, size.height - 16));
    _label(canvas, "100%", Offset(area.right, size.height - 16), right: true);

    Offset at(Offset o, double max) =>
        Offset(area.left + area.width * o.dx, area.bottom - area.height * (o.dy / max));
    final Paint dot = Paint()..color = accessColor.withValues(alpha: 0.6);
    for (final Offset o in access) {
      canvas.drawCircle(at(o, maxMs), 1.5, dot);
    }
    if (rates.length > 1) {
      canvas.drawPath(
        Path()..addPolygon([for (final Offset o in rates) at(o, maxRate)], false),
        Paint()
          ..color = rateColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_BenchmarkChart old) => true;
}
