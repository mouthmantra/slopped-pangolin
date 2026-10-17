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

import 'dart:math' as math;

import 'package:dahlia_apps/kit/file_chooser.dart';
import 'package:dahlia_apps/kit/system.dart';
import 'package:zenit_ui/zenit_ui.dart';

export 'package:dahlia_apps/kit/file_chooser.dart';

enum FileDialogMode { open, save, folder }

/// Shows Pangolin's file chooser ([FileChooser]) in the app and returns the
/// selected path.
///
/// [extensions] (without dots) filters the files shown in open mode.
Future<String?> showFileDialog(
  BuildContext context, {
  FileDialogMode mode = FileDialogMode.open,
  String? initialDirectory,
  String? suggestedName,
  List<String>? extensions,
  String? title,
}) async {
  final List<String> exts = [
    for (final String e in extensions ?? const <String>[]) e.toLowerCase(),
  ];
  final FileChooserRequest request = FileChooserRequest(
    mode: switch (mode) {
      FileDialogMode.open => FileChooserMode.open,
      FileDialogMode.save => FileChooserMode.save,
      FileDialogMode.folder => FileChooserMode.folder,
    },
    title: title,
    folder: initialDirectory ?? SystemUtils.home,
    name: suggestedName,
    filters: [
      if (exts.isNotEmpty && mode == FileDialogMode.open) ...[
        FileChooserFilter(
          "Supported files (${exts.map((e) => ".$e").join(", ")})",
          [for (final String e in exts) (0, "*.$e")],
        ),
        const FileChooserFilter("All files", [(0, "*")]),
      ],
    ],
  );
  final FileChooserResult? result = await showDialog<FileChooserResult>(
    context: context,
    builder: (context) {
      final Size screen = MediaQuery.sizeOf(context);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: math.min(900, screen.width - 48),
          height: math.min(600, screen.height - 48),
          child: ScaffoldMessenger(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: FileChooser(
                request: request,
                showTitle: true,
                onDone: (result) => Navigator.pop(context, result),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result?.paths.firstOrNull;
}
