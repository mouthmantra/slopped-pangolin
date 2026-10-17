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

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pangolin/services/wm/taskbar_geometry.dart';

/// Reports where its child (a taskbar button) is drawn, for the windows it
/// stands for, so they can be minimized into it (see [TaskbarGeometry]).
class TaskbarGeometryReporter extends SingleChildRenderObjectWidget {
  const TaskbarGeometryReporter({
    required this.windowIds,
    super.child,
    super.key,
  });

  final List<String> windowIds;

  @override
  RenderTaskbarGeometryReporter createRenderObject(BuildContext context) =>
      RenderTaskbarGeometryReporter(windowIds);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTaskbarGeometryReporter renderObject,
  ) {
    renderObject.windowIds = windowIds;
  }
}

class RenderTaskbarGeometryReporter extends RenderProxyBox {
  RenderTaskbarGeometryReporter(this._windowIds);

  List<String> _windowIds;
  set windowIds(List<String> value) {
    if (listEquals(value, _windowIds)) return;
    _windowIds = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!hasSize) return;
    RenderObject root = this;
    while (root.parent != null && root.parent is! RenderView) {
      root = root.parent!;
    }
    TaskbarGeometry.update(
      this,
      MatrixUtils.transformRect(getTransformTo(root), Offset.zero & size),
      _windowIds,
    );
  }

  @override
  void detach() {
    TaskbarGeometry.remove(this);
    super.detach();
  }
}
