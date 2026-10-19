// Self-check of MonitorsXml's EDID reading and saving:
//   dart run test/monitors_xml_check.dart

import 'dart:io';

import 'package:display_config/display_config.dart';

void check(bool ok, String what) {
  if (!ok) throw StateError("failed: $what");
}

List<int> edid({String? name, String? serial}) {
  final List<int> b = List.filled(128, 0);
  b.setAll(0, [0, 255, 255, 255, 255, 255, 255, 0]);
  // "GSM": G=7, S=19, M=13.
  final int v = 7 << 10 | 19 << 5 | 13;
  b[8] = v >> 8;
  b[9] = v & 255;
  b[10] = 0xa3;
  b[11] = 0x40;
  void text(int o, int tag, String s) {
    b[o + 3] = tag;
    final List<int> t = "$s\n".codeUnits;
    for (int i = 0; i < 13; i++) {
      b[o + 5 + i] = i < t.length ? t[i] : 0x20;
    }
  }

  if (name != null) text(72, 0xfc, name);
  if (serial != null) text(90, 0xff, serial);
  return b;
}

void main() {
  final named = MonitorsXml.parseEdid(
    edid(name: "LG ULTRAGEAR+", serial: "510RMEN8E292"),
  )!;
  check(named.vendor == "GSM", "vendor ${named.vendor}");
  check(named.product == "LG ULTRAGEAR+", "product ${named.product}");
  check(named.serial == "510RMEN8E292", "serial ${named.serial}");
  final bare = MonitorsXml.parseEdid(edid())!;
  check(bare.product == "0x40a3", "product code ${bare.product}");
  check(bare.serial == "0x00000000", "serial number ${bare.serial}");
  check(MonitorsXml.parseEdid([1, 2, 3]) == null, "not an EDID");

  const MonitorSpec lg = MonitorSpec(
    connector: "DP-8",
    vendor: "GSM",
    product: "LG ULTRAGEAR+",
    serial: "510RMEN8E292",
  );
  const MonitorSpec panel = MonitorSpec(
    connector: "eDP-1",
    vendor: "AUO",
    product: "0x40a3",
    serial: "0x00000000",
  );
  const String other = """<configuration>
    <layoutmode>logical</layoutmode>
    <logicalmonitor>
      <x>0</x>
      <y>0</y>
      <scale>1.5</scale>
      <primary>yes</primary>
      <monitor>
        <monitorspec>
          <connector>DP-9</connector>
          <vendor>GSM</vendor>
          <product>LG ULTRAGEAR+</product>
          <serial>510RMEN8E292</serial>
        </monitorspec>
        <mode>
          <width>3840</width>
          <height>2160</height>
          <rate>165.058</rate>
        </mode>
        <underscanning>no</underscanning>
      </monitor>
    </logicalmonitor>
  </configuration>""";
  final Directory dir = Directory.systemTemp.createTempSync("monitors_xml");
  final String path = "${dir.path}/monitors.xml";
  File(path).writeAsStringSync('<monitors version="2">\n  $other\n</monitors>\n');

  List<(MonitorSpec, OutputSettings)> setup(double scale) => [
        (
          lg,
          OutputSettings(
            id: "lg",
            enabled: true,
            width: 3840,
            height: 2160,
            refresh: 165058,
            scale: scale,
            transform: 0,
            x: 0,
            y: 0,
          ),
        ),
        (panel, const OutputSettings(id: "panel", enabled: false)),
      ];
  check(MonitorsXml.save(setup(1.5), path: path), "saved");
  check(MonitorsXml.save(setup(4 / 3), path: path), "saved again");
  final String text = File(path).readAsStringSync();
  check(text.contains(other), "the other configuration kept as it was");
  check(RegExp("<configuration>").allMatches(text).length == 2,
      "this one replaced, not added twice");

  final Map<String, OutputSettings>? resolved = MonitorsXml.resolve(
    MonitorsXml.load(path),
    [
      (id: "lg", name: "DP-8", model: "LG ULTRAGEAR+", serial: "510RMEN8E292"),
      (id: "panel", name: "eDP-1", model: "0x40A3", serial: ""),
    ],
  );
  check(resolved != null, "read back");
  check(resolved!["lg"]!.scale == 4 / 3, "scale ${resolved["lg"]!.scale}");
  check(resolved["lg"]!.refresh == 165058, "rate");
  check(!resolved["panel"]!.enabled, "panel off");

  File(path).writeAsStringSync("<monitors version=\"1\"></monitors>");
  check(!MonitorsXml.save(setup(1.5), path: path), "version 1 left alone");
  dir.deleteSync(recursive: true);
  print("monitors_xml: ok");
}
