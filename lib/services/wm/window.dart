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

import 'package:flutter/widgets.dart';

/// An application window as seen by the shell (taskbar, overview, ...),
/// independent of whether it is a real Wayland window managed through river
/// or a built-in Utopia window.
abstract class ShellWindow extends ChangeNotifier {
  /// Unique, never reused identifier.
  String get id;

  /// Application id (Wayland app_id / desktop entry id), if known.
  String? get appId;

  String get title;

  /// Icon supplied by the window itself. Real windows don't have one, the
  /// shell resolves their icon through the matching desktop entry.
  ImageProvider? get icon => null;

  bool get minimized;
  bool get maximized;
  bool get fullscreen;
  bool get focused;

  /// Window this one is a dialog of, if any.
  ShellWindow? get parent => null;

  /// Unminimizes, raises and focuses the window.
  void activate();

  void minimize();

  void toggleMaximize();

  /// Politely asks the window to close.
  void close();
}
