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
import 'dart:io';
import 'dart:math' as math;

import 'package:dahlia_apps/apps/activity_monitor/system_stats.dart';
import 'package:dahlia_apps/kit/kit.dart';

final DahliaAppSpec activityMonitorApp = DahliaAppSpec(
  name: "activity_monitor",
  title: "Activity Monitor",
  builder: (context, args) => const ActivityMonitorPage(),
);

const int _historyLength = 60;

enum _Sort { name, pid, user, cpu, memory }

class ActivityMonitorPage extends StatefulWidget {
  const ActivityMonitorPage({super.key});

  @override
  State<ActivityMonitorPage> createState() => _ActivityMonitorPageState();
}

class _ActivityMonitorPageState extends State<ActivityMonitorPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final Timer _timer;

  List<ProcessInfo> _processes = [];
  final Map<int, int> _previousTicks = {};
  SystemSample? _previous;
  SystemSample? _sample;
  SystemRates? _rates;

  final List<double> _cpuHistory = [];
  final List<List<double>> _coreHistory = [];
  final List<double> _memHistory = [];
  final List<double> _swapHistory = [];
  final List<double> _rxHistory = [];
  final List<double> _txHistory = [];
  final List<double> _readHistory = [];
  final List<double> _writeHistory = [];

  _Sort _sort = _Sort.cpu;
  bool _descending = true;
  String _filter = "";
  bool _onlyMine = false;
  int? _selected;

  final String _cpuModel = ProcFs.cpuModel();

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer.cancel();
    _tabs.dispose();
    super.dispose();
  }

  void _push(List<double> history, double value) {
    history.add(value);
    if (history.length > _historyLength) history.removeAt(0);
  }

  void _refresh() {
    final SystemSample sample = ProcFs.sample();
    final List<ProcessInfo> processes = ProcFs.processes();

    final SystemSample? previous = _sample;
    if (previous != null) {
      final int totalDelta = sample.cpu.total - previous.cpu.total;
      for (final ProcessInfo proc in processes) {
        final int? before = _previousTicks[proc.pid];
        if (before != null && totalDelta > 0) {
          proc.cpuPercent = ((proc.cpuTicks - before) / totalDelta * 100).clamp(0, 100).toDouble();
        }
      }
      final SystemRates rates = ProcFs.rates(previous, sample);
      _rates = rates;
      _push(_cpuHistory, rates.cpu);
      while (_coreHistory.length < rates.cores.length) {
        _coreHistory.add([]);
      }
      for (int i = 0; i < rates.cores.length; i++) {
        _push(_coreHistory[i], rates.cores[i]);
      }
      _push(_rxHistory, rates.netRxPerSec);
      _push(_txHistory, rates.netTxPerSec);
      _push(_readHistory, rates.diskReadPerSec);
      _push(_writeHistory, rates.diskWritePerSec);
    }
    if (sample.memTotal > 0) _push(_memHistory, sample.memUsed / sample.memTotal * 100);
    if (sample.swapTotal > 0) _push(_swapHistory, sample.swapUsed / sample.swapTotal * 100);

    _previousTicks
      ..clear()
      ..addEntries(processes.map((pr) => MapEntry(pr.pid, pr.cpuTicks)));

    if (!mounted) return;
    setState(() {
      _previous = previous;
      _sample = sample;
      _processes = processes;
    });
  }

  List<ProcessInfo> get _visibleProcesses {
    final String me = SystemUtils.user;
    final List<ProcessInfo> list = _processes.where((pr) {
      if (_onlyMine && pr.user != me) return false;
      if (_filter.isEmpty) return true;
      final String q = _filter.toLowerCase();
      return pr.name.toLowerCase().contains(q) ||
          pr.commandLine.toLowerCase().contains(q) ||
          pr.pid.toString() == q;
    }).toList();
    int compare(ProcessInfo a, ProcessInfo b) => switch (_sort) {
          _Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          _Sort.pid => a.pid.compareTo(b.pid),
          _Sort.user => a.user.compareTo(b.user),
          _Sort.cpu => a.cpuPercent.compareTo(b.cpuPercent),
          _Sort.memory => a.rssBytes.compareTo(b.rssBytes),
        };
    list.sort((a, b) => _descending ? compare(b, a) : compare(a, b));
    return list;
  }

  Future<void> _signal(ProcessInfo proc, ProcessSignal signal) async {
    final bool kill = signal == ProcessSignal.sigkill;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${kill ? "Kill" : "End"} ${proc.name}?"),
        content: Text(
          kill
              ? "The process will be stopped immediately. Unsaved data will be lost."
              : "The process will be asked to quit.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(kill ? "Kill" : "End Process")),
        ],
      ),
    );
    if (ok != true) return;
    final bool sent = Process.killPid(proc.pid, signal);
    if (!sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't signal ${proc.name} (permission denied?)")),
      );
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DahliaScaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: "Processes"),
              Tab(text: "Performance"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _processesTab(),
                _performanceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _processesTab() {
    final ThemeData theme = Theme.of(context);
    final List<ProcessInfo> processes = _visibleProcesses;
    final ProcessInfo? selected =
        processes.where((pr) => pr.pid == _selected).firstOrNull;
    final SystemSample? sample = _sample;

    Widget header(String label, _Sort sort, {int flex = 1, bool numeric = false}) => Expanded(
          flex: flex,
          child: InkWell(
            onTap: () => setState(() {
              if (_sort == sort) {
                _descending = !_descending;
              } else {
                _sort = sort;
                _descending = numeric;
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  if (_sort == sort)
                    Icon(_descending ? Icons.arrow_drop_down_rounded : Icons.arrow_drop_up_rounded, size: 18),
                ],
              ),
            ),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              SearchField(width: 260, hint: "Search processes", onChanged: (v) => setState(() => _filter = v)),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text("My processes"),
                selected: _onlyMine,
                onSelected: (v) => setState(() => _onlyMine = v),
              ),
              const Spacer(),
              if (sample != null && _rates != null)
                Text(
                  "CPU ${_rates!.cpu.toStringAsFixed(0)}%  ·  "
                  "Memory ${formatBytes(sample.memUsed)} / ${formatBytes(sample.memTotal)}  ·  "
                  "${_processes.length} processes",
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: selected == null ? null : () => _signal(selected, ProcessSignal.sigterm),
                child: const Text("End Process"),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              header("Name", _Sort.name, flex: 4),
              header("PID", _Sort.pid, numeric: true),
              const SizedBox(width: 16),
              header("User", _Sort.user, flex: 2),
              header("CPU", _Sort.cpu, numeric: true),
              header("Memory", _Sort.memory, flex: 2, numeric: true),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: processes.length,
            itemExtent: 32,
            itemBuilder: (context, index) {
              final ProcessInfo pr = processes[index];
              final bool isSelected = pr.pid == _selected;
              return GestureDetector(
                onSecondaryTapUp: (d) => _processMenu(pr, d.globalPosition),
                child: InkWell(
                  onTap: () => setState(() => _selected = pr.pid),
                  onDoubleTap: () => _details(pr),
                  child: Container(
                    color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(pr.name, overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(child: Text("${pr.pid}", textAlign: TextAlign.end, style: theme.textTheme.bodySmall)),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: Text(pr.user, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
                        Expanded(
                          child: Text(
                            "${pr.cpuPercent.toStringAsFixed(1)}%",
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: pr.cpuPercent > 50 ? theme.colorScheme.error : null,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(formatBytes(pr.rssBytes), textAlign: TextAlign.end, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _processMenu(ProcessInfo pr, Offset position) async {
    setState(() => _selected = pr.pid);
    final String? action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: const [
        PopupMenuItem(value: "details", child: Text("Details")),
        PopupMenuDivider(),
        PopupMenuItem(value: "stop", child: Text("Pause (SIGSTOP)")),
        PopupMenuItem(value: "cont", child: Text("Continue (SIGCONT)")),
        PopupMenuItem(value: "end", child: Text("End Process")),
        PopupMenuItem(value: "kill", child: Text("Kill")),
      ],
    );
    switch (action) {
      case "details":
        _details(pr);
      case "stop":
        Process.killPid(pr.pid, ProcessSignal.sigstop);
      case "cont":
        Process.killPid(pr.pid, ProcessSignal.sigcont);
      case "end":
        await _signal(pr, ProcessSignal.sigterm);
      case "kill":
        await _signal(pr, ProcessSignal.sigkill);
    }
  }

  void _details(ProcessInfo pr) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pr.name),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoRow(label: "PID", value: "${pr.pid}"),
              InfoRow(label: "User", value: pr.user),
              InfoRow(label: "State", value: pr.stateLabel),
              InfoRow(label: "Threads", value: "${pr.threads}"),
              InfoRow(label: "Memory", value: formatBytes(pr.rssBytes)),
              InfoRow(label: "CPU", value: "${pr.cpuPercent.toStringAsFixed(1)}%"),
              InfoRow(label: "Command", value: pr.commandLine),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  Widget _performanceTab() {
    final ThemeData theme = Theme.of(context);
    final SystemSample? sample = _sample;
    final SystemRates? rates = _rates;
    if (sample == null) return const Center(child: CircularProgressIndicator());

    final Color cpuColor = theme.colorScheme.primary;
    const Color memColor = Color(0xFF7E57C2);
    const Color rxColor = Color(0xFF26A69A);
    const Color txColor = Color(0xFFEF5350);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ChartCard(
          title: "CPU",
          subtitle: _cpuModel,
          value: "${(rates?.cpu ?? 0).toStringAsFixed(0)}%",
          series: [_Series(_cpuHistory, cpuColor)],
          maxValue: 100,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${sample.cores.length} cores  ·  Load ${ProcFs.loadAverage()}  ·  Up ${formatDuration(ProcFs.uptime())}",
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _coreHistory.length; i++)
                    SizedBox(
                      width: 120,
                      height: 44,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ChartPainter(
                                [_Series(_coreHistory[i], cpuColor)],
                                100,
                                theme,
                                grid: false,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text("CPU $i", style: theme.textTheme.labelSmall),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        _ChartCard(
          title: "Memory",
          subtitle: "${formatBytes(sample.memUsed)} of ${formatBytes(sample.memTotal)} used",
          value: "${(sample.memUsed / math.max(1, sample.memTotal) * 100).toStringAsFixed(0)}%",
          series: [_Series(_memHistory, memColor), _Series(_swapHistory, memColor.withValues(alpha: 0.4))],
          maxValue: 100,
          footer: Text(
            sample.swapTotal > 0
                ? "Swap ${formatBytes(sample.swapUsed)} of ${formatBytes(sample.swapTotal)}"
                : "No swap",
            style: theme.textTheme.bodySmall,
          ),
        ),
        _ChartCard(
          title: "Network",
          subtitle: "Received / sent",
          value: "↓ ${formatBytes(rates?.netRxPerSec ?? 0)}/s   ↑ ${formatBytes(rates?.netTxPerSec ?? 0)}/s",
          series: [_Series(_rxHistory, rxColor), _Series(_txHistory, txColor)],
        ),
        _ChartCard(
          title: "Disk",
          subtitle: "Read / write",
          value: "R ${formatBytes(rates?.diskReadPerSec ?? 0)}/s   W ${formatBytes(rates?.diskWritePerSec ?? 0)}/s",
          series: [_Series(_readHistory, rxColor), _Series(_writeHistory, txColor)],
        ),
        if (_previous == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text("Collecting data…"),
          ),
      ],
    );
  }
}

class _Series {
  const _Series(this.values, this.color);
  final List<double> values;
  final Color color;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.series,
    this.maxValue,
    this.footer,
  });

  final String title;
  final String subtitle;
  final String value;
  final List<_Series> series;
  final double? maxValue;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double max = maxValue ??
        math.max(
          1024.0,
          series.expand((s) => s.values).fold<double>(0, math.max) * 1.2,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ZenitSection(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                  const Spacer(),
                  Text(value, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 120,
                width: double.infinity,
                child: CustomPaint(painter: _ChartPainter(series, max, theme)),
              ),
              if (footer != null) ...[const SizedBox(height: 8), footer!],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.series, this.maxValue, this.theme, {this.grid = true});

  final List<_Series> series;
  final double maxValue;
  final ThemeData theme;
  final bool grid;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bounds = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(bounds, Paint()..color = theme.colorScheme.surface);
    canvas.save();
    canvas.clipRRect(bounds);

    if (grid) {
      final Paint gridPaint = Paint()
        ..color = theme.colorScheme.onSurface.withValues(alpha: 0.06)
        ..strokeWidth = 1;
      for (int i = 1; i < 4; i++) {
        final double y = size.height * i / 4;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    final double step = size.width / (_historyLength - 1);
    for (final _Series s in series) {
      if (s.values.length < 2) continue;
      final Path line = Path();
      final double startX = size.width - (s.values.length - 1) * step;
      for (int i = 0; i < s.values.length; i++) {
        final double x = startX + i * step;
        final double y = size.height - (s.values[i] / maxValue).clamp(0, 1) * size.height;
        i == 0 ? line.moveTo(x, y) : line.lineTo(x, y);
      }
      final Path area = Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(startX, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: 0.18));
      canvas.drawPath(
        line,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
