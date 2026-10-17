// Copyright 2026 The dahliaOS Authors
// SPDX-License-Identifier: Apache-2.0

// pangolin-portal: Pangolin's backend of the desktop portals
// (xdg-desktop-portal) for the file chooser and the "Open With" dialog, the
// dialogs every app (flatpak or not) gets through the portal.
//
// D-Bus activated as org.freedesktop.impl.portal.desktop.pangolin
// (share/xdg-desktop-portal/portals/pangolin.portal). Each request shows a
// dialog window of the dahliaOS apps (`dahlia_apps file_chooser` or
// `dahlia_apps app_chooser`) with the request in a JSON file and gets its
// answer in another. Leaves after a while without requests.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:path/path.dart' as p;

const String busName = "org.freedesktop.impl.portal.desktop.pangolin";
const String fileChooserInterface = "org.freedesktop.impl.portal.FileChooser";
const String appChooserInterface = "org.freedesktop.impl.portal.AppChooser";
const String requestInterface = "org.freedesktop.impl.portal.Request";

/// Responses of the portal API.
const int success = 0;
const int cancelled = 1;
const int failed = 2;

const Duration idleTimeout = Duration(minutes: 3);

late final DBusClient bus;
final Map<String, _Request> requests = {};
Timer? idleTimer;

Future<void> main(List<String> args) async {
  bus = DBusClient.session();
  final DBusRequestNameReply reply = await bus.requestName(
    busName,
    flags: {DBusRequestNameFlag.doNotQueue},
  );
  if (reply != DBusRequestNameReply.primaryOwner &&
      reply != DBusRequestNameReply.alreadyOwner) {
    stderr.writeln("pangolin-portal: $busName is already provided");
    await bus.close();
    exit(0);
  }
  await bus.registerObject(_Portal());
  for (final ProcessSignal signal in [ProcessSignal.sigterm, ProcessSignal.sigint]) {
    signal.watch().listen((_) => _quit());
  }
  _scheduleIdleExit();
}

void _scheduleIdleExit() {
  idleTimer?.cancel();
  if (requests.isNotEmpty) return;
  idleTimer = Timer(idleTimeout, _quit);
}

Future<void> _quit() async {
  for (final _Request r in requests.values.toList()) {
    r.process?.kill();
  }
  try {
    await bus.releaseName(busName);
    await bus.close();
  } on Object {
    // The bus may be gone already (end of the session).
  }
  exit(0);
}

/// The dialogs program (dahlia_apps), next to this one in the
/// installation: <prefix>/libexec/pangolin/pangolin-portal ->
/// <prefix>/bin/dahlia_apps.
String get dialogsProgram {
  final String? override = Platform.environment["PANGOLIN_DAHLIA_APPS"];
  if (override != null && override.isNotEmpty) return override;
  final String prefix = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
  final String installed = p.join(prefix, "bin", "dahlia_apps");
  return File(installed).existsSync() ? installed : "dahlia_apps";
}

Directory get runtimeDir {
  final String base =
      Platform.environment["XDG_RUNTIME_DIR"] ?? Directory.systemTemp.path;
  final Directory dir = Directory(p.join(base, "pangolin-portal"));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    Process.runSync("chmod", ["700", dir.path]);
  }
  return dir;
}

class _Portal extends DBusObject {
  _Portal() : super(DBusObjectPath("/org/freedesktop/portal/desktop"));

  @override
  List<DBusIntrospectInterface> introspect() => [
        DBusIntrospectInterface(fileChooserInterface, methods: [
          for (final String name in ["OpenFile", "SaveFile", "SaveFiles"])
            DBusIntrospectMethod(name, args: [
              DBusIntrospectArgument(DBusSignature("o"), DBusArgumentDirection.in_, name: "handle"),
              DBusIntrospectArgument(DBusSignature("s"), DBusArgumentDirection.in_, name: "app_id"),
              DBusIntrospectArgument(DBusSignature("s"), DBusArgumentDirection.in_, name: "parent_window"),
              DBusIntrospectArgument(DBusSignature("s"), DBusArgumentDirection.in_, name: "title"),
              DBusIntrospectArgument(DBusSignature("a{sv}"), DBusArgumentDirection.in_, name: "options"),
              DBusIntrospectArgument(DBusSignature("u"), DBusArgumentDirection.out, name: "response"),
              DBusIntrospectArgument(DBusSignature("a{sv}"), DBusArgumentDirection.out, name: "results"),
            ]),
        ]),
        DBusIntrospectInterface(appChooserInterface, methods: [
          DBusIntrospectMethod("ChooseApplication", args: [
            DBusIntrospectArgument(DBusSignature("o"), DBusArgumentDirection.in_, name: "handle"),
            DBusIntrospectArgument(DBusSignature("s"), DBusArgumentDirection.in_, name: "app_id"),
            DBusIntrospectArgument(DBusSignature("s"), DBusArgumentDirection.in_, name: "parent_window"),
            DBusIntrospectArgument(DBusSignature("as"), DBusArgumentDirection.in_, name: "choices"),
            DBusIntrospectArgument(DBusSignature("a{sv}"), DBusArgumentDirection.in_, name: "options"),
            DBusIntrospectArgument(DBusSignature("u"), DBusArgumentDirection.out, name: "response"),
            DBusIntrospectArgument(DBusSignature("a{sv}"), DBusArgumentDirection.out, name: "results"),
          ]),
          DBusIntrospectMethod("UpdateChoices", args: [
            DBusIntrospectArgument(DBusSignature("o"), DBusArgumentDirection.in_, name: "handle"),
            DBusIntrospectArgument(DBusSignature("as"), DBusArgumentDirection.in_, name: "choices"),
          ]),
        ]),
      ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    try {
      switch ((call.interface, call.name)) {
        case (fileChooserInterface, "OpenFile" || "SaveFile" || "SaveFiles"):
          if (call.signature != DBusSignature("osssa{sv}")) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          return await _fileChooser(call);
        case (appChooserInterface, "ChooseApplication"):
          if (call.signature != DBusSignature("ossasa{sv}")) {
            return DBusMethodErrorResponse.invalidArgs();
          }
          return await _appChooser(call);
        case (appChooserInterface, "UpdateChoices"):
          // The dialog lists the apps installed when it opened; one installed
          // meanwhile shows the next time.
          return DBusMethodSuccessResponse();
        default:
          return DBusMethodErrorResponse.unknownMethod();
      }
    } on Object catch (e, stack) {
      stderr.writeln("pangolin-portal: ${call.name} failed: $e\n$stack");
      return DBusMethodSuccessResponse([DBusUint32(failed), DBusDict.stringVariant({})]);
    }
  }

  Future<DBusMethodResponse> _fileChooser(DBusMethodCall call) async {
    final DBusObjectPath handle = call.values[0].asObjectPath();
    final String appId = call.values[1].asString();
    final String parent = call.values[2].asString();
    final String title = call.values[3].asString();
    final Map<String, DBusValue> options = call.values[4].asStringVariantDict();

    final List<Map<String, Object?>> filters = [
      for (final DBusValue f in options["filters"]?.asArray() ?? const []) _filter(f),
    ];
    int? currentFilter;
    final DBusValue? current = options["current_filter"];
    if (current != null) {
      final Map<String, Object?> wanted = _filter(current);
      currentFilter = filters.indexWhere((f) => jsonEncode(f) == jsonEncode(wanted));
      if (currentFilter < 0) {
        filters.add(wanted);
        currentFilter = filters.length - 1;
      }
    }

    String? folder = _bytesPath(options["current_folder"]);
    String? name = options["current_name"]?.asString();
    final String? currentFile = _bytesPath(options["current_file"]);
    if (currentFile != null) {
      folder ??= p.dirname(currentFile);
      name ??= p.basename(currentFile);
    }

    final Map<String, Object?> request = {
      "mode": switch (call.name) {
        "SaveFile" => "save",
        "SaveFiles" => "save_files",
        _ => "open",
      },
      "title": title,
      "acceptLabel": options["accept_label"]?.asString(),
      "multiple": options["multiple"]?.asBoolean() ?? false,
      "directory": options["directory"]?.asBoolean() ?? false,
      "filters": filters,
      "currentFilter": currentFilter,
      "choices": [
        for (final DBusValue c in options["choices"]?.asArray() ?? const []) _choice(c),
      ],
      "folder": folder,
      "name": name,
      "files": [
        for (final DBusValue f in options["files"]?.asArray() ?? const [])
          p.basename(_bytesPath(f) ?? ""),
      ],
      "appId": appId,
      "parent": parent,
    };

    final Map<String, Object?>? answer = await _show(handle, "file_chooser", request);
    if (answer == null || answer["response"] != success) {
      return DBusMethodSuccessResponse([
        DBusUint32(answer == null ? cancelled : (answer["response"] as num?)?.toInt() ?? cancelled),
        DBusDict.stringVariant({}),
      ]);
    }
    final List<String> paths = [
      for (final Object? path in (answer["paths"] as List?) ?? const []) path.toString(),
    ];
    final Map<String, DBusValue> results = {
      "uris": DBusArray.string([for (final String path in paths) Uri.file(path).toString()]),
    };
    final Map<String, Object?> choices = (answer["choices"] as Map?)?.cast<String, Object?>() ?? {};
    if (choices.isNotEmpty) {
      results["choices"] = DBusArray(DBusSignature("(ss)"), [
        for (final MapEntry<String, Object?> c in choices.entries)
          DBusStruct([DBusString(c.key), DBusString(c.value.toString())]),
      ]);
    }
    final int? filter = (answer["currentFilter"] as num?)?.toInt();
    if (filter != null && filter >= 0 && filter < filters.length) {
      results["current_filter"] = _filterValue(filters[filter]);
    }
    return DBusMethodSuccessResponse([DBusUint32(success), DBusDict.stringVariant(results)]);
  }

  Future<DBusMethodResponse> _appChooser(DBusMethodCall call) async {
    final DBusObjectPath handle = call.values[0].asObjectPath();
    final String appId = call.values[1].asString();
    final String parent = call.values[2].asString();
    final List<String> choices = call.values[3].asStringArray().toList();
    final Map<String, DBusValue> options = call.values[4].asStringVariantDict();

    final Map<String, Object?>? answer = await _show(handle, "app_chooser", {
      "choices": choices,
      "lastChoice": options["last_choice"]?.asString(),
      "contentType": options["content_type"]?.asString(),
      "uri": options["uri"]?.asString(),
      "filename": options["filename"]?.asString(),
      "appId": appId,
      "parent": parent,
    });
    final String? choice = answer?["choice"] as String?;
    if (answer == null || answer["response"] != success || choice == null) {
      return DBusMethodSuccessResponse([DBusUint32(cancelled), DBusDict.stringVariant({})]);
    }
    return DBusMethodSuccessResponse([
      DBusUint32(success),
      DBusDict.stringVariant({"choice": DBusString(choice)}),
    ]);
  }

  /// A filter (sa(us)) as JSON: {"name": ..., "patterns": [[kind, pattern]]}.
  static Map<String, Object?> _filter(DBusValue value) {
    final List<DBusValue> parts = value.asStruct();
    return {
      "name": parts[0].asString(),
      "patterns": [
        for (final DBusValue pattern in parts[1].asArray())
          [pattern.asStruct()[0].asUint32(), pattern.asStruct()[1].asString()],
      ],
    };
  }

  static DBusValue _filterValue(Map<String, Object?> filter) => DBusStruct([
        DBusString(filter["name"].toString()),
        DBusArray(DBusSignature("(us)"), [
          for (final Object? pattern in (filter["patterns"] as List?) ?? const [])
            if (pattern is List)
              DBusStruct([DBusUint32((pattern[0] as num).toInt()), DBusString(pattern[1].toString())]),
        ]),
      ]);

  /// A choice (ssa(ss)s) as JSON.
  static Map<String, Object?> _choice(DBusValue value) {
    final List<DBusValue> parts = value.asStruct();
    return {
      "id": parts[0].asString(),
      "label": parts[1].asString(),
      "options": [
        for (final DBusValue option in parts[2].asArray())
          [option.asStruct()[0].asString(), option.asStruct()[1].asString()],
      ],
      "value": parts[3].asString(),
    };
  }

  /// A file name given as bytes (ay, NUL-terminated).
  static String? _bytesPath(DBusValue? value) {
    if (value == null) return null;
    final List<int> bytes = value.asByteArray().takeWhile((b) => b != 0).toList();
    if (bytes.isEmpty) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Shows the dialog [kind] for [request]; completes with its answer, or
  /// null when it was closed or cancelled by the portal (Request.Close).
  Future<Map<String, Object?>?> _show(
    DBusObjectPath handle,
    String kind,
    Map<String, Object?> request,
  ) async {
    idleTimer?.cancel();
    final String id = "${DateTime.now().microsecondsSinceEpoch}-${requests.length}";
    final File requestFile = File(p.join(runtimeDir.path, "$id.request"));
    final File resultFile = File(p.join(runtimeDir.path, "$id.result"));
    requestFile.writeAsStringSync(jsonEncode(request));

    final _Request handleObject = _Request(handle);
    requests[handle.value] = handleObject;
    try {
      await bus.registerObject(handleObject);
    } on Object {
      // Another object at this path (shouldn't happen): no Close then.
    }
    try {
      final Process process = await Process.start(
        dialogsProgram,
        [kind, "--request", requestFile.path, "--result", resultFile.path],
      );
      handleObject.process = process;
      // The dialog's output goes to the session log, through ours.
      process.stdout.listen(stderr.add);
      process.stderr.listen(stderr.add);
      await process.exitCode;
      if (handleObject.closed || !resultFile.existsSync()) return null;
      return (jsonDecode(resultFile.readAsStringSync()) as Map).cast<String, Object?>();
    } on ProcessException catch (e) {
      stderr.writeln("pangolin-portal: can't show the dialog: ${e.message}");
      return null;
    } finally {
      requests.remove(handle.value);
      try {
        await bus.unregisterObject(handleObject);
      } on Object {
        // Already gone.
      }
      for (final File f in [requestFile, resultFile]) {
        if (f.existsSync()) f.deleteSync();
      }
      _scheduleIdleExit();
    }
  }
}

/// org.freedesktop.impl.portal.Request at a request's handle: the portal
/// closes it when the app cancels.
class _Request extends DBusObject {
  _Request(super.path);

  Process? process;
  bool closed = false;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface == requestInterface && call.name == "Close") {
      closed = true;
      process?.kill();
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}
