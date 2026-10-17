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
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:logging/logging.dart';

/// What apps can be using, shown with its color in the taskbar and Quick
/// Settings while some app does.
enum PrivacyUse {
  screen("Screen recording", Color(0xFFEF4444)),
  microphone("Microphone", Color(0xFFF59E0B)),
  camera("Camera", Color(0xFF22C55E));

  const PrivacyUse(this.label, this.color);

  final String label;
  final Color color;
}

/// Which apps record the screen, the microphone or the camera right now.
///
/// From PipeWire's graph (`pw-dump --monitor`): screen casts (through the
/// desktop portal), microphone recordings and cameras used through
/// PipeWire. Apps that open a camera directly (/dev/video*, most video call
/// apps) are found by watching the camera devices.
class PrivacyMonitor extends ChangeNotifier {
  PrivacyMonitor._();

  static final PrivacyMonitor instance = PrivacyMonitor._();
  static final Logger _logger = Logger("PrivacyMonitor");

  /// Apps (names) per use; a use is missing when nothing uses it.
  Map<PrivacyUse, Set<String>> get uses => _uses;
  Map<PrivacyUse, Set<String>> _uses = const {};

  bool inUse(PrivacyUse use) => _uses[use]?.isNotEmpty == true;

  Process? _pwDump;
  final Map<int, Map<String, Object?>> _objects = {};
  Map<PrivacyUse, Set<String>> _fromPipeWire = const {};
  Set<String> _cameraDevices = const {};
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    unawaited(_watchPipeWire());
    unawaited(_watchCameras());
  }

  // PipeWire.

  Future<void> _watchPipeWire() async {
    int failures = 0;
    while (failures < 5) {
      final DateTime started = DateTime.now();
      try {
        final Process process = await Process.start(
          "pw-dump",
          ["--monitor", "--no-colors"],
        );
        _pwDump = process;
        unawaited(process.stderr.drain<void>());
        final _JsonSplitter splitter = _JsonSplitter();
        await for (final String chunk
            in process.stdout.transform(utf8.decoder)) {
          for (final String value in splitter.add(chunk)) {
            _onPipeWire(value);
          }
        }
        await process.exitCode;
      } on ProcessException {
        _logger.info("pw-dump isn't installed: no microphone and screen "
            "recording indicators");
        return;
      } on Object catch (e) {
        _logger.info("Couldn't follow PipeWire: $e");
      }
      _objects.clear();
      _fromPipeWire = const {};
      _publish();
      // PipeWire restarted (or isn't up yet): try again, unless it keeps
      // failing right away.
      failures =
          DateTime.now().difference(started).inSeconds < 10 ? failures + 1 : 0;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  void _onPipeWire(String json) {
    final Object? value;
    try {
      value = jsonDecode(json);
    } on FormatException {
      return;
    }
    if (value is! List) return;
    for (final Object? object in value) {
      if (object is! Map<String, Object?>) continue;
      final int? id = (object["id"] as num?)?.toInt();
      if (id == null) continue;
      if (object["info"] == null && object["type"] == null) {
        _objects.remove(id);
      } else {
        _objects[id] = object;
      }
    }
    _fromPipeWire = _computePipeWire();
    _publish();
  }

  static Map<String, Object?> _info(Map<String, Object?>? object) =>
      (object?["info"] as Map<String, Object?>?) ?? const {};

  static Map<String, Object?> _props(Map<String, Object?>? object) =>
      (_info(object)["props"] as Map<String, Object?>?) ?? const {};

  static String _appName(Map<String, Object?> props) {
    for (final String key in [
      "application.name",
      "application.process.binary",
      "node.name",
    ]) {
      final Object? value = props[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return "An app";
  }

  bool _isScreenCast(Map<String, Object?>? node) {
    final Map<String, Object?> props = _props(node);
    if (props["media.class"] != "Video/Source") return false;
    final String name = props["node.name"]?.toString() ?? "";
    final String binary = props["application.process.binary"]?.toString() ?? "";
    return name.startsWith("xdpw") ||
        binary.contains("xdg-desktop-portal") ||
        name.contains("screen");
  }

  Map<PrivacyUse, Set<String>> _computePipeWire() {
    final Map<int, Map<String, Object?>> nodes = {};
    final List<Map<String, Object?>> links = [];
    for (final MapEntry<int, Map<String, Object?>> e in _objects.entries) {
      switch (e.value["type"]) {
        case "PipeWire:Interface:Node":
          nodes[e.key] = e.value;
        case "PipeWire:Interface:Link":
          links.add(_info(e.value));
      }
    }
    // What feeds each node.
    Iterable<Map<String, Object?>> sourcesOf(int id) sync* {
      for (final Map<String, Object?> link in links) {
        if ((link["input-node-id"] as num?)?.toInt() != id) continue;
        final Map<String, Object?>? source =
            nodes[(link["output-node-id"] as num?)?.toInt()];
        if (source != null) yield source;
      }
    }

    Iterable<Map<String, Object?>> consumersOf(int id) sync* {
      for (final Map<String, Object?> link in links) {
        if ((link["output-node-id"] as num?)?.toInt() != id) continue;
        final Map<String, Object?>? consumer =
            nodes[(link["input-node-id"] as num?)?.toInt()];
        if (consumer != null) yield consumer;
      }
    }

    final Map<PrivacyUse, Set<String>> uses = {};
    void add(PrivacyUse use, String app) =>
        (uses[use] ??= <String>{}).add(app);

    for (final MapEntry<int, Map<String, Object?>> e in nodes.entries) {
      final Map<String, Object?> info = _info(e.value);
      if (info["state"] != "running") continue;
      final Map<String, Object?> props = _props(e.value);
      switch (props["media.class"]) {
        case "Stream/Input/Audio":
          // Recording what plays (a sink's monitor) isn't the microphone.
          if (props["stream.capture.sink"] == true ||
              props["stream.monitor"] == true) {
            continue;
          }
          if (sourcesOf(e.key)
              .any((s) => _props(s)["media.class"] == "Audio/Sink")) {
            continue;
          }
          add(PrivacyUse.microphone, _appName(props));
        case "Stream/Input/Video":
          final List<Map<String, Object?>> sources = sourcesOf(e.key).toList();
          if (sources.any(_isScreenCast)) {
            add(PrivacyUse.screen, _appName(props));
          } else {
            add(PrivacyUse.camera, _appName(props));
          }
        case "Video/Source":
          if (!_isScreenCast(e.value)) continue;
          // Consumers that aren't PipeWire streams of their own (a browser
          // reading the portal's stream directly).
          final List<String> apps = [
            for (final Map<String, Object?> c in consumersOf(e.key))
              _appName(_props(c)),
          ];
          if (apps.isEmpty) apps.add("An app");
          for (final String app in apps) {
            add(PrivacyUse.screen, app);
          }
      }
    }
    return uses;
  }

  // Cameras used directly.

  Future<void> _watchCameras() async {
    final ReceivePort port = ReceivePort();
    port.listen((Object? message) {
      if (message is List) {
        _cameraDevices = {for (final Object? m in message) m.toString()};
        _publish();
      }
    });
    try {
      await Isolate.spawn(_cameraWatcher, port.sendPort);
    } on Object catch (e) {
      _logger.info("Couldn't watch the cameras: $e");
    }
  }

  void _publish() {
    final Map<PrivacyUse, Set<String>> uses = {
      for (final MapEntry<PrivacyUse, Set<String>> e in _fromPipeWire.entries)
        e.key: {...e.value},
    };
    if (_cameraDevices.isNotEmpty) {
      (uses[PrivacyUse.camera] ??= <String>{}).addAll(_cameraDevices);
    }
    uses.removeWhere((_, apps) => apps.isEmpty);
    if (_same(uses, _uses)) return;
    _uses = uses;
    notifyListeners();
  }

  static bool _same(
    Map<PrivacyUse, Set<String>> a,
    Map<PrivacyUse, Set<String>> b,
  ) {
    if (a.length != b.length) return false;
    for (final MapEntry<PrivacyUse, Set<String>> e in a.entries) {
      if (!setEquals(e.value, b[e.key])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _pwDump?.kill();
    super.dispose();
  }
}

/// Splits a stream of JSON values (pw-dump prints one array per update)
/// into the text of each value.
class _JsonSplitter {
  final StringBuffer _buffer = StringBuffer();
  int _depth = 0;
  bool _inString = false;
  bool _escaped = false;

  List<String> add(String chunk) {
    final List<String> values = [];
    for (int i = 0; i < chunk.length; i++) {
      final String c = chunk[i];
      if (_depth == 0 && c != "[" && c != "{") continue;
      _buffer.write(c);
      if (_inString) {
        if (_escaped) {
          _escaped = false;
        } else if (c == r"\") {
          _escaped = true;
        } else if (c == '"') {
          _inString = false;
        }
        continue;
      }
      switch (c) {
        case '"':
          _inString = true;
        case "[" || "{":
          _depth++;
        case "]" || "}":
          _depth--;
          if (_depth == 0) {
            values.add(_buffer.toString());
            _buffer.clear();
          }
      }
    }
    return values;
  }
}

// The camera watcher runs on its own isolate: it blocks reading inotify
// events of the camera devices (opened, closed) and then looks for the
// processes that have one open.

const int _inOpen = 0x20;
const int _inCloseWrite = 0x08;
const int _inCloseNoWrite = 0x10;
const int _inCloexec = 0x80000;

typedef _InotifyInitNative = Int32 Function(Int32 flags);
typedef _InotifyInit = int Function(int flags);
typedef _AddWatchNative = Int32 Function(Int32 fd, Pointer<Utf8> path, Uint32 mask);
typedef _AddWatch = int Function(int fd, Pointer<Utf8> path, int mask);
typedef _ReadNative = IntPtr Function(Int32 fd, Pointer<Uint8> buf, IntPtr count);
typedef _Read = int Function(int fd, Pointer<Uint8> buf, int count);

Future<void> _cameraWatcher(SendPort port) async {
  final List<String> devices = [
    for (final FileSystemEntity e in Directory("/dev").listSync())
      if (e.path.startsWith("/dev/video")) e.path,
  ];
  if (devices.isEmpty) return;
  final DynamicLibrary libc = DynamicLibrary.process();
  final _InotifyInit init =
      libc.lookupFunction<_InotifyInitNative, _InotifyInit>("inotify_init1");
  final _AddWatch addWatch =
      libc.lookupFunction<_AddWatchNative, _AddWatch>("inotify_add_watch");
  final _Read read = libc.lookupFunction<_ReadNative, _Read>("read");

  final int fd = init(_inCloexec);
  if (fd < 0) return;
  for (final String device in devices) {
    final Pointer<Utf8> path = device.toNativeUtf8();
    addWatch(fd, path, _inOpen | _inCloseWrite | _inCloseNoWrite);
    malloc.free(path);
  }
  port.send(_cameraUsers(devices));
  final Pointer<Uint8> buffer = malloc<Uint8>(4096);
  while (true) {
    // Blocks until a camera is opened or closed.
    if (read(fd, buffer, 4096) <= 0) break;
    // Let the app finish opening (or closing) everything first.
    sleep(const Duration(milliseconds: 300));
    port.send(_cameraUsers(devices));
  }
  malloc.free(buffer);
}

/// Names of the processes (of this user) that have a camera open, except
/// PipeWire's own (those apps are known from PipeWire).
List<String> _cameraUsers(List<String> devices) {
  final Set<String> names = {};
  for (final FileSystemEntity proc in Directory("/proc").listSync()) {
    final String pid = proc.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (int.tryParse(pid) == null) continue;
    List<FileSystemEntity> fds;
    try {
      fds = Directory("/proc/$pid/fd").listSync();
    } on FileSystemException {
      continue;
    }
    for (final FileSystemEntity entry in fds) {
      String target;
      try {
        target = Link(entry.path).targetSync();
      } on FileSystemException {
        continue;
      }
      if (!target.startsWith("/dev/video")) continue;
      try {
        final String comm = File("/proc/$pid/comm").readAsStringSync().trim();
        if (comm == "pipewire" || comm == "wireplumber") break;
        names.add(comm.isEmpty ? "An app" : comm);
      } on FileSystemException {
        // Gone meanwhile.
      }
      break;
    }
  }
  return names.toList();
}
