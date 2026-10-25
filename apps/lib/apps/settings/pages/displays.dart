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
import 'dart:math' as math;

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

/// Where [config] puts [head] in the layout, in logical pixels.
LayoutBox _boxOf(_Head head, _HeadConfig config) {
  final _Mode? mode = config.mode ?? head.currentMode;
  final (int width, int height) = logicalSize(
    mode?.width ?? 1920,
    mode?.height ?? 1080,
    config.scale,
    config.transform,
  );
  return LayoutBox(x: config.x, y: config.y, width: width, height: height);
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
            // A layout that overlaps (or falls apart) shows fixed, ready to
            // apply.
            _relayout();
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

  /// Moves the enabled displays so none overlaps another and they hang
  /// together ([settle]). [moved], just dropped in the arrangement, is
  /// placed last and lines up with edges within [snap] logical pixels.
  void _relayout({_Head? moved, int snap = 0}) {
    final Map<_Head, LayoutBox> boxes = {
      for (final MapEntry<_Head, _HeadConfig> e in _pending.entries)
        if (e.value.enabled) e.key: _boxOf(e.key, e.value),
    };
    settle(boxes.values.toList(), moved: boxes[moved], snap: snap);
    for (final MapEntry<_Head, LayoutBox> e in boxes.entries) {
      _pending[e.key]!
        ..x = e.value.x
        ..y = e.value.y;
    }
  }

  /// Changes [config] and settles the layout around the new size.
  void _update(VoidCallback change) => setState(() {
        change();
        _relayout();
      });

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
    final List<(_Head, OutputSettings)> saved = [
      for (final MapEntry<_Head, _HeadConfig> e in wanted.entries)
        (
          e.key,
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
        ),
    ];
    try {
      DisplayProfiles.save([for (final (_, OutputSettings o) in saved) o]);
    } on Object catch (e) {
      _toast("Couldn't save the display settings: $e");
    }
    // GNOME's monitors.xml too: the familiar file, and what GDM reads
    // (copied to /etc/xdg).
    try {
      MonitorsXml.save([
        for (final (_Head h, OutputSettings o) in saved)
          (
            MonitorsXml.specOf(
              connector: h.name,
              make: h.make,
              model: h.model,
              serial: h.serial,
            ),
            o,
          ),
      ]);
    } on Object catch (e) {
      _toast("Couldn't update monitors.xml: $e");
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
        _Arrangement(
          heads: _heads,
          pending: _pending,
          onMoved: (head, x, y, snap) => setState(() {
            _pending[head]!
              ..x = x
              ..y = y;
            _relayout(moved: head, snap: snap);
          }),
        ),
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
                    onChanged: (v) => _update(() => config.enabled = v),
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
                      onChanged: (m) => _update(() => config.mode = m),
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
                              _update(() => config.scale = s ?? 1),
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
                      onChanged: (t) => _update(() => config.transform = t ?? 0),
                    ),
                  ),
              ],
            ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _dirty
                  ? () => _update(() {
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

/// Miniature of the pending layout. Displays can be dragged; where one is
/// dropped, it snaps against the others (no overlap, no gap).
class _Arrangement extends StatefulWidget {
  const _Arrangement({
    required this.heads,
    required this.pending,
    required this.onMoved,
  });

  final List<_Head> heads;
  final Map<_Head, _HeadConfig> pending;

  /// [head] dropped at [x], [y] (logical pixels); edges within [snap]
  /// logical pixels should line up.
  final void Function(_Head head, int x, int y, int snap) onMoved;

  @override
  State<_Arrangement> createState() => _ArrangementState();
}

class _ArrangementState extends State<_Arrangement> {
  static const double _height = 180;
  static const double _margin = 24;

  /// Pointer distance, in screen pixels, within which a dropped display
  /// lines up with an edge.
  static const double _snapPixels = 10;

  _Head? _dragged;
  Offset _delta = Offset.zero;

  /// Placement of the miniature while a display is dragged: kept from the
  /// start of the drag, so the others don't move or rescale under it.
  ({Rect bounds, double scale, Offset origin})? _frozen;

  ({Rect bounds, double scale, Offset origin}) _fit(
    Iterable<LayoutBox> boxes,
    double width,
  ) {
    final Rect bounds = boxes
        .map((b) => Rect.fromLTWH(b.x.toDouble(), b.y.toDouble(), b.width.toDouble(), b.height.toDouble()))
        .reduce((a, b) => a.expandToInclude(b));
    final double scale = math.min(
      (width - _margin * 2) / bounds.width,
      (_height - _margin * 2) / bounds.height,
    );
    return (
      bounds: bounds,
      scale: scale,
      origin: Offset(
        (width - bounds.width * scale) / 2,
        (_height - bounds.height * scale) / 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<_Head, LayoutBox> boxes = {
      for (final _Head h in widget.heads)
        if (widget.pending[h] case final _HeadConfig c when c.enabled)
          h: _boxOf(h, c),
    };
    if (boxes.isEmpty) return const SizedBox();
    final bool movable = boxes.length > 1;

    return ZenitSection(
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fit = _frozen ?? _fit(boxes.values, constraints.maxWidth);
            Rect place(LayoutBox b) => Rect.fromLTWH(
                  fit.origin.dx + (b.x - fit.bounds.left) * fit.scale,
                  fit.origin.dy + (b.y - fit.bounds.top) * fit.scale,
                  b.width * fit.scale,
                  b.height * fit.scale,
                );
            // The dragged display on top.
            final List<_Head> order = [
              for (final _Head h in boxes.keys)
                if (h != _dragged) h,
              if (_dragged != null && boxes.containsKey(_dragged)) _dragged!,
            ];
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final _Head head in order)
                  Positioned.fromRect(
                    rect: head == _dragged
                        ? place(boxes[head]!).shift(_delta)
                        : place(boxes[head]!),
                    child: MouseRegion(
                      cursor: !movable
                          ? MouseCursor.defer
                          : head == _dragged
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                      child: GestureDetector(
                        onPanStart: !movable
                            ? null
                            : (_) => setState(() {
                                  _dragged = head;
                                  _delta = Offset.zero;
                                  _frozen = fit;
                                }),
                        onPanUpdate: !movable
                            ? null
                            : (d) => setState(() => _delta += d.delta),
                        onPanEnd: !movable ? null : (_) => _drop(boxes),
                        onPanCancel: !movable ? null : () => _drop(boxes),
                        child: _DisplayTile(
                          label: head.name,
                          dragging: head == _dragged,
                          theme: theme,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _drop(Map<_Head, LayoutBox> boxes) {
    final _Head? head = _dragged;
    final fit = _frozen;
    setState(() {
      _dragged = null;
      _frozen = null;
    });
    if (head == null || fit == null) return;
    final LayoutBox box = boxes[head]!;
    widget.onMoved(
      head,
      box.x + (_delta.dx / fit.scale).round(),
      box.y + (_delta.dy / fit.scale).round(),
      (_snapPixels / fit.scale).round(),
    );
    _delta = Offset.zero;
  }
}

class _DisplayTile extends StatelessWidget {
  const _DisplayTile({
    required this.label,
    required this.dragging,
    required this.theme,
  });

  final String label;
  final bool dragging;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.colorScheme.primary.withValues(alpha: dragging ? 0.35 : 0.2),
          sectionColor(theme),
        ),
        border: Border.all(color: theme.colorScheme.primary, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
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
