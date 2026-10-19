/*
Copyright 2021 The dahliaOS Authors

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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/overlays/launcher/app_launcher_button.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/greetd.dart' show LoginUser;
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/utils/data/globals.dart';
import 'package:pangolin/utils/extensions/extensions.dart';
import 'package:pangolin/widgets/quick_button.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:pangolin/widgets/user_avatar.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:xdg_desktop/xdg_desktop.dart';
import 'package:yatl_flutter/yatl_flutter.dart';

/// The app menu: a panel above the taskbar, or the whole screen (Settings >
/// Appearance > App menu, or its full screen button).
class CompactLauncherOverlay extends ShellOverlay {
  static const String overlayId = 'compactlauncher';

  CompactLauncherOverlay({super.key}) : super(id: overlayId);

  @override
  _CompactLauncherOverlayState createState() => _CompactLauncherOverlayState();
}

class _CompactLauncherOverlayState
    extends ShellOverlayState<CompactLauncherOverlay> {
  final scrollController = ScrollController();
  List<LauncherSection> sections = const [];

  static T _setting<T extends Object>(SessionSetting<T> setting) {
    final Object? value = PreferencesService.current.get<Object>(setting.key);
    return value is T ? value : setting.defaultValue;
  }

  @override
  Future<void> requestShow(Map<String, dynamic> args) async {
    sections = LauncherSection.of(
      ApplicationService.current.listApplications(),
      name: (a) => a.getLocalizedName(context.locale),
      byCategory: _setting(SessionSetting.launcherSort) == "category",
    );

    if (scrollController.hasClients) scrollController.jumpTo(0);
    controller.showing = true;
    animationController.forward();
  }

  @override
  Future<void> requestDismiss(Map<String, dynamic> args) async {
    controller.showing = false;
    animationController.reverse();
  }

  void _toggleFullscreen() {
    PreferencesService.current.set<bool>(
      SessionSetting.launcherFullscreen.key,
      !_setting(SessionSetting.launcherFullscreen),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (shouldHide) return const SizedBox();

    if (_setting(SessionSetting.launcherFullscreen)) {
      return Positioned.fill(
        bottom: PangolinSession.taskbarHeight,
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
            child: SurfaceLayer(
              child: FullscreenLauncher(
                sections: sections,
                controller: scrollController,
                onToggleFullscreen: _toggleFullscreen,
              ),
            ),
          ),
        ),
      );
    }

    return Positioned(
      bottom: PangolinSession.taskbarHeight + 8,
      left: 8,
      child: PopupTransition(
        animation: animation,
        showing: controller.showing,
        alignment: const FractionalOffset(0.025, 1.0),
        margin: const EdgeInsets.fromLTRB(8, 24, 24, 8),
        child: SurfaceLayer(
          shape: Constants.bigShape,
          height: 540,
          width: 474,
          outline: true,
          dropShadow: true,
          child: CompactLauncher(
            sections: sections,
            controller: scrollController,
            onToggleFullscreen: _toggleFullscreen,
          ),
        ),
      ),
    );
  }
}

/// Apps under a heading (sorted by category), or all of them (by name).
class LauncherSection {
  const LauncherSection(this.title, this.apps);

  final String? title;
  final List<DesktopEntry> apps;

  /// [apps] A to Z by [name], in one section or grouped by category (groups
  /// A to Z, "Other" last).
  static List<LauncherSection> of(
    Iterable<DesktopEntry> apps, {
    required String Function(DesktopEntry) name,
    required bool byCategory,
  }) {
    final List<DesktopEntry> sorted = apps.toList()
      ..sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));
    if (!byCategory) return [LauncherSection(null, sorted)];
    final Map<String, List<DesktopEntry>> groups = {};
    for (final DesktopEntry app in sorted) {
      groups.putIfAbsent(category(app.categories), () => []).add(app);
    }
    final List<String> titles = groups.keys.toList()
      ..sort((a, b) {
        if (a == "Other") return 1;
        if (b == "Other") return -1;
        return a.compareTo(b);
      });
    return [for (final String t in titles) LauncherSection(t, groups[t]!)];
  }

  /// The group of an app from its freedesktop categories: the first main
  /// category it lists.
  static String category(List<String>? categories) {
    for (final String c in categories ?? const <String>[]) {
      final String? group = switch (c) {
        "AudioVideo" || "Audio" || "Video" => "Media",
        "Development" => "Development",
        "Education" || "Science" => "Education",
        "Game" => "Games",
        "Graphics" => "Graphics",
        "Network" => "Internet",
        "Office" => "Office",
        "Settings" || "System" => "System",
        "Utility" => "Accessories",
        _ => null,
      };
      if (group != null) return group;
    }
    return "Other";
  }
}

/// The signed in user: login name and full name.
abstract final class _Me {
  static final String login = Platform.environment["USER"] ?? username;
  static final String name =
      LoginUser.all().where((u) => u.name == login).firstOrNull?.displayName ??
          login;
}

/// Avatar, settings, power and the full screen switch.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.axis,
  });

  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    Widget button(String tooltip, Widget icon, VoidCallback onPressed) =>
        Tooltip(
          message: tooltip,
          child: QuickActionButton(
            margin: const EdgeInsets.all(4),
            leading: icon,
            onPressed: onPressed,
          ),
        );
    final List<Widget> children = [
      button(
        "Account",
        UserAvatar(name: _Me.name, size: 28),
        () => ActionManager.showAccountMenu(context),
      ),
      if (axis == Axis.vertical) const Spacer(),
      button(
        fullscreen ? "Exit full screen" : "Full screen",
        Icon(
          fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
        ),
        onToggleFullscreen,
      ),
      button(
        "Settings",
        const Icon(Icons.settings_outlined),
        () => ActionManager.openSettings(context),
      ),
      button(
        "Power",
        const Icon(Icons.power_settings_new_rounded),
        () => ActionManager.showPowerMenu(context),
      ),
    ];
    return axis == Axis.vertical
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: children),
          )
        : Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _UserName extends StatelessWidget {
  const _UserName();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_Me.name),
        const SizedBox(height: 2.0),
        const Text("Local Account", style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

class CompactLauncher extends StatelessWidget {
  final List<LauncherSection> sections;
  final ScrollController? controller;
  final VoidCallback onToggleFullscreen;

  const CompactLauncher({
    required this.sections,
    required this.onToggleFullscreen,
    this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Headings and apps in one list.
    final List<Object> items = [
      for (final LauncherSection s in sections) ...[
        if (s.title != null) s.title!,
        ...s.apps,
      ],
    ];
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          _Actions(
            fullscreen: false,
            onToggleFullscreen: onToggleFullscreen,
            axis: Axis.vertical,
          ),
          Column(
            children: [
              const SizedBox(
                width: 402,
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: _UserName(),
                ),
              ),
              SizedBox(
                height: 460,
                width: 380,
                child: ListView.separated(
                  itemCount: items.length,
                  itemBuilder: (context, index) => switch (items[index]) {
                    final DesktopEntry app => AppLauncherTile(application: app),
                    final Object title => _Heading(title as String),
                  },
                  controller: controller,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The app menu over the whole screen: a grid of apps.
class FullscreenLauncher extends StatelessWidget {
  final List<LauncherSection> sections;
  final ScrollController? controller;
  final VoidCallback onToggleFullscreen;

  const FullscreenLauncher({
    required this.sections,
    required this.onToggleFullscreen,
    this.controller,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      // Clicking between the apps closes the menu.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ShellService.current.dismissEverything,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
                  child: Row(
                    children: [
                      const Expanded(child: _UserName()),
                      _Actions(
                        fullscreen: true,
                        onToggleFullscreen: onToggleFullscreen,
                        axis: Axis.horizontal,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    controller: controller,
                    slivers: [
                      for (final LauncherSection s in sections) ...[
                        if (s.title != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(40, 16, 40, 4),
                              child: _Heading(s.title!),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 144,
                            ),
                            itemCount: s.apps.length,
                            itemBuilder: (context, index) => Center(
                              child: AppLauncherButton(
                                application: s.apps[index],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
