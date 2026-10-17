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
import 'package:pangolin/services/session.dart';
import 'package:pangolin/widgets/context_menu.dart' show shellMenuRadius;
import 'package:zenit_ui/zenit_ui.dart' show BlurRegion, ZenitBlur;

/// Navigator of the shell surface (session mode).
///
/// The desktop surface sits in river's BACKGROUND layer, below every window,
/// and the transparent shell surface covers it. Popups started from the
/// desktop (its context menu, the wallpaper picker) are therefore shown on the
/// shell surface: they stay above windows, and while they are open the shell
/// takes all input so clicking anywhere else dismisses them.
final GlobalKey<NavigatorState> shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: "shell navigator");

/// Context to show popups from [context] with: the shell surface's navigator
/// in session mode, [context] itself otherwise.
BuildContext shellPopupContext(BuildContext context) {
  if (!PangolinSession.isSession) return context;
  return shellNavigatorKey.currentContext ?? context;
}

/// Whether [context] belongs to the shell surface (or there is only one
/// surface, in windowed mode).
bool isOnShellSurface(BuildContext context) {
  if (!PangolinSession.isSession) return true;
  return View.maybeOf(context)?.viewId == PangolinSession.shellViewId;
}

/// Shows a context menu at [globalPosition] on the shell surface: frosted
/// glass when river blurs.
Future<T?> showShellMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<PopupMenuEntry<T>> items,
}) {
  final BuildContext target = shellPopupContext(context);
  final Color background = Theme.of(target).colorScheme.background;
  final bool frosted = ZenitBlur.active;
  return showMenu<T>(
    context: target,
    position: RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx,
      globalPosition.dy,
    ),
    color: frosted ? background.withValues(alpha: ZenitBlur.fillOpacity) : background,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(borderRadius: shellMenuRadius),
    items: [
      if (frosted) _BlurMenuEntry<T>(),
      ...items,
    ],
  );
}

/// Invisible first entry asking river to blur behind the menu panel.
class _BlurMenuEntry<T> extends PopupMenuEntry<T> {
  const _BlurMenuEntry();

  @override
  double get height => 0;

  @override
  bool represents(T? value) => false;

  @override
  State<_BlurMenuEntry<T>> createState() => _BlurMenuEntryState<T>();
}

class _BlurMenuEntryState<T> extends State<_BlurMenuEntry<T>> {
  @override
  Widget build(BuildContext context) =>
      const BlurRegion.ancestor(borderRadius: shellMenuRadius);
}
