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

import 'dart:io';

/// A process as read from /proc/<pid>.
class ProcessInfo {
  ProcessInfo({
    required this.pid,
    required this.name,
    required this.state,
    required this.uid,
    required this.threads,
    required this.rssBytes,
    required this.cpuTicks,
    required this.commandLine,
  });

  final int pid;
  final String name;
  final String state;
  final int uid;
  final int threads;
  final int rssBytes;
  final int cpuTicks;
  final String commandLine;

  /// Share of total CPU time used since the previous sample (0-100).
  double cpuPercent = 0;
  String user = "";

  String get stateLabel => switch (state) {
        "R" => "Running",
        "S" => "Sleeping",
        "D" => "Waiting",
        "Z" => "Zombie",
        "T" || "t" => "Stopped",
        "I" => "Idle",
        _ => state,
      };
}

class CpuTimes {
  const CpuTimes(this.busy, this.total);
  final int busy;
  final int total;
}

/// One sample of system-wide statistics.
class SystemSample {
  SystemSample({
    required this.cpu,
    required this.cores,
    required this.memTotal,
    required this.memAvailable,
    required this.swapTotal,
    required this.swapFree,
    required this.netRx,
    required this.netTx,
    required this.diskRead,
    required this.diskWrite,
    required this.time,
  });

  final CpuTimes cpu;
  final List<CpuTimes> cores;
  final int memTotal;
  final int memAvailable;
  final int swapTotal;
  final int swapFree;
  final int netRx;
  final int netTx;
  final int diskRead;
  final int diskWrite;
  final DateTime time;

  int get memUsed => memTotal - memAvailable;
  int get swapUsed => swapTotal - swapFree;
}

/// Rates derived from two consecutive samples.
class SystemRates {
  const SystemRates({
    required this.cpu,
    required this.cores,
    required this.netRxPerSec,
    required this.netTxPerSec,
    required this.diskReadPerSec,
    required this.diskWritePerSec,
  });

  final double cpu;
  final List<double> cores;
  final double netRxPerSec;
  final double netTxPerSec;
  final double diskReadPerSec;
  final double diskWritePerSec;
}

abstract final class ProcFs {
  static final Map<int, String> _users = _readUsers();

  static Map<int, String> _readUsers() {
    final Map<int, String> users = {};
    try {
      for (final String line in File("/etc/passwd").readAsLinesSync()) {
        final List<String> f = line.split(":");
        if (f.length > 2) users[int.tryParse(f[2]) ?? -1] = f[0];
      }
    } on FileSystemException {
      // No passwd: show numeric ids.
    }
    return users;
  }

  static String userName(int uid) => _users[uid] ?? uid.toString();

  static String? _read(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  static List<ProcessInfo> processes() {
    final List<ProcessInfo> list = [];
    final Directory proc = Directory("/proc");
    for (final FileSystemEntity e in proc.listSync(followLinks: false)) {
      final int? pid = int.tryParse(e.path.substring(6));
      if (pid == null) continue;
      final String? stat = _read("/proc/$pid/stat");
      final String? status = _read("/proc/$pid/status");
      if (stat == null || status == null) continue;

      // The command name is in parentheses and may contain spaces.
      final int open = stat.indexOf("(");
      final int close = stat.lastIndexOf(")");
      if (open < 0 || close < 0) continue;
      final String comm = stat.substring(open + 1, close);
      final List<String> fields = stat.substring(close + 2).split(" ");
      if (fields.length < 20) continue;

      int field(String key) {
        final Match? m = RegExp("^$key:\\s+(\\d+)", multiLine: true).firstMatch(status);
        return m == null ? 0 : int.parse(m.group(1)!);
      }

      String cmdline = (_read("/proc/$pid/cmdline") ?? "").replaceAll("\u0000", " ").trim();
      if (cmdline.isEmpty) cmdline = "[$comm]";

      final ProcessInfo info = ProcessInfo(
        pid: pid,
        name: comm,
        state: fields[0],
        uid: field("Uid"),
        threads: field("Threads"),
        rssBytes: field("VmRSS") * 1024,
        cpuTicks: (int.tryParse(fields[11]) ?? 0) + (int.tryParse(fields[12]) ?? 0),
        commandLine: cmdline,
      );
      info.user = userName(info.uid);
      list.add(info);
    }
    return list;
  }

  static SystemSample sample() {
    final String stat = _read("/proc/stat") ?? "";
    CpuTimes parse(String line) {
      final List<int> v = line.split(RegExp(r"\s+")).skip(1).map((s) => int.tryParse(s) ?? 0).toList();
      final int idle = v.length > 4 ? v[3] + v[4] : 0;
      final int total = v.fold(0, (a, b) => a + b);
      return CpuTimes(total - idle, total);
    }

    CpuTimes cpu = const CpuTimes(0, 0);
    final List<CpuTimes> cores = [];
    for (final String line in stat.split("\n")) {
      if (line.startsWith("cpu ")) {
        cpu = parse(line);
      } else if (RegExp(r"^cpu\d+ ").hasMatch(line)) {
        cores.add(parse(line));
      }
    }

    final String meminfo = _read("/proc/meminfo") ?? "";
    int mem(String key) {
      final Match? m = RegExp("^$key:\\s+(\\d+)", multiLine: true).firstMatch(meminfo);
      return m == null ? 0 : int.parse(m.group(1)!) * 1024;
    }

    int rx = 0;
    int tx = 0;
    for (final String line in (_read("/proc/net/dev") ?? "").split("\n").skip(2)) {
      final List<String> parts = line.trim().split(RegExp(r"[:\s]+"));
      if (parts.length < 10 || parts[0] == "lo") continue;
      rx += int.tryParse(parts[1]) ?? 0;
      tx += int.tryParse(parts[9]) ?? 0;
    }

    int read = 0;
    int write = 0;
    for (final String line in (_read("/proc/diskstats") ?? "").split("\n")) {
      final List<String> f = line.trim().split(RegExp(r"\s+"));
      if (f.length < 10) continue;
      final String name = f[2];
      // Whole disks only, partitions would be counted twice.
      if (!RegExp(r"^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme\d+n\d+|mmcblk\d+)$").hasMatch(name)) {
        continue;
      }
      read += (int.tryParse(f[5]) ?? 0) * 512;
      write += (int.tryParse(f[9]) ?? 0) * 512;
    }

    return SystemSample(
      cpu: cpu,
      cores: cores,
      memTotal: mem("MemTotal"),
      memAvailable: mem("MemAvailable"),
      swapTotal: mem("SwapTotal"),
      swapFree: mem("SwapFree"),
      netRx: rx,
      netTx: tx,
      diskRead: read,
      diskWrite: write,
      time: DateTime.now(),
    );
  }

  static SystemRates rates(SystemSample previous, SystemSample current) {
    double usage(CpuTimes a, CpuTimes b) {
      final int total = b.total - a.total;
      return total <= 0 ? 0 : ((b.busy - a.busy) / total * 100).clamp(0, 100).toDouble();
    }

    final double seconds =
        current.time.difference(previous.time).inMilliseconds / 1000.0;
    double perSec(int a, int b) => seconds <= 0 ? 0 : (b - a).clamp(0, 1 << 62) / seconds;

    return SystemRates(
      cpu: usage(previous.cpu, current.cpu),
      cores: [
        for (int i = 0; i < current.cores.length && i < previous.cores.length; i++)
          usage(previous.cores[i], current.cores[i]),
      ],
      netRxPerSec: perSec(previous.netRx, current.netRx),
      netTxPerSec: perSec(previous.netTx, current.netTx),
      diskReadPerSec: perSec(previous.diskRead, current.diskRead),
      diskWritePerSec: perSec(previous.diskWrite, current.diskWrite),
    );
  }

  static String cpuModel() {
    final String info = _read("/proc/cpuinfo") ?? "";
    final Match? m = RegExp(r"^model name\s*:\s*(.+)$", multiLine: true).firstMatch(info);
    return m?.group(1)?.trim() ?? "Unknown processor";
  }

  static Duration uptime() {
    final String raw = _read("/proc/uptime") ?? "0";
    return Duration(seconds: double.tryParse(raw.split(" ").first)?.round() ?? 0);
  }

  static String loadAverage() =>
      (_read("/proc/loadavg") ?? "").split(" ").take(3).join("  ");
}
