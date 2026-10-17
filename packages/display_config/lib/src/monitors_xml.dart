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
