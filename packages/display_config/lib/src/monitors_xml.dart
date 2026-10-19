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

import 'package:display_config/src/profiles.dart';

/// A connected monitor, as the compositor describes it.
typedef ConnectedMonitor = ({
  String id,
  String name,
  String model,
  String serial,
});

/// A monitor as GNOME identifies it.
class MonitorSpec {
  const MonitorSpec({
    required this.connector,
    required this.vendor,
    required this.product,
    required this.serial,
  });

  final String connector;

  /// The EDID's three letter manufacturer code (e.g. "GSM").
  final String vendor;
  final String product;
  final String serial;

  @override
  String toString() => "$connector ($vendor $product $serial)";
}

class MonitorsXmlMonitor {
  const MonitorsXmlMonitor({
    required this.spec,
    required this.width,
    required this.height,
    required this.rate,
  });

  final MonitorSpec spec;
  final int width;
  final int height;

  /// Hz.
  final double rate;
}

/// Monitors showing the same part of the desktop (more than one when
/// mirrored).
class MonitorsXmlLogicalMonitor {
  const MonitorsXmlLogicalMonitor({
    required this.x,
    required this.y,
    required this.scale,
    required this.transform,
    required this.monitors,
  });

  final int x;
  final int y;
  final double scale;

  /// wl_output.transform.
  final int transform;
  final List<MonitorsXmlMonitor> monitors;
}

/// The setup GNOME saved for one set of monitors.
class MonitorsXmlConfiguration {
  const MonitorsXmlConfiguration({
    required this.physicalLayout,
    required this.logicalMonitors,
    required this.disabled,
  });

  /// Positions in physical pixels rather than logical ones.
  final bool physicalLayout;
  final List<MonitorsXmlLogicalMonitor> logicalMonitors;
  final List<MonitorSpec> disabled;

  List<MonitorSpec> get specs => [
        for (final MonitorsXmlLogicalMonitor l in logicalMonitors)
          for (final MonitorsXmlMonitor m in l.monitors) m.spec,
        ...disabled,
      ];
}

/// GNOME's display configuration (mutter's monitors.xml, version 2). GDM
/// uses `/etc/xdg/monitors.xml` for its login screen (an administrator
/// copies their `~/.config/monitors.xml` there); Pangolin's login screen
/// does the same.
abstract final class MonitorsXml {
  /// `monitors.xml` in the system configuration directories
  /// ($XDG_CONFIG_DIRS, /etc/xdg by default), first found first.
  static List<String> get searchPaths {
    final String dirs = Platform.environment["XDG_CONFIG_DIRS"] ?? "";
    return [
      for (final String dir in dirs.isEmpty ? ["/etc/xdg"] : dirs.split(":"))
        if (dir.isNotEmpty) "$dir/monitors.xml",
      if (dirs.isNotEmpty && !dirs.split(":").contains("/etc/xdg"))
        "/etc/xdg/monitors.xml",
    ];
  }

  /// The configurations of [path] (or of the first file of [searchPaths]),
  /// none when there's no readable file.
  static List<MonitorsXmlConfiguration> load([String? path]) {
    for (final String candidate in path != null ? [path] : searchPaths) {
      try {
        return parse(File(candidate).readAsStringSync());
      } on FileSystemException {
        continue;
      }
    }
    return const [];
  }

  static List<MonitorsXmlConfiguration> parse(String text) {
    final _Element? root = _Element.parse(text);
    if (root == null || root.name != "monitors") return const [];
    // Version 1 (before logical monitors) isn't supported.
    if (root.attributes["version"] != "2") return const [];
    return [
      for (final _Element c in root.children("configuration"))
        if (_configuration(c) case final MonitorsXmlConfiguration config)
          config,
    ];
  }

  static MonitorsXmlConfiguration? _configuration(_Element c) {
    final List<MonitorsXmlLogicalMonitor> logical = [];
    for (final _Element l in c.children("logicalmonitor")) {
      final List<MonitorsXmlMonitor> monitors = [];
      for (final _Element m in l.children("monitor")) {
        final MonitorSpec? spec = _spec(m.child("monitorspec"));
        final _Element? mode = m.child("mode");
        if (spec == null || mode == null) continue;
        monitors.add(
          MonitorsXmlMonitor(
            spec: spec,
            width: int.tryParse(mode.text("width")) ?? 0,
            height: int.tryParse(mode.text("height")) ?? 0,
            rate: double.tryParse(mode.text("rate")) ?? 0,
          ),
        );
      }
      if (monitors.isEmpty) continue;
      final _Element? transform = l.child("transform");
      int rotation = switch (transform?.text("rotation")) {
        "left" => 1,
        "upside_down" => 2,
        "right" => 3,
        _ => 0,
      };
      if (transform?.text("flipped") == "yes") rotation += 4;
      logical.add(
        MonitorsXmlLogicalMonitor(
          x: int.tryParse(l.text("x")) ?? 0,
          y: int.tryParse(l.text("y")) ?? 0,
          scale: double.tryParse(l.text("scale")) ?? 1,
          transform: rotation,
          monitors: monitors,
        ),
      );
    }
    final List<MonitorSpec> disabled = [
      for (final _Element d in c.children("disabled"))
        for (final _Element s in d.children("monitorspec"))
          if (_spec(s) case final MonitorSpec spec) spec,
    ];
    if (logical.isEmpty) return null;
    return MonitorsXmlConfiguration(
      physicalLayout: c.text("layoutmode") == "physical",
      logicalMonitors: logical,
      disabled: disabled,
    );
  }

  static MonitorSpec? _spec(_Element? e) {
    if (e == null) return null;
    return MonitorSpec(
      connector: e.text("connector"),
      vendor: e.text("vendor"),
      product: e.text("product"),
      serial: e.text("serial"),
    );
  }

  /// The settings of the configuration made for exactly the connected
  /// [heads] (each monitor of it found among them, and no other), by head
  /// id; null when there's none.
  ///
  /// Monitors are matched like GNOME does, by connector first, otherwise
  /// by product and serial number (the same monitor on another port): the
  /// connector names (HDMI-1 for wlroots' HDMI-A-1) and the manufacturer
  /// (a code for GNOME, a name for wlroots) don't always agree.
  static Map<String, OutputSettings>? resolve(
    List<MonitorsXmlConfiguration> configurations,
    List<ConnectedMonitor> heads,
  ) {
    MonitorsXmlConfiguration? best;
    List<ConnectedMonitor>? bestAssignment;
    int bestScore = -1;
    for (final MonitorsXmlConfiguration config in configurations) {
      final List<MonitorSpec> specs = config.specs;
      if (specs.length != heads.length) continue;
      final (List<ConnectedMonitor>, int)? assignment = _assign(specs, heads);
      if (assignment == null || assignment.$2 <= bestScore) continue;
      best = config;
      bestAssignment = assignment.$1;
      bestScore = assignment.$2;
    }
    if (best == null || bestAssignment == null) return null;

    final Map<String, OutputSettings> settings = {};
    int index = 0;
    for (final MonitorsXmlLogicalMonitor l in best.logicalMonitors) {
      for (final MonitorsXmlMonitor m in l.monitors) {
        final ConnectedMonitor head = bestAssignment[index++];
        // Physical layouts place monitors in pixels: wlroots lays out in
        // logical ones.
        final double divisor = best.physicalLayout ? l.scale : 1;
        settings[head.id] = OutputSettings(
          id: head.id,
          enabled: true,
          width: m.width,
          height: m.height,
          refresh: (m.rate * 1000).round(),
          scale: l.scale,
          transform: l.transform,
          x: (l.x / divisor).round(),
          y: (l.y / divisor).round(),
        );
      }
    }
    for (final MonitorSpec _ in best.disabled) {
      final ConnectedMonitor head = bestAssignment[index++];
      settings[head.id] = OutputSettings(id: head.id, enabled: false);
    }
    return settings;
  }

  /// Gives each spec a distinct head (the best scoring way), or null.
  static (List<ConnectedMonitor>, int)? _assign(
    List<MonitorSpec> specs,
    List<ConnectedMonitor> heads,
  ) {
    List<ConnectedMonitor>? best;
    int bestScore = -1;
    final List<ConnectedMonitor> chosen = [];
    final Set<ConnectedMonitor> used = {};
    void search(int i, int score) {
      if (i == specs.length) {
        if (score > bestScore) {
          bestScore = score;
          best = List.of(chosen);
        }
        return;
      }
      for (final ConnectedMonitor head in heads) {
        if (used.contains(head)) continue;
        final int s = _score(specs[i], head);
        if (s < 0) continue;
        used.add(head);
        chosen.add(head);
        search(i + 1, score + s);
        chosen.removeLast();
        used.remove(head);
      }
    }

    search(0, 0);
    final List<ConnectedMonitor>? result = best;
    return result == null ? null : (result, bestScore);
  }

  /// How well [spec] describes [head]: -1 when it doesn't.
  static int _score(MonitorSpec spec, ConnectedMonitor head) {
    bool known(String s) =>
        s.isNotEmpty &&
        s.toLowerCase() != "unknown" &&
        !RegExp(r"^0x0+$").hasMatch(s.toLowerCase());
    bool same(String a, String b) => a.toLowerCase() == b.toLowerCase();

    final bool productKnown = known(spec.product) && known(head.model);
    final bool serialKnown = known(spec.serial) && known(head.serial);
    if (productKnown && !same(spec.product, head.model)) return -1;
    if (serialKnown && !same(spec.serial, head.serial)) return -1;
    final bool connector = _connector(spec.connector) == _connector(head.name);
    final bool identified = productKnown || serialKnown;
    if (!connector && !identified) return -1;
    return (connector ? 4 : 0) + (productKnown ? 2 : 0) + (serialKnown ? 1 : 0);
  }

  /// wlroots names HDMI ports HDMI-A-1 where GNOME says HDMI-1.
  static String _connector(String name) =>
      name.replaceFirst(RegExp(r"^HDMI-A-"), "HDMI-");

  /// The user's monitors.xml (`$XDG_CONFIG_HOME/monitors.xml`).
  static String get userPath {
    final Map<String, String> env = Platform.environment;
    final String config = env["XDG_CONFIG_HOME"]?.isNotEmpty == true
        ? env["XDG_CONFIG_HOME"]!
        : "${env["HOME"] ?? "."}/.config";
    return "$config/monitors.xml";
  }

  /// The monitor on [connector] as GNOME identifies it: vendor code, product
  /// and serial read from its EDID the way mutter reads them, else what the
  /// compositor says ([make], [model], [serial]).
  static MonitorSpec specOf({
    required String connector,
    required String make,
    required String model,
    required String serial,
  }) {
    final ({String vendor, String product, String serial})? edid =
        _edidOf(connector);
    return MonitorSpec(
      connector: _connector(connector),
      vendor: edid?.vendor ?? make,
      product: edid?.product ?? model,
      serial: edid?.serial ?? serial,
    );
  }

  static ({String vendor, String product, String serial})? _edidOf(
    String connector,
  ) {
    try {
      for (final FileSystemEntity e in Directory("/sys/class/drm").listSync()) {
        final String name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
        final RegExpMatch? m = RegExp(r"^card\d+-(.+)$").firstMatch(name);
        if (m == null || m.group(1) != connector) continue;
        return parseEdid(File("${e.path}/edid").readAsBytesSync());
      }
    } on FileSystemException {
      // No EDID to read.
    }
    return null;
  }

  /// Vendor code, product and serial of an EDID as mutter derives them:
  /// the product and serial descriptors, else the product code and serial
  /// number in hex ("0x40a3", "0x00000000"). Null when it isn't an EDID.
  static ({String vendor, String product, String serial})? parseEdid(
    List<int> b,
  ) {
    const List<int> header = [0, 255, 255, 255, 255, 255, 255, 0];
    if (b.length < 128) return null;
    for (int i = 0; i < header.length; i++) {
      if (b[i] != header[i]) return null;
    }
    final int v = b[8] << 8 | b[9];
    String letter(int c) => String.fromCharCode(64 + (c & 31));
    final String vendor = letter(v >> 10) + letter(v >> 5) + letter(v);
    String? product;
    String? serial;
    for (int o = 54; o <= 108; o += 18) {
      if (b[o] != 0 || b[o + 1] != 0 || b[o + 2] != 0) continue;
      final String text = String.fromCharCodes(b.sublist(o + 5, o + 18))
          .split("\n")
          .first
          .trim();
      if (text.isEmpty) continue;
      if (b[o + 3] == 0xfc) product = text;
      if (b[o + 3] == 0xff) serial = text;
    }
    String hex(int value, int digits) =>
        "0x${value.toRadixString(16).padLeft(digits, "0")}";
    return (
      vendor: vendor,
      product: product ?? hex(b[10] | b[11] << 8, 4),
      serial: serial ?? hex(b[12] | b[13] << 8 | b[14] << 16 | b[15] << 24, 8),
    );
  }

  /// Saves [outputs] (each monitor and how it's set up) as the
  /// configuration for these monitors in the monitors.xml at [path] (the
  /// user's by default), in place of the one it had for them; the others
  /// stay as they are. A file that isn't a version 2 monitors.xml is left
  /// alone. Returns whether it was written.
  static bool save(
    List<(MonitorSpec, OutputSettings)> outputs, {
    String? path,
  }) {
    // GNOME needs a monitor on, and the mode of each.
    final Iterable<OutputSettings> on = [
      for (final (_, OutputSettings o) in outputs)
        if (o.enabled) o,
    ];
    if (on.isEmpty || on.any((o) => o.width <= 0 || o.refresh <= 0)) {
      return false;
    }
    final File file = File(path ?? userPath);
    String old = "";
    try {
      old = file.readAsStringSync();
    } on FileSystemException {
      // A new file.
    }
    final _Element? root = old.trim().isEmpty ? null : _Element.parse(old);
    if (old.trim().isNotEmpty &&
        (root?.name != "monitors" || root?.attributes["version"] != "2")) {
      return false;
    }

    String key(MonitorSpec s) =>
        [s.connector, s.vendor, s.product, s.serial].join("\u0000");
    final Set<String> mine = {for (final (MonitorSpec s, _) in outputs) key(s)};
    final StringBuffer out = StringBuffer('<monitors version="2">\n');
    for (final RegExpMatch m in RegExp(r"<configuration>[\s\S]*?</configuration>")
        .allMatches(old)) {
      final _Element? c = _Element.parse(m.group(0)!);
      final MonitorsXmlConfiguration? config =
          c == null ? null : _configuration(c);
      final Set<String>? theirs =
          config == null ? null : {for (final s in config.specs) key(s)};
      final bool same = theirs != null &&
          theirs.length == mine.length &&
          theirs.containsAll(mine);
      if (!same) out.write("  ${m.group(0)}\n");
    }
    out.write(_configurationXml(outputs));
    out.write("</monitors>\n");

    file.parent.createSync(recursive: true);
    // Written aside and renamed: a crash never leaves half a file.
    final File temp = File("${file.path}.tmp");
    temp.writeAsStringSync(out.toString(), flush: true);
    temp.renameSync(file.path);
    return true;
  }

  /// One <configuration>: monitors at the same place, scale and transform
  /// are mirrored (one logical monitor); the built-in panel, else the
  /// top-left one, is the primary.
  static String _configurationXml(List<(MonitorSpec, OutputSettings)> outputs) {
    final List<List<(MonitorSpec, OutputSettings)>> logical = [];
    for (final (MonitorSpec, OutputSettings) o in outputs) {
      if (!o.$2.enabled) continue;
      final List<(MonitorSpec, OutputSettings)>? group = logical
          .where((g) =>
              g.first.$2.x == o.$2.x &&
              g.first.$2.y == o.$2.y &&
              g.first.$2.scale == o.$2.scale &&
              g.first.$2.transform == o.$2.transform)
          .firstOrNull;
      if (group != null) {
        group.add(o);
      } else {
        logical.add([o]);
      }
    }
    logical.sort((a, b) => a.first.$2.x != b.first.$2.x
        ? a.first.$2.x.compareTo(b.first.$2.x)
        : a.first.$2.y.compareTo(b.first.$2.y));
    final int primary = logical.indexWhere(
      (g) => g.any((o) => RegExp(r"^(eDP|LVDS|DSI)-").hasMatch(o.$1.connector)),
    );

    String spec(MonitorSpec s, String indent) => "$indent<monitorspec>\n"
        "$indent  <connector>${_escape(s.connector)}</connector>\n"
        "$indent  <vendor>${_escape(s.vendor)}</vendor>\n"
        "$indent  <product>${_escape(s.product)}</product>\n"
        "$indent  <serial>${_escape(s.serial)}</serial>\n"
        "$indent</monitorspec>\n";

    final StringBuffer x = StringBuffer("  <configuration>\n");
    x.write("    <layoutmode>logical</layoutmode>\n");
    for (int i = 0; i < logical.length; i++) {
      final OutputSettings first = logical[i].first.$2;
      x.write("    <logicalmonitor>\n");
      x.write("      <x>${first.x}</x>\n");
      x.write("      <y>${first.y}</y>\n");
      x.write("      <scale>${first.scale}</scale>\n");
      if (i == (primary >= 0 ? primary : 0)) {
        x.write("      <primary>yes</primary>\n");
      }
      if (first.transform != 0) {
        const List<String> rotations = ["normal", "left", "upside_down", "right"];
        x.write("      <transform>\n");
        x.write("        <rotation>${rotations[first.transform % 4]}</rotation>\n");
        x.write("        <flipped>${first.transform >= 4 ? "yes" : "no"}</flipped>\n");
        x.write("      </transform>\n");
      }
      for (final (MonitorSpec s, OutputSettings o) in logical[i]) {
        x.write("      <monitor>\n");
        x.write(spec(s, "        "));
        x.write("        <mode>\n");
        x.write("          <width>${o.width}</width>\n");
        x.write("          <height>${o.height}</height>\n");
        x.write("          <rate>${(o.refresh / 1000).toStringAsFixed(3)}</rate>\n");
        x.write("        </mode>\n");
        x.write("      </monitor>\n");
      }
      x.write("    </logicalmonitor>\n");
    }
    final List<MonitorSpec> disabled = [
      for (final (MonitorSpec s, OutputSettings o) in outputs)
        if (!o.enabled) s,
    ];
    if (disabled.isNotEmpty) {
      x.write("    <disabled>\n");
      for (final MonitorSpec s in disabled) {
        x.write(spec(s, "      "));
      }
      x.write("    </disabled>\n");
    }
    x.write("  </configuration>\n");
    return x.toString();
  }

  static String _escape(String s) => s
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;");
}

/// Just enough XML for monitors.xml: elements, attributes and text.
class _Element {
  _Element(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<_Element> elements = [];
  final StringBuffer _text = StringBuffer();

  Iterable<_Element> children(String name) =>
      elements.where((e) => e.name == name);

  _Element? child(String name) {
    for (final _Element e in elements) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// The text of the child [name], trimmed ("" without one).
  String text(String name) => child(name)?._text.toString().trim() ?? "";

  static _Element? parse(String source) {
    final RegExp token = RegExp(
      r"<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|<(/?)([A-Za-z_][\w.:-]*)([^>]*?)(/?)>|([^<]+)",
    );
    final RegExp attribute = RegExp(r"""([A-Za-z_][\w.:-]*)\s*=\s*("([^"]*)"|'([^']*)')""");
    final List<_Element> stack = [];
    _Element? root;
    for (final RegExpMatch m in token.allMatches(source)) {
      if (m.group(1) != null) {
        if (stack.isNotEmpty) stack.last._text.write(m.group(1));
      } else if (m.group(3) != null) {
        final String name = m.group(3)!;
        if (m.group(2) == "/") {
          if (stack.isNotEmpty && stack.last.name == name) stack.removeLast();
          continue;
        }
        final _Element e = _Element(name, {
          for (final RegExpMatch a in attribute.allMatches(m.group(4) ?? ""))
            a.group(1)!: _unescape(a.group(3) ?? a.group(4) ?? ""),
        });
        if (stack.isEmpty) {
          root ??= e;
        } else {
          stack.last.elements.add(e);
        }
        if (m.group(5) != "/") stack.add(e);
      } else if (m.group(6) != null && stack.isNotEmpty) {
        stack.last._text.write(_unescape(m.group(6)!));
      }
    }
    return root;
  }

  static String _unescape(String s) => s
      .replaceAll("&lt;", "<")
      .replaceAll("&gt;", ">")
      .replaceAll("&quot;", '"')
      .replaceAll("&apos;", "'")
      .replaceAll("&amp;", "&");
}
