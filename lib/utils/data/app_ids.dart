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

/// Desktop entry ids (and Wayland app_ids) of the dahliaOS applications that
/// ship with Pangolin. See apps/ in this repository.
abstract final class DahliaApps {
  static const String settings = "io.dahliaos.settings";
  static const String files = "io.dahliaos.files";
  static const String store = "io.dahliaos.store";
  static const String clock = "io.dahliaos.clock";
  static const String welcome = "io.dahliaos.welcome";
  static const String terminal = "io.dahliaos.terminal";
  static const String calculator = "io.dahliaos.calculator";
  static const String activityMonitor = "io.dahliaos.activity_monitor";
  static const String gallery = "io.dahliaos.gallery";
  static const String textEditor = "io.dahliaos.text_editor";
  static const String logs = "io.dahliaos.logs";

  /// Apps pinned to the taskbar on first start.
  static const List<String> defaultPinned = [files, terminal, settings, store];
}
