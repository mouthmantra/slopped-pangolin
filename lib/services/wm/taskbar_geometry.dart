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

import 'dart:ui';

/// Where the taskbar shows each window, in shell surface coordinates, so
/// windows can be animated into and out of their taskbar button.
abstract final class TaskbarGeometry {
  static final Map<Object, (Rect, Set<String>)> _slots = {};

  /// Called by taskbar buttons after layout: [owner] shows [windowIds] at
  /// [rect].
  static void update(Object owner, Rect rect, Iterable<String> windowIds) {
    _slots[owner] = (rect, windowIds.toSet());
  }

  static void remove(Object owner) => _slots.remove(owner);

  /// The taskbar button of the window with [windowId], if it has one.
  static Rect? rectFor(String windowId) {
    for (final (Rect rect, Set<String> ids) in _slots.values) {
      if (ids.contains(windowId)) return rect;
    }
    return null;
  }
}
