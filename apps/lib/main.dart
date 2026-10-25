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

import 'dart:io';

import 'package:dahlia_apps/apps/activity_monitor/activity_monitor.dart';
import 'package:dahlia_apps/apps/calculator/calculator.dart';
import 'package:dahlia_apps/apps/clock/clock.dart';
import 'package:dahlia_apps/apps/disks/disks.dart';
import 'package:dahlia_apps/apps/files/files.dart';
import 'package:dahlia_apps/apps/gallery/gallery.dart';
import 'package:dahlia_apps/apps/logs/logs.dart';
import 'package:dahlia_apps/apps/portal/portal.dart';
import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/apps/store/store.dart';
import 'package:dahlia_apps/apps/terminal/terminal.dart';
import 'package:dahlia_apps/apps/text_editor/text_editor.dart';
import 'package:dahlia_apps/apps/welcome/welcome.dart';
import 'package:dahlia_apps/kit/app.dart';

/// Every application of the multi-call binary, by name. See
/// linux/runner/main.cc for the matching window defaults.
final Map<String, DahliaAppSpec> dahliaApps = {
  for (final DahliaAppSpec spec in [
    activityMonitorApp,
    calculatorApp,
    clockApp,
    disksApp,
    filesApp,
    galleryApp,
    logsApp,
    settingsApp,
    storeApp,
    terminalApp,
    textEditorApp,
    welcomeApp,
    fileChooserApp,
    appChooserApp,
  ])
    spec.name: spec,
};

Future<void> main(List<String> args) async {
  final String name = args.isNotEmpty ? args.first : "welcome";
  final DahliaAppSpec? spec = dahliaApps[name];
  if (spec == null) {
    stderr.writeln("Unknown application '$name'. "
        "Available: ${dahliaApps.keys.join(", ")}");
    exit(2);
  }
  await runDahliaApp(spec, args.skip(1).toList());
}
