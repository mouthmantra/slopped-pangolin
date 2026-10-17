import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:pangolin/services/dbus/power_profiles.dart';
import 'package:pangolin/services/dbus/utils.dart';
import 'package:upower/upower.dart';

export 'package:pangolin/services/dbus/power_profiles.dart' show PowerProfile;
export 'package:upower/upower.dart'
    show
        UPowerDeviceBatteryLevel,
        UPowerDeviceHistoryRecord,
        UPowerDeviceState,
        UPowerDeviceStatisticsRecord,
        UPowerDeviceTechnology,
        UPowerDeviceType,
        UPowerDeviceWarningLevel;

enum LidStatus { unknown, open, closed }

class PowerServiceFactory extends ServiceFactory<PowerService> {
  const PowerServiceFactory();

  // Without a system bus (containers, minimal installs) there is nothing to
  // talk to: use the dummy service directly instead of failing to start.
  @override
  PowerService build() =>
      systemBusAvailable() ? _UPowerPowerService() : _DummyPowerService();

  @override
  PowerService fallback() => _DummyPowerService();
}

abstract class PowerService extends ListenableService {
  PowerService();

  static PowerService get current {
    return ServiceManager.getService<PowerService>()!;
  }

  bool get hasBattery =>
      mainBattery != null && mainBattery!.type == UPowerDeviceType.battery;

  PowerDevice? get mainBattery;
  List<PowerDevice> get devices;
  LidStatus get lidStatus;
  bool get onBattery;

  List<PowerProfile> get profiles;
  ValueNotifier<PowerProfile> get activeProfileNotifier;
  PowerProfile get activeProfile => activeProfileNotifier.value;
  Future<void> setActiveProfile(PowerProfile profile);
}

class _UPowerPowerService extends PowerService {
  late final DBusClient client;
  late final UPowerClient upower;
  late PowerProfilesClient? powerProfiles;
  late final StreamSubscription deviceAddedSub;
  late final StreamSubscription deviceRemovedSub;
  late final StreamSubscription propertiesChangedSub;
  late final PowerDevice _displayDevice;
  final List<PowerDevice> _devices = [];

  @override
  Future<void> start() async {
    client = DBusClient.system();
    upower = UPowerClient(bus: client);
    // Without UPower connect() never completes; give up so the dummy service
    // takes over instead of blocking shell startup.
    try {
      await upower.connect().timeout(const Duration(seconds: 3));
    } catch (_) {
      await client.close();
      rethrow;
    }
    deviceAddedSub = upower.deviceAdded.listen(_notifyAddDevice);
    deviceRemovedSub = upower.deviceRemoved.listen(_notifyRemoveDevice);
    propertiesChangedSub = upower.propertiesChanged.listen(_notifyProperties);

    for (final device in upower.devices) {
      _devices.add(PowerDevice._(device));
    }

    _displayDevice = PowerDevice._(upower.displayDevice);

    try {
      powerProfiles = PowerProfilesClient(bus: client);
      await powerProfiles!.connect().timeout(const Duration(seconds: 3));
    } catch (e) {
      // power-profiles-daemon is optional: the profile switcher just hides.
      powerProfiles = null;
      logger.info("power-profiles-daemon isn't available, profiles disabled");
    }
  }

  @override
  Future<void> stop() async {
    await deviceAddedSub.cancel();
    await deviceRemovedSub.cancel();
    await propertiesChangedSub.cancel();
    await upower.close();
    await client.close();
  }

  @override
  PowerDevice get mainBattery => _displayDevice;

  @override
  List<PowerDevice> get devices => _devices;

  @override
  LidStatus get lidStatus {
    if (!upower.lidIsPresent) return LidStatus.unknown;

    return upower.lidIsClosed ? LidStatus.closed : LidStatus.open;
  }

  @override
  bool get onBattery => upower.onBattery;

  @override
  List<PowerProfile> get profiles =>
      powerProfiles?.profiles ?? [PowerProfile.balanced];

  @override
  ValueNotifier<PowerProfile> get activeProfileNotifier =>
      powerProfiles?.activeProfile ?? ValueNotifier(PowerProfile.balanced);

  @override
  Future<void> setActiveProfile(PowerProfile profile) async =>
      powerProfiles?.setActiveProfile(profile);

  void _notifyAddDevice(UPowerDevice device) {
    _devices.add(PowerDevice._(device));
    notifyListeners();
  }

  void _notifyRemoveDevice(UPowerDevice device) {
    _devices.removeWhere((e) => e._device == device);
    notifyListeners();
  }

  void _notifyProperties(List<String> properties) {
    notifyListeners();
  }
}

class _DummyPowerService extends PowerService {
  @override
  void start() {
    // noop
  }

  @override
  void stop() {
    // noop
  }

  @override
  PowerDevice? get mainBattery => null;

  @override
  List<PowerDevice> get devices => [];

  @override
  LidStatus get lidStatus => LidStatus.unknown;

  @override
  bool get onBattery => false;

  @override
  ValueNotifier<PowerProfile> get activeProfileNotifier =>
      ValueNotifier(PowerProfile.balanced);

  @override
  List<PowerProfile> get profiles => [];

  @override
  Future<void> setActiveProfile(PowerProfile profile) async {}
}

class PowerDevice with ChangeNotifier {
  final UPowerDevice _device;
  late final StreamSubscription<List<String>> _propertiesChangedSub;

  PowerDevice._(this._device) {
    _propertiesChangedSub = _device.propertiesChanged.listen(_notify);
  }

  @override
  void dispose() {
    _propertiesChangedSub.cancel();
    super.dispose();
  }

  void _notify(List<String> properties) {
    notifyListeners();
  }

  UPowerDeviceBatteryLevel get batteryLevel => _device.batteryLevel;

  double get capacity => _device.capacity;

  double get energy => _device.energy;

  double get energyEmpty => _device.energyEmpty;

  double get energyFull => _device.energyFull;

  double get energyFullDesign => _device.energyFullDesign;

  double get energyRate => _device.energyRate;

  Future<List<UPowerDeviceHistoryRecord>> getHistory(
    String type,
    int resolution, {
    int timespan = 0,
  }) =>
      _device.getHistory(type, resolution, timespan: timespan);

  Future<List<UPowerDeviceStatisticsRecord>> getStatistics(String type) =>
      _device.getStatistics(type);

  bool get hasHistory => _device.hasHistory;

  bool get hasStatistics => _device.hasStatistics;

  bool get isPresent => _device.isPresent;

  bool get isRechargeable => _device.isRechargeable;

  double get luminosity => _device.luminosity;

  String get model => _device.model;

  String get nativePath => _device.nativePath;

  bool get online => _device.online;

  double get percentage => _device.percentage;

  bool get powerSupply => _device.powerSupply;

  Future<void> refresh() => _device.refresh();

  String get serial => _device.serial;

  UPowerDeviceState get state => _device.state;

  UPowerDeviceTechnology get technology => _device.technology;

  double get temperature => _device.temperature;

  int get timeToEmpty => _device.timeToEmpty;

  int get timeToFull => _device.timeToFull;

  UPowerDeviceType get type => _device.type;

  int get updateTime => _device.updateTime;

  String get vendor => _device.vendor;

  double get voltage => _device.voltage;

  UPowerDeviceWarningLevel get warningLevel => _device.warningLevel;
}
