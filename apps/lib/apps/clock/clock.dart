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

import 'package:dahlia_apps/kit/kit.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final DahliaAppSpec clockApp = DahliaAppSpec(
  name: "clock",
  title: "Clock",
  builder: (context, args) => const ClockPage(),
);

/// Cities offered for world clocks.
const Map<String, String> _cities = {
  "Amsterdam": "Europe/Amsterdam",
  "Auckland": "Pacific/Auckland",
  "Bangkok": "Asia/Bangkok",
  "Berlin": "Europe/Berlin",
  "Buenos Aires": "America/Argentina/Buenos_Aires",
  "Cairo": "Africa/Cairo",
  "Chicago": "America/Chicago",
  "Delhi": "Asia/Kolkata",
  "Denver": "America/Denver",
  "Dubai": "Asia/Dubai",
  "Hong Kong": "Asia/Hong_Kong",
  "Honolulu": "Pacific/Honolulu",
  "Istanbul": "Europe/Istanbul",
  "Jakarta": "Asia/Jakarta",
  "Johannesburg": "Africa/Johannesburg",
  "Lagos": "Africa/Lagos",
  "Lisbon": "Europe/Lisbon",
  "London": "Europe/London",
  "Los Angeles": "America/Los_Angeles",
  "Madrid": "Europe/Madrid",
  "Mexico City": "America/Mexico_City",
  "Moscow": "Europe/Moscow",
  "Nairobi": "Africa/Nairobi",
  "New York": "America/New_York",
  "Paris": "Europe/Paris",
  "Rome": "Europe/Rome",
  "São Paulo": "America/Sao_Paulo",
  "Seoul": "Asia/Seoul",
  "Shanghai": "Asia/Shanghai",
  "Singapore": "Asia/Singapore",
  "Stockholm": "Europe/Stockholm",
  "Sydney": "Australia/Sydney",
  "Tokyo": "Asia/Tokyo",
  "Toronto": "America/Toronto",
  "Vancouver": "America/Vancouver",
  "Warsaw": "Europe/Warsaw",
};

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  final DesktopNotifications _notifications =
      DesktopNotifications("Clock", appIcon: "io.dahliaos.clock");
  AppStorage? _storage;
  late final Timer _ticker;
  DateTime _now = DateTime.now();

  final List<String> _worldClocks = [];
  final List<_Alarm> _alarms = [];
  String? _lastAlarmMinute;

  @override
  void initState() {
    super.initState();
    tzdata.initializeTimeZones();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _load();
  }

  Future<void> _load() async {
    final AppStorage storage = await AppStorage.open("clock");
    setState(() {
      _storage = storage;
      _worldClocks.addAll(storage.get<List>("world_clocks")?.cast<String>() ??
          ["London", "New York", "Tokyo"]);
      _alarms.addAll(storage.getList("alarms").map(_Alarm.fromJson));
    });
  }

  void _save() {
    _storage?.set("world_clocks", _worldClocks);
    _storage?.set("alarms", _alarms.map((a) => a.toJson()).toList());
  }

  @override
  void dispose() {
    _ticker.cancel();
    _tabs.dispose();
    _notifications.close();
    super.dispose();
  }

  void _tick() {
    setState(() => _now = DateTime.now());
    final String minute = DateFormat("yyyyMMddHHmm").format(_now);
    if (minute == _lastAlarmMinute) return;
    for (final _Alarm alarm in _alarms) {
      if (alarm.shouldRing(_now)) {
        _lastAlarmMinute = minute;
        _ring(alarm);
        if (alarm.days.isEmpty && alarm.snoozedUntil == null) {
          alarm.enabled = false;
        }
        alarm.snoozedUntil = null;
        _save();
      }
    }
  }

  Future<void> _ring(_Alarm alarm) async {
    final String time = alarm.formatted;
    _notifications.notify(
      alarm.label.isEmpty ? "Alarm" : alarm.label,
      body: "It's $time",
    );
    if (!mounted) return;
    final bool? snooze = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.alarm_rounded, size: 40),
        title: Text(alarm.label.isEmpty ? "Alarm" : alarm.label),
        content: Text(time, style: Theme.of(context).textTheme.displaySmall),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Snooze 5 min"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Stop"),
          ),
        ],
      ),
    );
    if (snooze ?? false) {
      setState(() {
        alarm.snoozedUntil = DateTime.now().add(const Duration(minutes: 5));
        alarm.enabled = true;
      });
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DahliaScaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.schedule_rounded), text: "Clock"),
              Tab(icon: Icon(Icons.alarm_rounded), text: "Alarms"),
              Tab(icon: Icon(Icons.hourglass_bottom_rounded), text: "Timer"),
              Tab(icon: Icon(Icons.timer_outlined), text: "Stopwatch"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _WorldClockTab(
                  now: _now,
                  cities: _worldClocks,
                  onAdd: (city) {
                    setState(() => _worldClocks.add(city));
                    _save();
                  },
                  onRemove: (city) {
                    setState(() => _worldClocks.remove(city));
                    _save();
                  },
                ),
                _AlarmsTab(
                  alarms: _alarms,
                  onChanged: () {
                    setState(() {});
                    _save();
                  },
                ),
                _TimerTab(notifications: _notifications),
                const _StopwatchTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Clock
// ============================================================================

class _WorldClockTab extends StatelessWidget {
  const _WorldClockTab({
    required this.now,
    required this.cities,
    required this.onAdd,
    required this.onRemove,
  });

  final DateTime now;
  final List<String> cities;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration localOffset = now.timeZoneOffset;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth > 640;
        final Widget face = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: math.min(240, constraints.maxHeight * 0.45),
              child: CustomPaint(painter: _AnalogClockPainter(now, theme)),
            ),
            const SizedBox(height: 16),
            Text(
              DateFormat.Hms().format(now),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              DateFormat.yMMMMEEEEd().format(now),
              style: theme.textTheme.titleMedium,
            ),
          ],
        );

        final Widget list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Text("World clocks", style: theme.textTheme.titleSmall),
                  const Spacer(),
                  IconButton(
                    tooltip: "Add city",
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () async {
                      final String? city = await showDialog<String>(
                        context: context,
                        builder: (context) => _CityPicker(exclude: cities),
                      );
                      if (city != null) onAdd(city);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final String city in cities)
                    if (_cities[city] case final String zone)
                      Builder(
                        builder: (context) {
                          final tz.TZDateTime time =
                              tz.TZDateTime.now(tz.getLocation(zone));
                          final Duration diff = time.timeZoneOffset - localOffset;
                          final String relative = diff == Duration.zero
                              ? "Same time"
                              : "${diff.isNegative ? "" : "+"}${(diff.inMinutes / 60).toStringAsFixed(diff.inMinutes % 60 == 0 ? 0 : 1)}h";
                          return ListTile(
                            title: Text(city),
                            subtitle: Text(
                              "${DateFormat.MMMEd().format(time)} · $relative",
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  DateFormat.Hm().format(time),
                                  style: theme.textTheme.headlineSmall,
                                ),
                                IconButton(
                                  tooltip: "Remove",
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  onPressed: () => onRemove(city),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
          ],
        );

        return wide
            ? Row(
                children: [
                  Expanded(child: face),
                  SidebarPane(width: 320, child: list),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 3, child: face),
                  const Divider(height: 1),
                  Expanded(flex: 2, child: list),
                ],
              );
      },
    );
  }
}

class _CityPicker extends StatefulWidget {
  const _CityPicker({required this.exclude});
  final List<String> exclude;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final List<String> matches = _cities.keys
        .where((c) => !widget.exclude.contains(c))
        .where((c) => c.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text("Add a city"),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(
          children: [
            SearchField(autofocus: true, onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final String city in matches)
                    ListTile(
                      dense: true,
                      title: Text(city),
                      subtitle: Text(_cities[city]!),
                      onTap: () => Navigator.pop(context, city),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  _AnalogClockPainter(this.time, this.theme);

  final DateTime time;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    final Color fg = theme.colorScheme.onSurface;
    final Color accent = theme.colorScheme.primary;

    canvas.drawCircle(c, r, Paint()..color = theme.colorScheme.surface);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = fg.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (int i = 0; i < 60; i++) {
      final double a = i * math.pi / 30;
      final bool hour = i % 5 == 0;
      final double inner = r * (hour ? 0.84 : 0.9);
      canvas.drawLine(
        c + Offset(math.sin(a), -math.cos(a)) * inner,
        c + Offset(math.sin(a), -math.cos(a)) * r * 0.95,
        Paint()
          ..color = fg.withValues(alpha: hour ? 0.7 : 0.25)
          ..strokeWidth = hour ? 3 : 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    void hand(double angle, double length, double width, Color color) {
      canvas.drawLine(
        c - Offset(math.sin(angle), -math.cos(angle)) * r * 0.08,
        c + Offset(math.sin(angle), -math.cos(angle)) * r * length,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    final double seconds = time.second.toDouble();
    final double minutes = time.minute + seconds / 60;
    final double hours = time.hour % 12 + minutes / 60;
    hand(hours * math.pi / 6, 0.5, 6, fg);
    hand(minutes * math.pi / 30, 0.72, 4, fg);
    hand(seconds * math.pi / 30, 0.8, 2, accent);
    canvas.drawCircle(c, 5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_AnalogClockPainter old) =>
      old.time.second != time.second || old.theme != theme;
}

// ============================================================================
// Alarms
// ============================================================================

class _Alarm {
  _Alarm({
    required this.hour,
    required this.minute,
    this.label = "",
    this.enabled = true,
    List<int>? days,
  }) : days = days ?? [];

  factory _Alarm.fromJson(Map<String, Object?> json) => _Alarm(
        hour: json["hour"]! as int,
        minute: json["minute"]! as int,
        label: json["label"] as String? ?? "",
        enabled: json["enabled"] as bool? ?? true,
        days: (json["days"] as List?)?.cast<int>(),
      );

  int hour;
  int minute;
  String label;
  bool enabled;

  /// ISO weekdays (1 = Monday). Empty means "ring once".
  List<int> days;
  DateTime? snoozedUntil;

  String get formatted =>
      "${hour.toString().padLeft(2, "0")}:${minute.toString().padLeft(2, "0")}";

  bool shouldRing(DateTime now) {
    final DateTime? snooze = snoozedUntil;
    if (snooze != null) {
      return now.hour == snooze.hour && now.minute == snooze.minute;
    }
    if (!enabled || now.hour != hour || now.minute != minute) return false;
    return days.isEmpty || days.contains(now.weekday);
  }

  Map<String, Object?> toJson() => {
        "hour": hour,
        "minute": minute,
        "label": label,
        "enabled": enabled,
        "days": days,
      };
}

class _AlarmsTab extends StatelessWidget {
  const _AlarmsTab({required this.alarms, required this.onChanged});

  final List<_Alarm> alarms;
  final VoidCallback onChanged;

  static const List<String> _dayNames = ["M", "T", "W", "T", "F", "S", "S"];

  Future<void> _edit(BuildContext context, [_Alarm? alarm]) async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: alarm != null
          ? TimeOfDay(hour: alarm.hour, minute: alarm.minute)
          : TimeOfDay.now(),
    );
    if (time == null) return;
    if (alarm == null) {
      alarms.add(_Alarm(hour: time.hour, minute: time.minute));
    } else {
      alarm
        ..hour = time.hour
        ..minute = time.minute
        ..enabled = true;
    }
    alarms.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        tooltip: "New alarm",
        onPressed: () => _edit(context),
        child: const Icon(Icons.add_alarm_rounded),
      ),
      body: alarms.isEmpty
          ? const EmptyState(
              icon: Icons.alarm_off_rounded,
              title: "No alarms",
              subtitle: "Alarms ring while Clock is open",
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final _Alarm alarm in alarms)
                  ZenitSection(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => _edit(context, alarm),
                                  child: Text(
                                    alarm.formatted,
                                    style: theme.textTheme.displaySmall?.copyWith(
                                      color: alarm.enabled
                                          ? null
                                          : theme.disabledColor,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 240,
                                  child: TextFormField(
                                    initialValue: alarm.label,
                                    decoration: const InputDecoration(
                                      hintText: "Label",
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (v) {
                                      alarm.label = v;
                                      onChanged();
                                    },
                                  ),
                                ),
                                Row(
                                  children: [
                                    for (int d = 1; d <= 7; d++)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 4),
                                        child: ChoiceChip(
                                          label: Text(_dayNames[d - 1]),
                                          selected: alarm.days.contains(d),
                                          visualDensity: VisualDensity.compact,
                                          onSelected: (selected) {
                                            selected
                                                ? alarm.days.add(d)
                                                : alarm.days.remove(d);
                                            onChanged();
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ZenitSwitch(
                            value: alarm.enabled,
                            onChanged: (v) {
                              alarm.enabled = v;
                              onChanged();
                            },
                          ),
                          IconButton(
                            tooltip: "Delete",
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () {
                              alarms.remove(alarm);
                              onChanged();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ============================================================================
// Timer
// ============================================================================

class _TimerTab extends StatefulWidget {
  const _TimerTab({required this.notifications});
  final DesktopNotifications notifications;

  @override
  State<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<_TimerTab>
    with AutomaticKeepAliveClientMixin {
  Duration _total = const Duration(minutes: 5);
  Duration _remaining = const Duration(minutes: 5);
  Timer? _timer;
  DateTime? _endsAt;

  bool get _running => _timer != null;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_remaining <= Duration.zero) _remaining = _total;
    _endsAt = DateTime.now().add(_remaining);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final Duration left = _endsAt!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _finish();
      } else {
        setState(() => _remaining = left);
      }
    });
    setState(() {});
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _timer = null);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _remaining = _total;
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() {
      _timer = null;
      _remaining = Duration.zero;
    });
    widget.notifications.notify(
      "Time's up",
      body: "Your ${_format(_total)} timer has finished",
    );
  }

  void _set(Duration d) {
    if (_running) return;
    setState(() {
      _total = d;
      _remaining = d;
    });
  }

  static String _format(Duration d) {
    final int h = d.inHours;
    final String m = (d.inMinutes % 60).toString().padLeft(2, "0");
    final String s = (d.inSeconds % 60).toString().padLeft(2, "0");
    return h > 0 ? "$h:$m:$s" : "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ThemeData theme = Theme.of(context);
    final double progress = _total.inMilliseconds == 0
        ? 0
        : _remaining.inMilliseconds / _total.inMilliseconds;

    Widget adjust(String label, Duration step) => Column(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: _running ? null : () => _set(_total + step),
            ),
            Text(label, style: theme.textTheme.labelSmall),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: _running || _total <= step ? null : () => _set(_total - step),
            ),
          ],
        );

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 240,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: theme.colorScheme.surface,
                  ),
                  Center(
                    child: Text(
                      _format(_remaining),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                adjust("hours", const Duration(hours: 1)),
                adjust("min", const Duration(minutes: 1)),
                adjust("sec", const Duration(seconds: 10)),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final int m in [1, 3, 5, 10, 15, 30])
                  ActionChip(
                    label: Text("$m min"),
                    onPressed: _running ? null : () => _set(Duration(minutes: m)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(_running ? "Pause" : "Start"),
                  onPressed: _running ? _pause : _start,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.replay_rounded),
                  label: const Text("Reset"),
                  onPressed: _reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Stopwatch
// ============================================================================

class _StopwatchTab extends StatefulWidget {
  const _StopwatchTab();

  @override
  State<_StopwatchTab> createState() => _StopwatchTabState();
}

class _StopwatchTabState extends State<_StopwatchTab>
    with AutomaticKeepAliveClientMixin {
  final Stopwatch _stopwatch = Stopwatch();
  final List<Duration> _laps = [];
  Timer? _ticker;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _ticker?.cancel();
      } else {
        _stopwatch.start();
        _ticker = Timer.periodic(
          const Duration(milliseconds: 30),
          (_) => setState(() {}),
        );
      }
    });
  }

  static String _format(Duration d) {
    final String m = d.inMinutes.toString().padLeft(2, "0");
    final String s = (d.inSeconds % 60).toString().padLeft(2, "0");
    final String cs = (d.inMilliseconds % 1000 ~/ 10).toString().padLeft(2, "0");
    return d.inHours > 0 ? "${d.inHours}:$m:$s.$cs" : "$m:$s.$cs";
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ThemeData theme = Theme.of(context);
    final Duration elapsed = _stopwatch.elapsed;

    return Column(
      children: [
        const SizedBox(height: 32),
        Text(
          _format(elapsed),
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w300,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.icon(
              icon: Icon(_stopwatch.isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(_stopwatch.isRunning ? "Stop" : "Start"),
              onPressed: _toggle,
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              icon: Icon(_stopwatch.isRunning ? Icons.flag_outlined : Icons.replay_rounded),
              label: Text(_stopwatch.isRunning ? "Lap" : "Reset"),
              onPressed: elapsed == Duration.zero
                  ? null
                  : () => setState(() {
                        if (_stopwatch.isRunning) {
                          _laps.insert(0, elapsed);
                        } else {
                          _stopwatch.reset();
                          _laps.clear();
                        }
                      }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: _laps.length,
            itemBuilder: (context, index) {
              final Duration lap = _laps[index];
              final Duration previous =
                  index + 1 < _laps.length ? _laps[index + 1] : Duration.zero;
              return ListTile(
                leading: Text("Lap ${_laps.length - index}"),
                title: Text("+${_format(lap - previous)}"),
                trailing: Text(_format(lap)),
              );
            },
          ),
        ),
      ],
    );
  }
}
