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

// Prints the globals advertised by the compositor, like `wayland-info`.

import 'package:wayland/wayland.dart';

Future<void> main() async {
  final WaylandConnection connection = await WaylandConnection.connect();
  final GlobalRegistry registry = await GlobalRegistry.create(connection);

  final List<WaylandGlobal> globals = registry.globals.toList()
    ..sort((a, b) => a.interface.compareTo(b.interface));
  for (final WaylandGlobal global in globals) {
    // ignore: avoid_print
    print('${global.interface.padRight(48)} v${global.version}');
  }

  await connection.close();
}
