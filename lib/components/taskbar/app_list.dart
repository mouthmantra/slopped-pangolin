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

import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/components/taskbar/taskbar_item.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:xdg_desktop/xdg_desktop.dart';

/// A taskbar slot: a pinned application and/or the running windows that
/// belong to the same application.
class AppSlot {
  AppSlot({required this.key, this.entry, required this.pinned});

  /// Desktop entry id when known, the window's app id or id otherwise.
  final String key;
  final DesktopEntry? entry;
  final bool pinned;
  final List<ShellWindow> windows = [];

  /// Started, its first window yet to show up.
  bool launching = false;

  bool get running => windows.isNotEmpty;
}

class AppListElement extends StatefulWidget {
  const AppListElement({super.key});

  @override
  State<AppListElement> createState() => _AppListElementState();
}

class _AppListElementState extends State<AppListElement> {
  CustomizationService get _customization => CustomizationService.current;
  WindowManagerService get _wm => WindowManagerService.current;
  ApplicationService get _apps => ApplicationService.current;

  /// Order of unpinned running slots, by first appearance.
  final List<String> _runningOrder = [];

  /// What the bar shows: the current slots plus the ones on their way out,
  /// which shrink away where they were so the others slide over.
  List<_Shown> _shown = [];

  @override
  void initState() {
    super.initState();
    _customization.addListener(_rebuild);
    _wm.addListener(_rebuild);
    _wm.desks.addListener(_rebuild);
    _apps.addListener(_rebuild);
    _apps.launching.addListener(_rebuild);
    PreferencesService.current.addListener(_rebuild);
  }

  @override
  void dispose() {
    _customization.removeListener(_rebuild);
    _wm.removeListener(_rebuild);
    _wm.desks.removeListener(_rebuild);
    _apps.removeListener(_rebuild);
    _apps.launching.removeListener(_rebuild);
    PreferencesService.current.removeListener(_rebuild);
    super.dispose();
  }

  bool get _allDesks =>
      PreferencesService.current.get<bool>(SessionSetting.taskbarAllDesktops.key) ??
      SessionSetting.taskbarAllDesktops.defaultValue;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  List<AppSlot> _computeSlots() {
    final Map<String, AppSlot> slots = {};
    final List<AppSlot> ordered = [];

    for (final String id in _customization.pinnedApps) {
      final DesktopEntry? entry = _apps.getApp(id);
      // A pinned app that can't be found anymore is skipped.
      if (entry == null) continue;
      final AppSlot slot = AppSlot(key: id, entry: entry, pinned: true);
      slots[id] = slot;
      ordered.add(slot);
    }

    final List<AppSlot> running = [];
    final int desk = _wm.desks.value.current;
    final bool allDesks = _allDesks;
    for (final ShellWindow window in _wm.windows) {
      // Dialogs are reached through their parent.
      if (window.parent != null) continue;
      if (!allDesks && _wm.deskOf(window) != desk) continue;
      final DesktopEntry? entry = _apps.findForAppId(window.appId);
      final String key = entry?.id ?? window.appId ?? window.id;
      AppSlot? slot = slots[key];
      if (slot == null) {
        slot = AppSlot(key: key, entry: entry, pinned: false);
        slots[key] = slot;
        running.add(slot);
      }
      slot.windows.add(window);
    }

    // Apps starting up have their place already (where their window's
    // will be): feedback right away, wherever they were started from.
    for (final String id in _apps.launching.value) {
      final AppSlot? slot = slots[id];
      if (slot != null && slot.running) {
        // Its window is here.
        scheduleMicrotask(() => _apps.markLaunched(id));
        continue;
      }
      if (slot != null) {
        slot.launching = true;
        continue;
      }
      final DesktopEntry? entry = _apps.getApp(id);
      if (entry == null) continue;
      final AppSlot starting = AppSlot(key: id, entry: entry, pinned: false)
        ..launching = true;
      slots[id] = starting;
      running.add(starting);
    }

    _runningOrder.removeWhere((k) => !running.any((s) => s.key == k));
    for (final AppSlot slot in running) {
      if (!_runningOrder.contains(slot.key)) _runningOrder.add(slot.key);
    }
    running.sort(
      (a, b) =>
          _runningOrder.indexOf(a.key).compareTo(_runningOrder.indexOf(b.key)),
    );

    return [...ordered, ...running];
  }

  /// [newIndex] is where the item ends up once moved.
  void _onReorder(int oldIndex, int newIndex) {
    final List<_Shown> shown = [..._shown];
    shown.insert(newIndex, shown.removeAt(oldIndex));
    // Leaving slots don't take part in the order.
    final List<AppSlot> slots = [
      for (final _Shown s in shown)
        if (!s.leaving) s.slot,
    ];

    final List<String> pinned =
        slots.where((s) => s.pinned).map((s) => s.key).toList();
    if (!listEquals(pinned, _customization.pinnedApps)) {
      _customization.pinnedApps = pinned;
    }

    _runningOrder
      ..clear()
      ..addAll(slots.where((s) => !s.pinned).map((s) => s.key));
    setState(() {});
  }

  /// Merges [slots] into what's shown: leaving slots stay right after the
  /// slot they followed until they've shrunk away.
  List<_Shown> _merge(List<AppSlot> slots) {
    final Set<String> keys = {for (final AppSlot slot in slots) slot.key};
    final List<_Shown> merged = [for (final AppSlot slot in slots) _Shown(slot)];
    String? previous;
    for (final _Shown old in _shown) {
      if (!keys.contains(old.slot.key)) {
        final int anchor = previous == null
            ? -1
            : merged.indexWhere((s) => s.slot.key == previous);
        merged.insert(anchor + 1, _Shown(old.slot, leaving: true));
      }
      previous = old.slot.key;
    }
    return merged;
  }

  void _onLeft(String key) {
    if (!mounted) return;
    setState(() => _shown.removeWhere((s) => s.leaving && s.slot.key == key));
  }

  @override
  Widget build(BuildContext context) {
    final List<_Shown> shown = _shown = _merge(_computeSlots());

    return ReorderableListView.builder(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      onReorderItem: _onReorder,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) => child,
      itemBuilder: (context, index) => ReorderableDragStartListener(
        key: ValueKey(shown[index].slot.key),
        index: index,
        enabled: !shown[index].leaving,
        child: TaskbarItem(
          slot: shown[index].slot,
          leaving: shown[index].leaving,
          onLeft: () => _onLeft(shown[index].slot.key),
        ),
      ),
      itemCount: shown.length,
    );
  }
}

class _Shown {
  _Shown(this.slot, {this.leaving = false});

  final AppSlot slot;
  final bool leaving;
}
