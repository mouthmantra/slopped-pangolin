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
import 'package:dahlia_apps/kit/kit.dart';
import 'package:system_controls/system_controls.dart';

class _AudioNode {
  const _AudioNode(this.id, this.name, this.isDefault);
  final int id;
  final String name;
  final bool isDefault;
}

/// Sound settings through PipeWire's `wpctl`.
class SoundPage extends StatefulWidget {
  const SoundPage({super.key});

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  bool _available = SystemUtils.which("wpctl") != null;
  bool _loading = true;
  // The output volume is the one the shell shows (quick settings, volume
  // keys): shared and followed live.
  final VolumeControl _output = VolumeControl.instance;
  double get _volume => _output.volume;
  bool get _muted => _output.muted;
  double _micVolume = 0;
  bool _micMuted = false;
  List<_AudioNode> _sinks = [];
  List<_AudioNode> _sources = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _output.addListener(_onOutputChanged);
    _load();
  }

  @override
  void dispose() {
    _output.removeListener(_onOutputChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onOutputChanged() {
    if (mounted) setState(() {});
  }

  static (double, bool)? _parseVolume(String? out) {
    final Match? m = RegExp(r"Volume:\s*([0-9.]+)(\s*\[MUTED\])?").firstMatch(out ?? "");
    if (m == null) return null;
    return (double.parse(m.group(1)!), m.group(2) != null);
  }

  /// Parses the "Sinks:" / "Sources:" sections of `wpctl status`.
  static List<_AudioNode> _parseNodes(String status, String section) {
    final List<_AudioNode> nodes = [];
    bool inAudio = false;
    bool inSection = false;
    for (final String raw in status.split("\n")) {
      final String line = raw.replaceAll(RegExp("[│├└─]"), " ");
      if (line.trim() == "Audio") inAudio = true;
      if (line.trim() == "Video") inAudio = false;
      if (!inAudio) continue;
      if (line.trim().endsWith(":")) {
        inSection = line.trim() == "$section:";
        continue;
      }
      if (!inSection) continue;
      final Match? m = RegExp(r"^\s*(\*)?\s*(\d+)\.\s+(.*?)(\s*\[vol:.*\])?$").firstMatch(line);
      if (m == null) {
        if (line.trim().isEmpty) inSection = false;
        continue;
      }
      nodes.add(_AudioNode(int.parse(m.group(2)!), m.group(3)!.trim(), m.group(1) != null));
    }
    return nodes;
  }

  Future<void> _load() async {
    if (!_available) {
      setState(() => _loading = false);
      return;
    }
    final (double, bool)? sink = _parseVolume(await SystemUtils.run("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"]));
    final (double, bool)? source = _parseVolume(await SystemUtils.run("wpctl", ["get-volume", "@DEFAULT_AUDIO_SOURCE@"]));
    final String status = await SystemUtils.run("wpctl", ["status"]) ?? "";
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (sink == null && status.isEmpty) _available = false;
      _micVolume = source?.$1 ?? 0;
      _micMuted = source?.$2 ?? false;
      _sinks = _parseNodes(status, "Sinks");
      _sources = _parseNodes(status, "Sources");
    });
  }

  void _setVolume(String target, double value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 80), () {
      SystemUtils.run("wpctl", ["set-volume", target, value.toStringAsFixed(2)]);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_available) {
      return const EmptyState(
        icon: Icons.volume_off_rounded,
        title: "Sound settings unavailable",
        subtitle: "Pangolin manages audio through PipeWire (wpctl), which isn't running.",
      );
    }

    return SettingsPageBody(
      children: [
        SettingsGroup(
          title: "Output",
          children: [
            SettingsRow(
              icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              title: "Volume",
              subtitle: "${(_volume * 100).round()}%",
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    child: Slider(
                      value: _volume.clamp(0, 1),
                      onChanged: _output.setVolume,
                    ),
                  ),
                  IconButton(
                    tooltip: _muted ? "Unmute" : "Mute",
                    icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded),
                    onPressed: () => _output.setMuted(!_muted),
                  ),
                ],
              ),
            ),
            for (final _AudioNode sink in _sinks)
              SettingsRow(
                icon: Icons.speaker_rounded,
                title: sink.name,
                trailing: sink.isDefault
                    ? const Icon(Icons.check_rounded)
                    : TextButton(
                        onPressed: () async {
                          await SystemUtils.run("wpctl", ["set-default", "${sink.id}"]);
                          await _load();
                        },
                        child: const Text("Use"),
                      ),
              ),
          ],
        ),
        SettingsGroup(
          title: "Input",
          children: [
            SettingsRow(
              icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              title: "Microphone",
              subtitle: "${(_micVolume * 100).round()}%",
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    child: Slider(
                      value: _micVolume.clamp(0, 1),
                      onChanged: (v) {
                        setState(() => _micVolume = v);
                        _setVolume("@DEFAULT_AUDIO_SOURCE@", v);
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(_micMuted ? Icons.mic_off_rounded : Icons.mic_none_rounded),
                    onPressed: () async {
                      await SystemUtils.run("wpctl", ["set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
                      await _load();
                    },
                  ),
                ],
              ),
            ),
            for (final _AudioNode source in _sources)
              SettingsRow(
                icon: Icons.mic_external_on_rounded,
                title: source.name,
                trailing: source.isDefault
                    ? const Icon(Icons.check_rounded)
                    : TextButton(
                        onPressed: () async {
                          await SystemUtils.run("wpctl", ["set-default", "${source.id}"]);
                          await _load();
                        },
                        child: const Text("Use"),
                      ),
              ),
          ],
        ),
      ],
    );
  }
}
