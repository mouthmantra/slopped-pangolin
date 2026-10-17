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

import 'package:dahlia_apps/apps/settings/settings.dart';
import 'package:dahlia_apps/apps/settings/pages/session_settings.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:display_config/display_config.dart';
import 'package:wayland/wayland.dart';

class _Mode {
  _Mode(this.proxy);
  final ZwlrOutputModeV1 proxy;
  int width = 0;
  int height = 0;
  int refresh = 0;
  bool preferred = false;

  String get label =>
      "$width × $height${refresh > 0 ? " @ ${(refresh / 1000).toStringAsFixed(refresh % 1000 == 0 ? 0 : 2)} Hz" : ""}";
}

class _Head {
  _Head(this.proxy);
  final ZwlrOutputHeadV1 proxy;
  String name = "";
  String description = "";
  String make = "";
  String model = "";
  String serial = "";
  int physicalWidth = 0;
  int physicalHeight = 0;
  bool enabled = false;
  final List<_Mode> modes = [];
  _Mode? currentMode;
  int x = 0;
  int y = 0;
  int transform = 0;
  double scale = 1;
}

/// The state applied to a head when the user hits Apply.
class _HeadConfig {
  _HeadConfig.from(_Head head)
      : enabled = head.enabled,
        mode = head.currentMode,
        scale = head.scale,
        transform = head.transform,
        x = head.x,
        y = head.y;

  bool enabled;
  _Mode? mode;
  double scale;
  int transform;
  int x;
  int y;
}

class DisplaysPage extends StatefulWidget {
  const DisplaysPage({super.key});

  @override
  State<DisplaysPage> createState() => _DisplaysPageState();
}

class _DisplaysPageState extends State<DisplaysPage> {
  WaylandConnection? _connection;
  ZwlrOutputManagerV1? _manager;
  final List<_Head> _heads = [];
  final Map<_Head, _HeadConfig> _pending = {};
  int _serial = 0;
  String? _error;
  bool _busy = false;

  /// Scales that keep the logical size of [mode] whole pixels (GNOME's
  /// approach), with the current one if it isn't among them.
  static List<double> _scalesFor(_Mode? mode, double current) {
    final List<double> scales = mode == null
        ? const [1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        : supportedScales(mode.width, mode.height);
    return [
      ...scales,
      if (!scales.any((s) => (s - current).abs() < 0.005)) current,
    ]..sort();
  }

  static double? _recommendedFor(_Head head, _Mode? mode) {
    if (mode == null || head.physicalWidth <= 0) return null;
    return recommendedScale(
      mode.width,
      mode.height,
      head.physicalWidth,
      head.physicalHeight,
    );
  }
  static const Map<int, String> _transforms = {
    0: "Normal",
    1: "90°",
    2: "180°",
    3: "270°",
  };

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _manager?.stop();
    _connection?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    try {
      final WaylandConnection connection = await WaylandConnection.connect();
      final GlobalRegistry globals = await GlobalRegistry.create(connection);
      final ZwlrOutputManagerV1? manager =
          globals.bind(ZwlrOutputManagerV1.interface, maxVersion: 4);
      if (manager == null) {
        setState(() => _error = "The compositor doesn't support output management.");
        return;
      }
      _connection = connection;
      _manager = manager;

      manager
        ..onHead = _onHead
        ..onDone = (serial) {
          if (!mounted) return;
          setState(() {
            _serial = serial;
            _pending
              ..clear()
              ..addEntries(_heads.map((h) => MapEntry(h, _HeadConfig.from(h))));
          });
        };
      await connection.roundtrip();
    } on Object catch (e) {
      if (mounted) setState(() => _error = "Couldn't connect to the compositor: $e");
    }
  }

  void _onHead(ZwlrOutputHeadV1 proxy) {
    final _Head head = _Head(proxy);
    _heads.add(head);
    proxy
      ..onName = (v) {
        head.name = v;
      }
      ..onDescription = (v) {
        head.description = v;
      }
      ..onMake = (v) {
        head.make = v;
      }
      ..onModel = (v) {
        head.model = v;
      }
      ..onSerialNumber = (v) {
        head.serial = v;
      }
      ..onPhysicalSize = (w, h) {
        head.physicalWidth = w;
        head.physicalHeight = h;
      }
      ..onEnabled = (v) {
        head.enabled = v != 0;
      }
      ..onPosition = (x, y) {
        head.x = x;
        head.y = y;
      }
      ..onTransform = (v) {
        head.transform = v;
      }
      ..onScale = (v) {
        head.scale = v;
      }
      ..onMode = (modeProxy) {
        final _Mode mode = _Mode(modeProxy);
        head.modes.add(mode);
        modeProxy
          ..onSize = (w, h) {
            mode.width = w;
            mode.height = h;
          }
          ..onRefresh = (r) {
            mode.refresh = r;
          }
          ..onPreferred = () {
            mode.preferred = true;
          }
          ..onFinished = () {
            head.modes.remove(mode);
          };
      }
      ..onCurrentMode = (modeProxy) {
        head.currentMode = head.modes.where((m) => m.proxy == modeProxy).firstOrNull;
      }
      ..onFinished = () {
        _heads.remove(head);
        _pending.remove(head);
        if (mounted) setState(() {});
      };
  }

  bool get _dirty => _pending.entries.any((e) {
        final _Head h = e.key;
        final _HeadConfig c = e.value;
        return c.enabled != h.enabled ||
            c.mode != h.currentMode ||
            c.scale != h.scale ||
            c.transform != h.transform ||
            c.x != h.x ||
            c.y != h.y;
      });

  /// Applies [configs], returning whether the compositor accepted them.
  Future<bool> _applyConfigs(Map<_Head, _HeadConfig> configs, {bool testOnly = false}) {
    final ZwlrOutputManagerV1 manager = _manager!;
    final Completer<bool> result = Completer();
    final ZwlrOutputConfigurationV1 config = manager.createConfiguration(_serial);
    for (final MapEntry<_Head, _HeadConfig> e in configs.entries) {
      if (!e.value.enabled) {
        config.disableHead(e.key.proxy);
        continue;
      }
      final ZwlrOutputConfigurationHeadV1 head = config.enableHead(e.key.proxy);
      final _Mode? mode = e.value.mode;
      if (mode != null) head.setMode(mode.proxy);
      head
        ..setScale(e.value.scale)
        ..setTransform(e.value.transform)
        ..setPosition(e.value.x, e.value.y);
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
    return result.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
  }

  Future<void> _apply() async {
    if (_heads.isNotEmpty && _pending.values.every((c) => !c.enabled)) {
      _toast("At least one display must stay enabled");
      return;
    }
    setState(() => _busy = true);
    final Map<_Head, _HeadConfig> previous = {
      for (final _Head h in _heads) h: _HeadConfig.from(h),
    };
    final Map<_Head, _HeadConfig> wanted = Map.of(_pending);

    final bool tested = await _applyConfigs(wanted, testOnly: true);
    if (!tested) {
      setState(() => _busy = false);
      _toast("The compositor rejected this configuration");
      return;
    }
    final bool applied = await _applyConfigs(wanted);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!applied) {
      _toast("Couldn't apply the configuration");
      return;
    }

    final bool keep = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const _KeepChangesDialog(),
        ) ??
        false;
    if (!keep) {
      await _connection?.roundtrip();
      await _applyConfigs(previous);
      return;
    }
    // Applied again at every login and whenever these monitors are
    // connected (pangolin-displays).
    try {
      DisplayProfiles.save([
        for (final MapEntry<_Head, _HeadConfig> e in wanted.entries)
          OutputSettings(
            id: outputId(
              name: e.key.name,
              make: e.key.make,
              model: e.key.model,
              serial: e.key.serial,
            ),
            enabled: e.value.enabled,
            width: e.value.mode?.width ?? 0,
            height: e.value.mode?.height ?? 0,
            refresh: e.value.mode?.refresh ?? 0,
            scale: e.value.scale,
            transform: e.value.transform,
            x: e.value.x,
            y: e.value.y,
          ),
      ]);
    } on Object catch (e) {
      _toast("Couldn't save the display settings: $e");
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (_error != null) {
      return EmptyState(icon: Icons.desktop_access_disabled_rounded, title: "Displays unavailable", subtitle: _error);
    }
    if (_manager == null) return const Center(child: CircularProgressIndicator());

    return SettingsPageBody(
      children: [
        _Arrangement(heads: _heads, pending: _pending),
        const SizedBox(height: 16),
        for (final _Head head in _heads)
          if (_pending[head] case final _HeadConfig config)
            SettingsGroup(
              title: head.description.isNotEmpty ? head.description : head.name,
              children: [
                SettingsRow(
                  icon: Icons.monitor_rounded,
                  title: head.name,
                  subtitle: [
                    if (head.make.isNotEmpty) "${head.make} ${head.model}".trim(),
                    if (head.physicalWidth > 0)
                      "${head.physicalWidth} × ${head.physicalHeight} mm",
                  ].join(" · "),
                  trailing: ZenitSwitch(
                    value: config.enabled,
                    onChanged: (v) => setState(() => config.enabled = v),
                  ),
                ),
                if (config.enabled && head.modes.isNotEmpty)
                  SettingsRow(
                    title: "Resolution",
                    trailing: DropdownButton<_Mode>(
                      value: config.mode,
                      underline: const SizedBox(),
                      items: [
                        for (final _Mode m in head.modes)
                          DropdownMenuItem(
                            value: m,
                            child: Text("${m.label}${m.preferred ? "  (recommended)" : ""}"),
                          ),
                      ],
                      onChanged: (m) => setState(() => config.mode = m),
                    ),
                  ),
                if (config.enabled)
                  Builder(
                    builder: (context) {
                      final List<double> scales =
                          _scalesFor(config.mode, config.scale);
                      final double? recommended =
                          _recommendedFor(head, config.mode);
                      final double current = scales.firstWhere(
                        (s) => (s - config.scale).abs() < 0.005,
                      );
                      return SettingsRow(
                        title: "Scale",
                        trailing: DropdownButton<double>(
                          value: current,
                          underline: const SizedBox(),
                          items: [
                            for (final double s in scales)
                              DropdownMenuItem(
                                value: s,
                                child: Text(
                                  "${scaleLabel(s)}"
                                  "${recommended != null && (s - recommended).abs() < 0.005 ? "  (recommended)" : ""}",
                                ),
                              ),
                          ],
                          onChanged: (s) =>
                              setState(() => config.scale = s ?? 1),
                        ),
                      );
                    },
                  ),
                if (config.enabled)
                  SettingsRow(
                    title: "Rotation",
                    trailing: DropdownButton<int>(
                      value: _transforms.containsKey(config.transform) ? config.transform : 0,
                      underline: const SizedBox(),
                      items: [
                        for (final MapEntry<int, String> t in _transforms.entries)
                          DropdownMenuItem(value: t.key, child: Text(t.value)),
                      ],
                      onChanged: (t) => setState(() => config.transform = t ?? 0),
                    ),
                  ),
              ],
            ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _dirty
                  ? () => setState(() {
                        for (final _Head h in _heads) {
                          _pending[h] = _HeadConfig.from(h);
                        }
                      })
                  : null,
              child: const Text("Reset"),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _dirty && !_busy ? _apply : null,
              child: _busy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                    )
                  : const Text("Apply"),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const NightShiftGroup(),
      ],
    );
  }
}

/// Miniature of the output layout.
class _Arrangement extends StatelessWidget {
  const _Arrangement({required this.heads, required this.pending});

  final List<_Head> heads;
  final Map<_Head, _HeadConfig> pending;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<(_Head, Rect)> rects = [
      for (final _Head h in heads)
        if (pending[h]?.enabled ?? h.enabled)
          (
            h,
            Rect.fromLTWH(
              h.x.toDouble(),
              h.y.toDouble(),
              (pending[h]?.mode?.width ?? h.currentMode?.width ?? 1920) / (pending[h]?.scale ?? h.scale),
              (pending[h]?.mode?.height ?? h.currentMode?.height ?? 1080) / (pending[h]?.scale ?? h.scale),
            ),
          ),
    ];
    if (rects.isEmpty) return const SizedBox();
    final Rect bounds = rects.map((r) => r.$2).reduce((a, b) => a.expandToInclude(b));

    return ZenitSection(
      child: SizedBox(
        height: 180,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double scale = ((constraints.maxWidth - 48) / bounds.width)
                .clamp(0.0, (180 - 48) / bounds.height);
            final double offsetX = (constraints.maxWidth - bounds.width * scale) / 2;
            final double offsetY = (180 - bounds.height * scale) / 2;
            return Stack(
              children: [
                for (final (head, rect) in rects)
                  Positioned(
                    left: offsetX + (rect.left - bounds.left) * scale,
                    top: offsetY + (rect.top - bounds.top) * scale,
                    width: rect.width * scale,
                    height: rect.height * scale,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        border: Border.all(color: theme.colorScheme.primary, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(head.name, style: theme.textTheme.labelLarge),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KeepChangesDialog extends StatefulWidget {
  const _KeepChangesDialog();

  @override
  State<_KeepChangesDialog> createState() => _KeepChangesDialogState();
}

class _KeepChangesDialogState extends State<_KeepChangesDialog> {
  int _seconds = 15;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_seconds <= 1) {
        _timer.cancel();
        Navigator.pop(context, false);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Keep these display settings?"),
      content: Text("Reverting in $_seconds seconds."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Revert")),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text("Keep Changes")),
      ],
    );
  }
}
