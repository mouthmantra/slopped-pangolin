import 'dart:async';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:intl/intl.dart';
import 'package:pangolin_settings/pangolin_settings.dart';

class DateTimeServiceFactory extends ServiceFactory<DateTimeService> {
  const DateTimeServiceFactory();

  @override
  DateTimeService build() => _DateTimeServiceImpl();
}

abstract class DateTimeService extends ListenableService {
  DateTimeService();

  static DateTimeService get current {
    return ServiceManager.getService<DateTimeService>()!;
  }

  DateTime get date;

  String get formattedDate;
  String get formattedTime;
}

class _DateTimeServiceImpl extends DateTimeService {
  CustomizationService get customization => CustomizationService.current;

  Timer? _timer;
  late DateTime _lastDate;

  @override
  DateTime get date => _lastDate;

  @override
  String get formattedDate => DateFormat("dd.MM.yyyy").format(date);

  // Clock format chosen in Settings → Date & Time.
  T _setting<T extends Object>(SessionSetting<T> setting) =>
      PreferencesService.current.get<T>(setting.key) ?? setting.defaultValue;

  bool get _showSeconds => _setting(SessionSetting.clockShowSeconds);

  @override
  String get formattedTime {
    final bool seconds = _showSeconds;
    final String pattern = _setting(SessionSetting.clock24Hour)
        ? (seconds ? "HH:mm:ss" : "HH:mm")
        : (seconds ? "h:mm:ss a" : "h:mm a");
    return DateFormat(pattern).format(date);
  }

  @override
  Future<void> start() async {
    await ServiceManager.waitForService<CustomizationService>();
    await ServiceManager.waitForService<PreferencesService>();

    _lastDate = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 200), _checkTime);

    CustomizationService.current.addListener(notifyListeners);
    PreferencesService.current.addListener(notifyListeners);
  }

  @override
  void stop() {
    _timer?.cancel();
    CustomizationService.current.removeListener(notifyListeners);
    PreferencesService.current.removeListener(notifyListeners);
  }

  void _checkTime(Timer timer) {
    final DateTime now = DateTime.now();

    // Only rebuild the clock when what it shows changes.
    final bool changed = _showSeconds
        ? _lastDate.second != now.second
        : _lastDate.minute != now.minute || _lastDate.hour != now.hour;
    if (!changed && _lastDate.day == now.day) return;

    _lastDate = now;
    notifyListeners();
  }
}
