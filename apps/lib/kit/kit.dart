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

/// Shared infrastructure of the dahliaOS applications: bootstrapping, theme
/// syncing with the shell, window chrome and common widgets.
library;

export 'package:dahlia_apps/kit/app.dart';
export 'package:dahlia_apps/kit/file_dialog.dart';
export 'package:dahlia_apps/kit/open_with.dart';
export 'package:dahlia_apps/kit/personalize.dart';
export 'package:dahlia_apps/kit/rail.dart';
export 'package:dahlia_apps/kit/storage.dart';
export 'package:dahlia_apps/kit/system.dart';
export 'package:dahlia_apps/kit/tabs.dart';
export 'package:dahlia_apps/kit/themed_icon.dart';
export 'package:dahlia_apps/kit/titlebar.dart';
export 'package:dahlia_apps/kit/widgets.dart';
export 'package:zenit_ui/zenit_ui.dart';
