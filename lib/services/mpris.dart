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

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:dbus/dbus.dart';

/// Media players on the session bus (MPRIS 2): what plays, and controls for
/// Quick Settings.
class MprisServiceFactory extends ServiceFactory<MprisService> {
  const MprisServiceFactory();

  @override
  MprisService build() => MprisService();

  /// No session bus: no players.
  @override
  MprisService fallback() => MprisService(connect: false);
}

class MprisService extends ListenableService {
  MprisService({this.connect = true});

  static MprisService get current => ServiceManager.getService<MprisService>()!;

  final bool connect;

  static const String _prefix = "org.mpris.MediaPlayer2.";

  DBusClient? _bus;
  StreamSubscription<DBusNameOwnerChangedEvent>? _names;
  final Map<String, MediaPlayer> _players = {};
  String? _chosen;

  List<MediaPlayer> get players => _players.values.toList();

  /// The player to show: the one picked, else one playing, else the one
  /// that changed last.
  MediaPlayer? get player {
    final MediaPlayer? chosen = _players[_chosen];
    if (chosen != null) return chosen;
    final List<MediaPlayer> all = players
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return all.where((p) => p.playing).firstOrNull ?? all.firstOrNull;
  }

  void choose(MediaPlayer player) {
    _chosen = player.busName;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    if (!connect) return;
    final DBusClient bus = DBusClient.session();
    _bus = bus;
    _names = bus.nameOwnerChanged.listen((event) {
      if (!event.name.startsWith(_prefix)) return;
      _remove(event.name);
      if (event.newOwner?.isNotEmpty ?? false) unawaited(_add(event.name));
    });
    // Players already running, without holding up the shell's start.
    unawaited(
      bus.listNames().then((names) {
        for (final String name in names) {
          if (name.startsWith(_prefix)) unawaited(_add(name));
        }
      }, onError: (Object e) => logger.warning("Couldn't list media players: $e")),
    );
  }

  @override
  Future<void> stop() async {
    await _names?.cancel();
    for (final MediaPlayer player in _players.values) {
      player._dispose();
    }
    _players.clear();
    await _bus?.close();
  }

  Future<void> _add(String name) async {
    final MediaPlayer player = MediaPlayer._(
      name,
      DBusRemoteObject(
        _bus!,
        name: name,
        path: DBusObjectPath("/org/mpris/MediaPlayer2"),
      ),
      notifyListeners,
    );
    _players[name] = player;
    try {
      await player._load();
    } on Object catch (e) {
      logger.info("Ignoring media player $name: $e");
      if (identical(_players[name], player)) _remove(name);
      return;
    }
    notifyListeners();
  }

  void _remove(String name) {
    final MediaPlayer? player = _players.remove(name);
    if (player == null) return;
    player._dispose();
    if (_chosen == name) _chosen = null;
    notifyListeners();
  }
}

/// One MPRIS player (org.mpris.MediaPlayer2.*).
class MediaPlayer {
  MediaPlayer._(this.busName, this._object, this._changed);

  static const String _player = "org.mpris.MediaPlayer2.Player";

  final String busName;
  final DBusRemoteObject _object;
  final void Function() _changed;
  final List<StreamSubscription<Object>> _subscriptions = [];

  String identity = "";
  String status = "Stopped";
  String title = "";
  List<String> artists = const [];
  String? artUrl;
  Duration? length;
  bool canGoNext = false;
  bool canGoPrevious = false;
  bool canPlay = false;
  bool canPause = false;
  bool canSeek = false;
  DateTime changedAt = DateTime.now();

  DBusObjectPath? _trackId;
  Duration _position = Duration.zero;
  DateTime _positionAt = DateTime.now();
  double _rate = 1;

  bool get playing => status == "Playing";
  String get artist => artists.join(", ");

  /// Players don't signal position changes: it is read when the track or
  /// the playback state changes and after seeks, and counted on meanwhile.
  Duration get position {
    Duration value = _position;
    if (playing) value += DateTime.now().difference(_positionAt) * _rate;
    final Duration? end = length;
    return end != null && value > end ? end : value;
  }

  Future<void> playPause() => _call("PlayPause");
  Future<void> next() => _call("Next");
  Future<void> previous() => _call("Previous");

  Future<void> seekTo(Duration to) async {
    final DBusObjectPath? track = _trackId;
    if (track != null) {
      await _call("SetPosition", [track, DBusInt64(to.inMicroseconds)]);
    } else {
      await _call("Seek", [DBusInt64((to - position).inMicroseconds)]);
    }
    _setPosition(to);
    _changed();
  }

  Future<void> _load() async {
    final Map<String, DBusValue> root =
        await _object.getAllProperties("org.mpris.MediaPlayer2");
    identity = root["Identity"]?.toNative() as String? ??
        busName.substring("org.mpris.MediaPlayer2.".length);
    _apply(await _object.getAllProperties(_player));
    _subscriptions.add(
      _object.propertiesChanged.listen((signal) {
        if (signal.propertiesInterface != _player) return;
        _apply(signal.changedProperties);
        if (signal.invalidatedProperties.isNotEmpty) unawaited(_reload());
      }),
    );
    _subscriptions.add(
      DBusRemoteObjectSignalStream(
        object: _object,
        interface: _player,
        name: "Seeked",
      ).listen((signal) {
        final Object? micros = signal.values.firstOrNull?.toNative();
        if (micros is int) _setPosition(Duration(microseconds: micros));
        _changed();
      }),
    );
  }

  Future<void> _reload() async {
    try {
      _apply(await _object.getAllProperties(_player));
    } on Object {
      // Gone meanwhile: the service drops it on NameOwnerChanged.
    }
  }

  void _apply(Map<String, DBusValue> properties) {
    final Object? newStatus = properties["PlaybackStatus"]?.toNative();
    if (newStatus is String && newStatus != status) {
      // Freeze the counted position before playing stops (or resume it).
      _setPosition(position);
      status = newStatus;
      changedAt = DateTime.now();
      unawaited(_readPosition());
    }
    final DBusValue? metadata = properties["Metadata"];
    if (metadata is DBusDict) {
      final Map<String, DBusValue> m = metadata.asStringVariantDict();
      title = m["xesam:title"]?.toNative() as String? ?? "";
      final Object? artist = m["xesam:artist"]?.toNative();
      // Arrays come back as an Iterable.
      artists = artist is Iterable
          ? artist.whereType<String>().toList()
          : artist is String
              ? [artist]
              : const [];
      final Object? art = m["mpris:artUrl"]?.toNative();
      artUrl = art is String && art.isNotEmpty ? art : null;
      final Object? micros = m["mpris:length"]?.toNative();
      length = micros is int && micros > 0 ? Duration(microseconds: micros) : null;
      final DBusValue? track = m["mpris:trackid"];
      _trackId = track is DBusObjectPath ? track : null;
      changedAt = DateTime.now();
      unawaited(_readPosition());
    }
    final Object? rate = properties["Rate"]?.toNative();
    if (rate is num && rate > 0) {
      _setPosition(position);
      _rate = rate.toDouble();
    }
    bool flag(String name, bool current) {
      final Object? value = properties[name]?.toNative();
      return value is bool ? value : current;
    }

    canGoNext = flag("CanGoNext", canGoNext);
    canGoPrevious = flag("CanGoPrevious", canGoPrevious);
    canPlay = flag("CanPlay", canPlay);
    canPause = flag("CanPause", canPause);
    canSeek = flag("CanSeek", canSeek);
    _changed();
  }

  Future<void> _readPosition() async {
    try {
      final Object? micros =
          (await _object.getProperty(_player, "Position")).toNative();
      if (micros is int) {
        _setPosition(Duration(microseconds: micros));
        _changed();
      }
    } on Object {
      // Not every player reports a position.
    }
  }

  void _setPosition(Duration value) {
    _position = value.isNegative ? Duration.zero : value;
    _positionAt = DateTime.now();
  }

  Future<void> _call(String method, [List<DBusValue> args = const []]) async {
    try {
      await _object.callMethod(_player, method, args);
    } on Object {
      // The player went away or refused.
    }
  }

  void _dispose() {
    for (final StreamSubscription<Object> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
