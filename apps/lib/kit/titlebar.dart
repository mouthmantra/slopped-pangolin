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

import 'package:dahlia_apps/kit/app.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:yaru_window/yaru_window.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// Title bar of dahliaOS applications: title, optional actions and the window
/// buttons. Dragging it moves the window, double clicking toggles maximize.
///
/// Under Pangolin these become xdg_toplevel move/maximize/minimize requests
/// handled by the shell's window manager.
class DahliaTitlebar extends StatelessWidget implements PreferredSizeWidget {
  const DahliaTitlebar({
    this.title,
    this.leading = const [],
    this.actions = const [],
    this.backgroundColor,
    this.showIcon = true,
    this.height = 48,
    this.dialog = false,
    super.key,
  });

  /// A dialog's title bar: only the close button, no maximizing.
  final bool dialog;

  final Widget? title;
  final List<Widget> leading;
  final List<Widget> actions;
  final Color? backgroundColor;
  final bool showIcon;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final DahliaAppSpec? spec = AppSpecScope.maybeOf(context);
    final Widget titleWidget = title ?? Text(spec?.title ?? "");

    if (kIsWeb) return _bar(context, titleWidget, null, null);

    final YaruWindowInstance window = YaruWindow.of(context);
    return StreamBuilder<YaruWindowState>(
      stream: window.states(),
      builder: (context, snapshot) =>
          _bar(context, titleWidget, window, snapshot.data),
    );
  }

  Widget _bar(
    BuildContext context,
    Widget titleWidget,
    YaruWindowInstance? window,
    YaruWindowState? state,
  ) {
    return ListenableBuilder(
      listenable: Listenable.merge([ZenitBlur.state, PreferencesService.current]),
      builder: (context, _) => _frostedBar(context, titleWidget, window, state),
    );
  }

  Widget _frostedBar(
    BuildContext context,
    Widget titleWidget,
    YaruWindowInstance? window,
    YaruWindowState? state,
  ) {
    final DahliaAppSpec? spec = AppSpecScope.maybeOf(context);
    final bool maximized = state?.isMaximized ?? false;
    final bool tiled = maximized || (state?.isFullscreen ?? false);

    final Color background =
        backgroundColor ?? DahliaTitlebar.backgroundOf(context);

    final Widget bar = TitleBarGestureDetector(
      onDrag: window == null ? null : (_) => window.drag(),
      onDoubleTap: window == null || dialog
          ? null
          : () => maximized ? window.restore() : window.maximize(),
      onSecondaryTap: window?.showMenu,
      child: Material(
        color: background,
        // Inactive windows dim their title bar's contents, not its glass,
        // so that panes sharing its color (Settings' rail) stay seamless.
        child: AnimatedOpacity(
          opacity: state == null || state.isActive != false ? 1 : 0.6,
          duration: const Duration(milliseconds: 100),
          child: SizedBox(
            height: height,
            // Title centered on the bar, as in the dahliaOS design, when the
            // bar has nothing else; next to the app icon otherwise, so it
            // never crowds a search field or other actions.
            child: NavigationToolbar(
              centerMiddle: leading.isEmpty && actions.isEmpty,
              middleSpacing: 16,
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 8),
                  if (showIcon && spec != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 10),
                      child: AppIcon(spec: spec, size: 22),
                    ),
                  ...leading,
                ],
              ),
              middle: DefaultTextStyle.merge(
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: titleWidget,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...actions,
                  if (window != null && dialog) ...[
                    const SizedBox(width: 8),
                    ZenitWindowButton(
                      type: ZenitWindowButtonType.close,
                      onPressed: window.close,
                    ),
                  ] else if (window != null) ...[
                    const SizedBox(width: 8),
                    ZenitWindowButton(
                      type: ZenitWindowButtonType.minimize,
                      onPressed: window.minimize,
                    ),
                    const SizedBox(width: 4),
                    ZenitWindowButton(
                      type: maximized
                          ? ZenitWindowButtonType.restore
                          : ZenitWindowButtonType.maximize,
                      onPressed: maximized ? window.restore : window.maximize,
                    ),
                    const SizedBox(width: 4),
                    ZenitWindowButton(
                      type: ZenitWindowButtonType.close,
                      onPressed: window.close,
                    ),
                  ],
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!ZenitBlur.active) return bar;
    return BlurRegion(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(tiled ? 0 : DahliaTitlebar.windowRadius),
      ),
      child: bar,
    );
  }

  /// Corner radius of dahliaOS windows.
  static const double windowRadius = 12;

  /// The title bar's color: translucent glass when river blurs behind it,
  /// tinted with the accent color unless turned off in Settings. Panes that
  /// continue the title bar (Settings' rail) use it too.
  static Color backgroundOf(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    Color base = theme.colorScheme.surface.themedLightness(context, 0.05);
    if (accentTint) {
      final bool dark = theme.brightness == Brightness.dark;
      base = Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: dark ? 0.16 : 0.09),
        base,
      );
    }
    return ZenitBlur.active ? base.withValues(alpha: ZenitBlur.fillOpacity) : base;
  }

  /// Settings > Appearance > "Tint title bars".
  static bool get accentTint =>
      PreferencesService.current.get<bool>(
        SessionSetting.titlebarAccentTint.key,
      ) ??
      SessionSetting.titlebarAccentTint.defaultValue;
}

/// Scaffold with a [DahliaTitlebar].
class DahliaScaffold extends StatelessWidget {
  const DahliaScaffold({
    required this.body,
    this.title,
    this.titlebarLeading = const [],
    this.titlebarActions = const [],
    this.floatingActionButton,
    this.bottomBar,
    this.titlebarColor,
    super.key,
  });

  /// Defaults to [DahliaTitlebar.backgroundOf].
  final Color? titlebarColor;

  final Widget body;
  final Widget? title;
  final List<Widget> titlebarLeading;
  final List<Widget> titlebarActions;
  final Widget? floatingActionButton;
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).scaffoldBackgroundColor;
    // The scaffold leaves the title bar's area transparent (for frosted
    // glass); the content paints its own background.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: DahliaTitlebar(
        title: title,
        leading: titlebarLeading,
        actions: titlebarActions,
        backgroundColor: titlebarColor,
      ),
      body: ColoredBox(color: background, child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null
          ? null
          : ColoredBox(color: background, child: bottomBar),
    );
  }
}

/// The application's own icon (official dahliaOS icon set).
class AppIcon extends StatelessWidget {
  const AppIcon({required this.spec, this.size = 32, super.key});

  final DahliaAppSpec spec;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      spec.iconAsset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
