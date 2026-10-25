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

import 'dart:async';

import 'package:display_config/src/layout.dart';
import 'package:display_config/src/monitors_xml.dart';
import 'package:display_config/src/profiles.dart';
import 'package:display_config/src/scales.dart';
import 'package:wayland/wayland.dart';

/// A mode a monitor supports.
class OutputModeState {
  OutputModeState(this.proxy);

  final ZwlrOutputModeV1 proxy;
  int width = 0;
  int height = 0;

  /// mHz.
  int refresh = 0;
  bool preferred = false;
}

/// A monitor as the compositor reports it (zwlr_output_head_v1).
class OutputHeadState {
  OutputHeadState(this.proxy);

  final ZwlrOutputHeadV1 proxy;
  String name = "";
  String description = "";
  String make = "";
  String model = "";
  String serial = "";
  int physicalWidth = 0;
  int physicalHeight = 0;
  bool enabled = false;
  final List<OutputModeState> modes = [];
  OutputModeState? currentMode;
  int x = 0;
  int y = 0;
  int transform = 0;
  double scale = 1;
  bool? adaptiveSync;

  String get id =>
      outputId(name: name, make: make, model: model, serial: serial);

  OutputSettings get settings => OutputSettings(
        id: id,
        enabled: enabled,
        width: currentMode?.width ?? 0,
        height: currentMode?.height ?? 0,
        refresh: currentMode?.refresh ?? 0,
        scale: scale,
        transform: transform,
        x: x,
        y: y,
        adaptiveSync: adaptiveSync,
      );

  /// The supported mode closest to [width] × [height] @ [refresh] mHz.
  OutputModeState? modeFor(int width, int height, int refresh) {
    OutputModeState? best;
    for (final OutputModeState mode in modes) {
      if (mode.width != width || mode.height != height) continue;
      if (best == null ||
          (mode.refresh - refresh).abs() < (best.refresh - refresh).abs()) {
        best = mode;
      }
    }
    return best;
  }
}

/// Whether [name] is a built-in screen's connector (laptop panels).
bool isBuiltInOutput(String name) =>
    name.startsWith("eDP") || name.startsWith("LVDS") || name.startsWith("DSI");

/// Reads and changes the configuration of the monitors through
/// wlr-output-management.
class DisplayConfigurator {
  DisplayConfigurator._(this._connection, this._manager);

  final WaylandConnection _connection;
  final ZwlrOutputManagerV1 _manager;
  final List<OutputHeadState> heads = [];
  int _serial = 0;
  bool _ready = false;
  final StreamController<void> _changes = StreamController.broadcast();

  /// After the compositor reported a complete, possibly changed, state.
  Stream<void> get changes => _changes.stream;

  /// Null when the compositor doesn't support output management.
  static Future<DisplayConfigurator?> connect() async {
    final WaylandConnection connection = await WaylandConnection.connect();
    final GlobalRegistry globals = await GlobalRegistry.create(connection);
    final ZwlrOutputManagerV1? manager =
        globals.bind(ZwlrOutputManagerV1.interface, maxVersion: 4);
    if (manager == null) {
      await connection.close();
      return null;
    }
    final DisplayConfigurator configurator =
        DisplayConfigurator._(connection, manager);
    manager
      ..onHead = configurator._onHead
      ..onDone = configurator._onDone
      ..onFinished = () => configurator._changes.close();
    // Heads, then their properties and modes, then done.
    while (!configurator._ready) {
      await connection.roundtrip();
    }
    return configurator;
  }

  Future<void> close() async {
    _manager.stop();
    await _connection.close();
  }

  /// The connected monitors, by id.
  Set<String> get ids => {for (final OutputHeadState h in heads) h.id};

  void _onDone(int serial) {
    _serial = serial;
    _ready = true;
    _changes.add(null);
  }

  void _onHead(ZwlrOutputHeadV1 proxy) {
    final OutputHeadState head = OutputHeadState(proxy);
    heads.add(head);
    proxy
      ..onName = ((v) => head.name = v)
      ..onDescription = ((v) => head.description = v)
      ..onMake = ((v) => head.make = v)
      ..onModel = ((v) => head.model = v)
      ..onSerialNumber = ((v) => head.serial = v)
      ..onPhysicalSize = (w, h) {
        head.physicalWidth = w;
        head.physicalHeight = h;
      }
      ..onEnabled = ((v) => head.enabled = v != 0)
      ..onPosition = (x, y) {
        head.x = x;
        head.y = y;
      }
      ..onTransform = ((v) => head.transform = v)
      ..onScale = ((v) => head.scale = v)
      ..onAdaptiveSync = ((v) => head.adaptiveSync = v != 0)
      ..onMode = (modeProxy) {
        final OutputModeState mode = OutputModeState(modeProxy);
        head.modes.add(mode);
        modeProxy
          ..onSize = (w, h) {
            mode.width = w;
            mode.height = h;
          }
          ..onRefresh = ((r) => mode.refresh = r)
          ..onPreferred = (() => mode.preferred = true)
          ..onFinished = () {
            head.modes.remove(mode);
            if (head.currentMode == mode) head.currentMode = null;
          };
      }
      ..onCurrentMode = (modeProxy) {
        head.currentMode =
            head.modes.where((m) => m.proxy == modeProxy).firstOrNull;
      }
      ..onFinished = () => heads.remove(head);
  }

  /// Applies [settings] (by monitor id; monitors left out keep their
  /// configuration). Completes with whether the compositor accepted it.
  Future<bool> apply(
    Map<String, OutputSettings> settings, {
    bool testOnly = false,
  }) async {
    final Map<String, OutputSettings> settled = settledLayout(settings);
    final Completer<bool> result = Completer();
    final ZwlrOutputConfigurationV1 config =
        _manager.createConfiguration(_serial);
    for (final OutputHeadState head in heads) {
      final OutputSettings wanted = settled[head.id] ?? head.settings;
      if (!wanted.enabled) {
        config.disableHead(head.proxy);
        continue;
      }
      final ZwlrOutputConfigurationHeadV1 configHead =
          config.enableHead(head.proxy);
      if (wanted.width > 0 && wanted.height > 0) {
        final OutputModeState? mode =
            head.modeFor(wanted.width, wanted.height, wanted.refresh);
        if (mode != null) {
          configHead.setMode(mode.proxy);
        } else {
          configHead.setCustomMode(wanted.width, wanted.height, wanted.refresh);
        }
      }
      configHead
        ..setScale(wanted.scale)
        ..setTransform(wanted.transform)
        ..setPosition(wanted.x, wanted.y);
      if (wanted.adaptiveSync != null &&
          configHead.version >= 4 &&
          head.adaptiveSync != null) {
        configHead.setAdaptiveSync(wanted.adaptiveSync! ? 1 : 0);
      }
    }
    config
      ..onSucceeded = () {
        if (!result.isCompleted) result.complete(true);
        config.destroy();
      }
      ..onFailed = () {
        if (!result.isCompleted) result.complete(false);
        config.destroy();
      }
      ..onCancelled = () {
        if (!result.isCompleted) result.complete(false);
        config.destroy();
      };
    testOnly ? config.test() : config.apply();
    _connection.flush();
    return await result.future
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
  }

  /// Applies the configuration saved for the connected monitors, if any and
  /// if it differs from the current one. Completes with whether something
  /// was applied.
  Future<bool> applySaved() async {
    final List<OutputSettings>? saved = DisplayProfiles.match(ids);
    if (saved == null) return false;
    return _applyIfDifferent({
      for (final OutputSettings o in saved) o.id: o,
    });
  }

  /// Applies [profile] (one monitor setup, e.g. from
  /// [DisplayProfiles.sharedBy]) if it differs from the current one.
  Future<bool> applyProfile(List<OutputSettings> profile) => _applyIfDifferent({
        for (final OutputSettings o in profile) o.id: o,
      });

  /// Turns a monitor on when none is (the one in use was unplugged and
  /// nothing saved covers the ones left): the built-in panel if there is
  /// one, at its preferred mode and a scale for its density. Completes with
  /// the monitor turned on, if any.
  Future<OutputHeadState?> ensureOneEnabled() async {
    // State the compositor sent after a configuration just applied.
    await _connection.roundtrip();
    if (heads.isEmpty || heads.any((h) => h.enabled)) return null;
    final OutputHeadState head =
        heads.where((h) => isBuiltInOutput(h.name)).firstOrNull ?? heads.first;
    final OutputModeState? mode =
        head.modes.where((m) => m.preferred).firstOrNull ??
            head.modes.fold<OutputModeState?>(
              null,
              (best, m) => best == null ||
                      m.width * m.height > best.width * best.height
                  ? m
                  : best,
            );
    if (mode == null) return null;
    final bool applied = await apply({
      head.id: OutputSettings(
        id: head.id,
        enabled: true,
        width: mode.width,
        height: mode.height,
        refresh: mode.refresh,
        scale: recommendedScale(
          mode.width,
          mode.height,
          head.physicalWidth,
          head.physicalHeight,
        ),
      ),
    });
    return applied ? head : null;
  }

  /// How the connected monitors are set up right now.
  List<OutputSettings> get current => [
        for (final OutputHeadState h in heads) h.settings,
      ];

  /// Applies GNOME's configuration for the connected monitors from
  /// monitors.xml ([MonitorsXml]), if it has one and it differs from the
  /// current one. Completes with whether there was such a configuration.
  Future<bool> applyMonitorsXml([String? path]) async {
    final Map<String, OutputSettings>? wanted =
        MonitorsXml.resolve(MonitorsXml.load(path), [
      for (final OutputHeadState h in heads)
        (id: h.id, name: h.name, model: h.model, serial: h.serial),
    ]);
    if (wanted == null) return false;
    await _applyIfDifferent(wanted);
    return true;
  }

  /// [settings] (monitors left out as they are) with the enabled monitors
  /// moved so none overlaps another and they hang together ([settle]):
  /// saved layouts can come from other scales (a monitors.xml in physical
  /// pixels, a profile from before a scale change).
  Map<String, OutputSettings> settledLayout(
    Map<String, OutputSettings> settings,
  ) {
    final Map<String, OutputSettings> all = {
      for (final OutputHeadState h in heads) h.id: settings[h.id] ?? h.settings,
    };
    final Map<String, LayoutBox> boxes = {};
    for (final OutputHeadState h in heads) {
      final OutputSettings o = all[h.id]!;
      if (!o.enabled) continue;
      final int width = o.width > 0 ? o.width : h.currentMode?.width ?? 0;
      final int height = o.height > 0 ? o.height : h.currentMode?.height ?? 0;
      if (width <= 0 || height <= 0) continue;
      final (int w, int lh) = logicalSize(width, height, o.scale, o.transform);
      boxes[h.id] = LayoutBox(x: o.x, y: o.y, width: w, height: lh);
    }
    settle(boxes.values.toList());
    return {
      ...settings,
      for (final MapEntry<String, LayoutBox> b in boxes.entries)
        b.key: all[b.key]!.movedTo(b.value.x, b.value.y),
    };
  }

  Future<bool> _applyIfDifferent(Map<String, OutputSettings> requested) async {
    final Map<String, OutputSettings> wanted = settledLayout(requested);
    final bool same = heads.every((h) {
      final OutputSettings? w = wanted[h.id];
      if (w == null) return true;
      final OutputSettings c = h.settings;
      return c.enabled == w.enabled &&
          (!w.enabled ||
              (c.width == w.width &&
                  c.height == w.height &&
                  (c.refresh - w.refresh).abs() < 500 &&
                  (c.scale - w.scale).abs() < 0.005 &&
                  c.transform == w.transform &&
                  c.x == w.x &&
                  c.y == w.y));
    });
    if (same) return false;
    return await apply(wanted);
  }
}
