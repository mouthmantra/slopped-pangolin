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
import 'dart:io';

import 'package:dahlia_apps/kit/kit.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yaru_window/yaru_window.dart';

/// The dialogs Pangolin's desktop portal (session/portal) shows for other
/// apps, each in a window of its own:
///
///   dahlia_apps file_chooser --request FILE --result FILE
///   dahlia_apps app_chooser --request FILE --result FILE
///
/// The request is JSON written by the portal; the answer is JSON written to
/// the result file before the dialog exits (no result: cancelled). Without
/// a request they run on their own, printing the answer.
final DahliaAppSpec fileChooserApp = DahliaAppSpec(
  name: "file_chooser",
  title: "Choose a File",
  builder: (context, args) => _PortalDialog(args: args, chooser: _Chooser.file),
);

final DahliaAppSpec appChooserApp = DahliaAppSpec(
  name: "app_chooser",
  title: "Open With",
  builder: (context, args) => _PortalDialog(args: args, chooser: _Chooser.app),
);

enum _Chooser { file, app }

class _PortalDialog extends StatefulWidget {
  const _PortalDialog({required this.args, required this.chooser});

  final List<String> args;
  final _Chooser chooser;

  @override
  State<_PortalDialog> createState() => _PortalDialogState();
}

class _PortalDialogState extends State<_PortalDialog> {
  late final Map<String, Object?> _request = _readRequest();
  String? _resultPath;
  bool _answered = false;

  Map<String, Object?> _readRequest() {
    final List<String> args = widget.args;
    String? request;
    for (int i = 0; i + 1 < args.length; i++) {
      if (args[i] == "--request") request = args[i + 1];
      if (args[i] == "--result") _resultPath = args[i + 1];
    }
    if (request == null) return const {};
    try {
      return (jsonDecode(File(request).readAsStringSync()) as Map).cast<String, Object?>();
    } on Object {
      return const {};
    }
  }

  String get _title => switch (widget.chooser) {
        _Chooser.file => (_request["title"] as String?)?.isNotEmpty == true
            ? _request["title"]! as String
            : _fileRequest.defaultTitle,
        _Chooser.app => "Open With",
      };

  @override
  void initState() {
    super.initState();
    final String? parent = _request["parent"] as String?;
    if (parent != null && parent.startsWith("wayland:")) {
      unawaited(
        const MethodChannel("io.dahliaos.apps/window")
            .invokeMethod<bool>("setParent", parent)
            .catchError((Object _) => false),
      );
    }
    // After the first frame, where the runner names the window after the
    // app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) unawaited(YaruWindow.setTitle(context, _title).catchError((Object _) {}));
      });
    });
  }

  late final FileChooserRequest _fileRequest = _parseFileRequest(_request);

  static FileChooserRequest _parseFileRequest(Map<String, Object?> r) {
    List<Object?> list(String key) => (r[key] as List?) ?? const [];
    return FileChooserRequest(
      mode: switch (r["mode"]) {
        "save" => FileChooserMode.save,
        "save_files" => FileChooserMode.saveFiles,
        _ => r["directory"] == true ? FileChooserMode.folder : FileChooserMode.open,
      },
      title: r["title"] as String?,
      acceptLabel: r["acceptLabel"] as String?,
      multiple: r["multiple"] == true,
      filters: [
        for (final Object? f in list("filters"))
          if (f is Map)
            FileChooserFilter(
              (f["name"] as String?) ?? "Files",
              [
                for (final Object? pattern in (f["patterns"] as List?) ?? const [])
                  if (pattern is List && pattern.length == 2)
                    ((pattern[0] as num).toInt(), pattern[1].toString()),
              ],
            ),
      ],
      currentFilter: (r["currentFilter"] as num?)?.toInt(),
      choices: [
        for (final Object? c in list("choices"))
          if (c is Map)
            FileChooserChoice(
              id: c["id"].toString(),
              label: (c["label"] as String?) ?? "",
              value: (c["value"] as String?) ?? "",
              options: [
                for (final Object? o in (c["options"] as List?) ?? const [])
                  if (o is List && o.length == 2) (o[0].toString(), o[1].toString()),
              ],
            ),
      ],
      folder: r["folder"] as String?,
      name: r["name"] as String?,
      files: [for (final Object? f in list("files")) f.toString()],
    );
  }

  /// Hands the answer to the portal and closes.
  void _answer(Map<String, Object?> result) {
    if (_answered) return;
    _answered = true;
    final String? path = _resultPath;
    if (path != null) {
      final File temp = File("$path.tmp");
      temp.writeAsStringSync(jsonEncode(result), flush: true);
      temp.renameSync(path);
    } else {
      stdout.writeln(jsonEncode(result));
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (widget.chooser) {
      _Chooser.file => FileChooser(
          request: _fileRequest,
          onDone: (result) => _answer(
            result == null
                ? const {"response": 1}
                : {
                    "response": 0,
                    "paths": result.paths,
                    if (result.filter != null) "currentFilter": result.filter,
                    "choices": result.choices,
                  },
          ),
        ),
      _Chooser.app => OpenWithChooser(
          contentType: (_request["contentType"] as String?)?.isNotEmpty == true
              ? _request["contentType"]! as String
              : _typeOfSubject(),
          subject: _subject(),
          choices: (_request["choices"] as List?)?.map((e) => e.toString()).toList(),
          lastChoice: _request["lastChoice"] as String?,
          onDone: (result) => _answer(
            result == null ? const {"response": 1} : {"response": 0, "choice": result.app.id},
          ),
        ),
    };
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: DahliaTitlebar(title: Text(_title), dialog: true, showIcon: false),
      body: body,
    );
  }

  String _subject() {
    final String? file = _request["filename"] as String?;
    if (file != null && file.isNotEmpty) return p.basename(file);
    final String? uri = _request["uri"] as String?;
    if (uri != null && uri.isNotEmpty) {
      final Uri? parsed = Uri.tryParse(uri);
      if (parsed != null && parsed.pathSegments.isNotEmpty) {
        return Uri.decodeComponent(parsed.pathSegments.last);
      }
      return uri;
    }
    return "this file";
  }

  String _typeOfSubject() {
    final String? file = _request["filename"] as String?;
    if (file != null && File(file).existsSync()) return DesktopApps.typeOf(file);
    return "application/octet-stream";
  }
}
