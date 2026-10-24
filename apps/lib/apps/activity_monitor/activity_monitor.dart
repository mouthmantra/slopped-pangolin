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
import 'dart:isolate';
import 'dart:math' as math;

import 'package:dahlia_apps/apps/activity_monitor/system_stats.dart';
import 'package:dahlia_apps/kit/kit.dart';
import 'package:dahlia_shared/dahlia_shared.dart' show PreferencesService;
import 'package:flutter/services.dart';

final DahliaAppSpec activityMonitorApp = DahliaAppSpec(
  name: "activity_monitor",
  title: "Activity Monitor",
  builder: (context, args) => const ActivityMonitorPage(),
);

const int _historyLength = 60;
const Duration _interval = Duration(milliseconds: 1500);

const String _processesPage = "processes";

const List<RailDestination?> _pages = [
  RailDestination(_processesPage, "Processes", Icons.view_list_rounded),
  null,
  RailDestination("cpu", "CPU", Icons.memory_rounded),
  RailDestination("memory", "Memory", Icons.developer_board_rounded),
  RailDestination("network", "Network", Icons.lan_rounded),
  RailDestination("disk", "Disk", Icons.storage_rounded),
];

const Color _memColor = Color(0xFF7E57C2);
const Color _inColor = Color(0xFF26A69A);
const Color _outColor = Color(0xFFEF5350);

/// Numbers in columns and charts line up digit for digit.
const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

enum _Sort { name, pid, user, cpu, memory }

class ActivityMonitorPage extends StatefulWidget {
  const ActivityMonitorPage({super.key});

  @override
  State<ActivityMonitorPage> createState() => _ActivityMonitorPageState();
}

class _ActivityMonitorPageState extends State<ActivityMonitorPage> {
  Timer? _timer;
  bool _polling = false;
  bool _pollAgain = false;
  String _page = _processesPage;

  List<ProcessInfo> _processes = [];
  final Map<int, int> _previousTicks = {};

  /// Total CPU ticks when [_previousTicks] were read (0: never). The process
  /// list is only read while its page shows, so this can be several samples
  /// back; percentages are then averages since that read.
  int _ticksTotal = 0;
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

  String _cpuModel = "";

  @override
  void initState() {
    super.initState();
    Isolate.run(ProcFs.cpuModel).then((model) {
      if (mounted) setState(() => _cpuModel = model);
    });
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _push(List<double> history, double value) {
    history.add(value);
    if (history.length > _historyLength) history.removeAt(0);
  }

  /// Polls now (or right after the poll that is running), then every
  /// [_interval].
  Future<void> _refresh() async {
    if (_polling) {
      _pollAgain = true;
      return;
    }
    _polling = true;
    _timer?.cancel();
    Snapshot? snapshot;
    try {
      snapshot = await ProcFs.poll(withProcesses: _page == _processesPage);
    } on Object {
      // E.g. /proc unreadable mid-walk: the next poll tries again.
    } finally {
      _polling = false;
    }
    if (!mounted) return;
    if (snapshot != null) _apply(snapshot);
    if (_pollAgain) {
      _pollAgain = false;
      _refresh();
    } else {
      _timer = Timer(_interval, _refresh);
    }
  }

  void _apply(Snapshot snapshot) {
    final SystemSample sample = snapshot.sample;
    final List<ProcessInfo>? processes = snapshot.processes;

    if (processes != null) {
      final int totalDelta = sample.cpu.total - _ticksTotal;
      if (_ticksTotal > 0 && totalDelta > 0) {
        for (final ProcessInfo proc in processes) {
          final int? before = _previousTicks[proc.pid];
          if (before != null) {
            proc.cpuPercent = ((proc.cpuTicks - before) / totalDelta * 100).clamp(0, 100).toDouble();
          }
        }
      }
      _previousTicks
        ..clear()
        ..addEntries(processes.map((pr) => MapEntry(pr.pid, pr.cpuTicks)));
      _ticksTotal = sample.cpu.total;
    }

    final SystemSample? previous = _sample;
    if (previous != null) {
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

    setState(() {
      _sample = sample;
      if (processes != null) _processes = processes;
    });
  }

  void _open(String page) {
    if (page == _page) return;
    setState(() => _page = page);
    // The process list isn't read while hidden: get a fresh one.
    if (page == _processesPage) _refresh();
  }

  List<ProcessInfo> get _visibleProcesses {
    final String me = SystemUtils.user;
    final String q = _filter.trim().toLowerCase();
    final List<ProcessInfo> list = _processes.where((pr) {
      if (_onlyMine && pr.user != me) return false;
      if (q.isEmpty) return true;
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

  Future<void> _runTask() async {
    final bool? started = await showDialog<bool>(
      context: context,
      builder: (context) => const _RunTaskDialog(),
    );
    if (started == true && _page == _processesPage) {
      // Give the program a moment to show up in /proc.
      Timer(const Duration(milliseconds: 300), _refresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final RailDestination page =
        _pages.whereType<RailDestination>().firstWhere((pg) => pg.id == _page);
    // The rail continues the title bar, as in Settings.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _runTask,
      },
      // A scope, not a Focus: when the search field loses focus (a click
      // elsewhere), focus falls back to the nearest scope, which must be
      // below the shortcuts or Ctrl+R stops working.
      child: FocusScope(
        autofocus: true,
        child: ListenableBuilder(
          listenable: Listenable.merge([ZenitBlur.state, PreferencesService.current]),
          builder: (context, _) => DahliaScaffold(
            titlebarColor: DahliaRail.colorOf(context),
            body: Row(
              children: [
                DahliaRail(destinations: _pages, current: _page, onSelected: _open),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(page.id),
                    child: switch (page.id) {
                      _processesPage => _processesPageView(page),
                      "cpu" => _cpuPage(page),
                      "memory" => _memoryPage(page),
                      "network" => _networkPage(page),
                      _ => _diskPage(page),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _processesPageView(RailDestination page) {
    final ThemeData theme = Theme.of(context);
    final List<ProcessInfo> processes = _visibleProcesses;
    final ProcessInfo? selected = processes.where((pr) => pr.pid == _selected).firstOrNull;
    final SystemSample? sample = _sample;
    final SystemRates? rates = _rates;
    final TextStyle muted = TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      fontFeatures: _tabular,
    );

    void sortBy(_Sort sort, bool numeric) => setState(() {
          if (_sort == sort) {
            _descending = !_descending;
          } else {
            _sort = sort;
            _descending = numeric;
          }
        });

    return _PageFrame(
      title: page.title,
      trailing: sample == null
          ? null
          : Text(
              [
                if (rates != null) "CPU ${rates.cpu.toStringAsFixed(0)}%",
                "Memory ${formatBytes(sample.memUsed)} of ${formatBytes(sample.memTotal)}",
                "${_processes.length} processes",
              ].join("  ·  "),
              style: muted,
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SearchField(
                        width: 280,
                        hint: "Search processes",
                        onChanged: (v) => setState(() => _filter = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _TogglePill(
                    label: "My processes",
                    selected: _onlyMine,
                    onChanged: (v) => setState(() => _onlyMine = v),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: "Run Task (Ctrl+R)",
                    waitDuration: const Duration(milliseconds: 400),
                    child: FilledButton.tonalIcon(
                      onPressed: _runTask,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text("Run Task"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: selected == null ? null : () => _signal(selected, ProcessSignal.sigterm),
                    child: const Text("End Process"),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ZenitSection(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _ProcessColumns(
                        name: _HeaderCell("Name", sort: _Sort.name, current: _sort, descending: _descending, onTap: sortBy),
                        pid: _HeaderCell("PID", sort: _Sort.pid, current: _sort, descending: _descending, onTap: sortBy, numeric: true),
                        user: _HeaderCell("User", sort: _Sort.user, current: _sort, descending: _descending, onTap: sortBy),
                        cpu: _HeaderCell("CPU", sort: _Sort.cpu, current: _sort, descending: _descending, onTap: sortBy, numeric: true),
                        memory: _HeaderCell("Memory", sort: _Sort.memory, current: _sort, descending: _descending, onTap: sortBy, numeric: true),
                      ),
                    ),
                    Expanded(
                      child: processes.isEmpty && _sample != null
                          ? const EmptyState(
                              icon: Icons.search_off_rounded,
                              title: "No processes",
                              subtitle: "No processes match your search",
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                              itemCount: processes.length,
                              itemExtent: 32,
                              itemBuilder: (context, index) => _processRow(processes[index], muted),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _processRow(ProcessInfo pr, TextStyle muted) {
    final ThemeData theme = Theme.of(context);
    final bool isSelected = pr.pid == _selected;
    return GestureDetector(
      onSecondaryTapUp: (d) => _processMenu(pr, d.globalPosition),
      child: Material(
        color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selected = pr.pid),
          onDoubleTap: () => _details(pr),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _ProcessColumns(
              name: Text(pr.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              pid: Text("${pr.pid}", textAlign: TextAlign.end, style: muted),
              user: Text(pr.user, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              cpu: Text(
                "${pr.cpuPercent.toStringAsFixed(1)}%",
                textAlign: TextAlign.end,
                style: pr.cpuPercent > 50 ? muted.copyWith(color: theme.colorScheme.error) : muted,
              ),
              memory: Text(formatBytes(pr.rssBytes), textAlign: TextAlign.end, style: muted),
            ),
          ),
        ),
      ),
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

  /// A performance page: its chart, then [children] (details).
  Widget _statsPage(RailDestination page, {required _ChartCard chart, List<Widget> children = const []}) {
    if (_sample == null) return const Center(child: CircularProgressIndicator());
    return _PageFrame(
      title: page.title,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        children: [
          chart,
          const SizedBox(height: 12),
          ...children,
          if (_rates == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text("Collecting data…"),
            ),
        ],
      ),
    );
  }

  Widget _cpuPage(RailDestination page) {
    final ThemeData theme = Theme.of(context);
    final SystemSample? sample = _sample;
    final Color cpuColor = theme.colorScheme.primary;
    return _statsPage(
      page,
      chart: _ChartCard(
        caption: _cpuModel,
        value: "${(_rates?.cpu ?? 0).toStringAsFixed(0)}%",
        series: [_Series("Usage", _cpuHistory, cpuColor)],
        maxValue: 100,
      ),
      children: [
        if (sample != null)
          SettingsGroup(
            children: [
              InfoRow(label: "Processor", value: _cpuModel),
              InfoRow(label: "Cores", value: "${sample.cores.length}"),
              InfoRow(label: "Load average", value: sample.loadAverage),
              InfoRow(label: "Up time", value: formatDuration(sample.uptime)),
            ],
          ),
        if (_coreHistory.isNotEmpty)
          SettingsGroup(
            title: "Cores",
            padding: const EdgeInsets.all(12),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // As many columns as fit at 140 px or more each.
                  const double gap = 8;
                  final int columns = math.max(1, ((constraints.maxWidth + gap) / (140 + gap)).floor());
                  final double width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (int i = 0; i < _coreHistory.length; i++)
                        SizedBox(
                          width: width,
                          height: 52,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ChartPainter([_Series("", _coreHistory[i], cpuColor)], 100, theme, grid: false),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                                child: Row(
                                  children: [
                                    Text("CPU $i", style: theme.textTheme.labelSmall),
                                    const Spacer(),
                                    Text(
                                      "${(_coreHistory[i].lastOrNull ?? 0).toStringAsFixed(0)}%",
                                      style: theme.textTheme.labelSmall?.copyWith(fontFeatures: _tabular),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  Widget _memoryPage(RailDestination page) {
    final SystemSample? sample = _sample;
    return _statsPage(
      page,
      chart: _ChartCard(
        caption: sample == null ? "" : "${formatBytes(sample.memUsed)} of ${formatBytes(sample.memTotal)} used",
        value: sample == null ? "" : "${(sample.memUsed / math.max(1, sample.memTotal) * 100).toStringAsFixed(0)}%",
        series: [
          _Series("Memory", _memHistory, _memColor),
          if (sample != null && sample.swapTotal > 0)
            _Series("Swap", _swapHistory, _memColor.withValues(alpha: 0.45)),
        ],
        maxValue: 100,
      ),
      children: [
        if (sample != null)
          SettingsGroup(
            children: [
              InfoRow(label: "In use", value: formatBytes(sample.memUsed)),
              InfoRow(label: "Available", value: formatBytes(sample.memAvailable)),
              InfoRow(label: "Total", value: formatBytes(sample.memTotal)),
              InfoRow(
                label: "Swap",
                value: sample.swapTotal > 0
                    ? "${formatBytes(sample.swapUsed)} of ${formatBytes(sample.swapTotal)}"
                    : "None",
              ),
            ],
          ),
      ],
    );
  }

  Widget _networkPage(RailDestination page) {
    final SystemSample? sample = _sample;
    final SystemRates? rates = _rates;
    return _statsPage(
      page,
      chart: _ChartCard(
        caption: "All interfaces except loopback",
        value: "↓ ${formatBytes(rates?.netRxPerSec ?? 0)}/s   ↑ ${formatBytes(rates?.netTxPerSec ?? 0)}/s",
        series: [_Series("Received", _rxHistory, _inColor), _Series("Sent", _txHistory, _outColor)],
      ),
      children: [
        if (sample != null)
          SettingsGroup(
            children: [
              InfoRow(label: "Receiving", value: "${formatBytes(rates?.netRxPerSec ?? 0)}/s"),
              InfoRow(label: "Sending", value: "${formatBytes(rates?.netTxPerSec ?? 0)}/s"),
              InfoRow(label: "Received since boot", value: formatBytes(sample.netRx)),
              InfoRow(label: "Sent since boot", value: formatBytes(sample.netTx)),
            ],
          ),
      ],
    );
  }

  Widget _diskPage(RailDestination page) {
    final SystemSample? sample = _sample;
    final SystemRates? rates = _rates;
    return _statsPage(
      page,
      chart: _ChartCard(
        caption: "All drives",
        value: "R ${formatBytes(rates?.diskReadPerSec ?? 0)}/s   W ${formatBytes(rates?.diskWritePerSec ?? 0)}/s",
        series: [_Series("Read", _readHistory, _inColor), _Series("Write", _writeHistory, _outColor)],
      ),
      children: [
        if (sample != null)
          SettingsGroup(
            children: [
              InfoRow(label: "Reading", value: "${formatBytes(rates?.diskReadPerSec ?? 0)}/s"),
              InfoRow(label: "Writing", value: "${formatBytes(rates?.diskWritePerSec ?? 0)}/s"),
              InfoRow(label: "Read since boot", value: formatBytes(sample.diskRead)),
              InfoRow(label: "Written since boot", value: formatBytes(sample.diskWrite)),
            ],
          ),
      ],
    );
  }
}

/// Page title (lined up with the content, as in Settings) above the page.
class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.title, required this.child, this.trailing});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// The process table's columns; the header and every row use it, so they
/// line up.
class _ProcessColumns extends StatelessWidget {
  const _ProcessColumns({
    required this.name,
    required this.pid,
    required this.user,
    required this.cpu,
    required this.memory,
  });

  final Widget name;
  final Widget pid;
  final Widget user;
  final Widget cpu;
  final Widget memory;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 4, child: name),
        const SizedBox(width: 16),
        SizedBox(width: 72, child: pid),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: user),
        const SizedBox(width: 16),
        SizedBox(width: 72, child: cpu),
        const SizedBox(width: 16),
        SizedBox(width: 96, child: memory),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(
    this.label, {
    required this.sort,
    required this.current,
    required this.descending,
    required this.onTap,
    this.numeric = false,
  });

  final String label;
  final _Sort sort;
  final _Sort current;
  final bool descending;
  final void Function(_Sort sort, bool numeric) onTap;

  /// Right-aligned like its values; the sort arrow goes before the label so
  /// the label's end stays over the numbers' end.
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = current == sort;
    final Color color = theme.colorScheme.onSurface.withValues(alpha: active ? 0.9 : 0.6);
    final Widget arrow = Icon(
      descending ? Icons.arrow_drop_down_rounded : Icons.arrow_drop_up_rounded,
      size: 18,
      color: color,
    );
    final Widget text = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: active ? FontWeight.w600 : null,
        ),
      ),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onTap(sort, numeric),
      child: SizedBox(
        height: 32,
        child: Row(
          mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (active && numeric) arrow,
            text,
            if (active && !numeric) arrow,
          ],
        ),
      ),
    );
  }
}

/// On/off filter drawn like [SearchField] (filled pill, no outline).
class _TogglePill extends StatelessWidget {
  const _TogglePill({required this.label, required this.selected, required this.onChanged});

  final String label;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary.withValues(alpha: 0.2) : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onChanged(!selected),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_rounded : Icons.person_outline_rounded,
                  size: 18,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Starts a program or shell command (Ctrl+R), on its own or in Terminal.
class _RunTaskDialog extends StatefulWidget {
  const _RunTaskDialog();

  /// Kept for the next time the dialog opens.
  static bool _inTerminal = false;

  @override
  State<_RunTaskDialog> createState() => _RunTaskDialogState();
}

class _RunTaskDialogState extends State<_RunTaskDialog> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _field = FocusNode();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final String command = _controller.text.trim();
    if (command.isEmpty) return;
    final bool inTerminal = _RunTaskDialog._inTerminal;
    final String shell = Platform.environment["SHELL"] ?? "/bin/sh";

    // A detached program's errors go nowhere, so check that a plain program
    // name exists. Anything else (paths, VAR=value prefixes) is left to the
    // shell; in Terminal its errors show there.
    final String program = command.split(RegExp(r"\s+")).first;
    if (!inTerminal && !program.contains("/") && !program.contains("=") && SystemUtils.which(program) == null) {
      setState(() => _error = "Couldn't find “$program”");
      return;
    }

    try {
      if (inTerminal) {
        await SystemUtils.launchApp("terminal", ["-e", shell, "-c", command]);
      } else {
        await Process.start(
          shell,
          ["-c", command],
          workingDirectory: SystemUtils.home,
          mode: ProcessStartMode.detached,
        );
      }
    } on ProcessException catch (e) {
      setState(() => _error = "Couldn't start it: ${e.message}");
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text("Run Task"),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Type the name of a program or a command.",
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              focusNode: _field,
              autofocus: true,
              style: const TextStyle(fontFamily: "monospace"),
              decoration: InputDecoration(hintText: "firefox", errorText: _error),
              onChanged: (_) => setState(() => _error = null),
              // Not onSubmitted: Enter would unfocus the field, and after an
              // error the next try couldn't be typed.
              onEditingComplete: _run,
            ),
            const SizedBox(height: 12),
            // On a section fill, as in Settings: the switch's off track is
            // the dialog's own color.
            DecoratedBox(
              decoration: BoxDecoration(
                color: sectionColor(theme),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Run in Terminal"),
                          Text(
                            "Shows the command's output",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ZenitSwitch(
                      value: _RunTaskDialog._inTerminal,
                      onChanged: (v) {
                        setState(() => _RunTaskDialog._inTerminal = v);
                        // Back to the command, so Enter still runs it.
                        _field.requestFocus();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _run,
            child: const Text("Run"),
          ),
        ),
      ],
    );
  }
}

class _Series {
  const _Series(this.label, this.values, this.color);
  final String label;
  final List<double> values;
  final Color color;
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.caption,
    required this.value,
    required this.series,
    this.maxValue,
  });

  final String caption;
  final String value;
  final List<_Series> series;
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double max = maxValue ??
        math.max(
          1024.0,
          series.expand((s) => s.values).fold<double>(0, math.max) * 1.2,
        );
    return ZenitSection(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.titleLarge?.copyWith(fontFeatures: _tabular),
                      ),
                      if (caption.isNotEmpty)
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                for (final _Series s in series) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(s.label, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: CustomPaint(painter: _ChartPainter(series, max, theme)),
            ),
          ],
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
    final RRect bounds = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
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
