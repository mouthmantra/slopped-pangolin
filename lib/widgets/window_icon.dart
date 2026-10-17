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

import 'package:flutter/material.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/widgets/resource/auto_image.dart';
import 'package:xdg_desktop/xdg_desktop.dart';

/// Icon of a [ShellWindow]: the window's own icon if it provides one,
/// otherwise the icon of the matching desktop entry.
class WindowIcon extends StatelessWidget {
  const WindowIcon({required this.window, this.size = 32, super.key});

  final ShellWindow window;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ImageProvider? own = window.icon;
    if (own != null) {
      return Image(image: own, width: size, height: size);
    }

    final DesktopEntry? entry =
        ApplicationService.current.findForAppId(window.appId);
    final String? icon = entry?.icon?.main;
    if (icon != null) {
      return AutoVisualResource(resource: icon, size: size);
    }

    return Icon(Icons.web_asset_rounded, size: size);
  }
}
