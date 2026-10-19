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
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:dahlia_apps/kit/preferences.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:yaru_window/yaru_window.dart';
import 'package:zenit_ui/zenit_ui.dart';

/// Static description of a dahliaOS application.
class DahliaAppSpec {
  const DahliaAppSpec({
    required this.name,
    required this.title,
    required this.builder,
  });

  /// Short name, also the first argument of the multi-call binary.
  final String name;
  final String title;
  final Widget Function(BuildContext context, List<String> args) builder;

  /// Application id, Wayland app_id and desktop entry id.
  String get id => "io.dahliaos.$name";

  String get iconAsset => "assets/icons/$id.png";
}

/// Boots the services shared by every dahliaOS app and runs [spec].
Future<void> runDahliaApp(DahliaAppSpec spec, List<String> args) async {
  // PANGOLIN_PROFILE: when startup reaches Dart, runApp and the first frame
  // (CLOCK_MONOTONIC milliseconds, as the shell's profile logs).
  final int dartStart = Timeline.now ~/ 1000;
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (kIsWeb) return;
    stderr.writeln("[${r.level.name}] ${r.loggerName}: ${r.message}"
        "${r.error != null ? " (${r.error})" : ""}");
    if (r.stackTrace != null && r.level >= Level.SEVERE) {
      stderr.writeln(r.stackTrace);
    }
  });

  // Route framework and uncaught async errors to the log so they reach the
  // session journal instead of vanishing.
  final Logger flutterLogger = Logger("Flutter");
  FlutterError.onError = (details) {
    flutterLogger.severe(details.exceptionAsString(), details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    flutterLogger.severe("Uncaught error", error, stack);
    return true;
  };

  // Not awaited: the window's main thread is busy showing the window at this
  // point, and the app can be built meanwhile (the request still reaches
  // the window before its first frame).
  unawaited(
    ZenitWindowTitlebar.ensureInitialized().catchError((Object _) {
      // Not running inside the Flutter Linux runner (tests).
    }),
  );

  const ServiceEntry<LocaleService>.critical(LocaleServiceFactory()).register();
  const ServiceEntry<PreferencesService>.critical(
          AppPreferencesServiceFactory())
      .register();
  const ServiceEntry<CustomizationService>.critical(
    CustomizationServiceFactory(),
  ).register();
  await ServiceManager.startServices();
  await _setUpBlur();
  _setUpBorder();

  if (Platform.environment["PANGOLIN_PROFILE"] != null) {
    final int appStart = Timeline.now ~/ 1000;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      stderr.writeln(
        "[INFO] Startup: dart at ${dartStart}ms, runApp at ${appStart}ms, "
        "first frame at ${Timeline.now ~/ 1000}ms",
      );
    });
    // PANGOLIN_PROFILE=frames: every frame, as the shell logs them.
    if (Platform.environment["PANGOLIN_PROFILE"] == "frames") {
      SchedulerBinding.instance.addTimingsCallback((timings) {
        for (final FrameTiming t in timings) {
          stderr.writeln(
            "[INFO] FrameTiming: ${spec.name} frame: build "
            "${t.buildDuration.inMicroseconds / 1000}ms, raster "
            "${t.rasterDuration.inMicroseconds / 1000}ms, total "
            "${t.totalSpan.inMicroseconds / 1000}ms, at "
            "${t.timestampInMicroseconds(FramePhase.vsyncStart) ~/ 1000}ms",
          );
        }
      });
    }
  }
  runApp(DahliaApp(spec: spec, args: args));
}

/// Frosted glass from river (river-blur-v1), following the shell's "Visual
/// effects" setting.
Future<void> _setUpBlur() async {
  const MethodChannel channel = MethodChannel("io.dahliaos.apps/blur");
  ZenitBlur.sink = (view, regions) => channel.invokeMethod(
        "setBlurRegions",
        {"regions": regions.map((r) => r.encode()).toList()},
      );
  final String? known = Platform.environment["PANGOLIN_RIVER_BLUR"];
  if (known != null) {
    // Set by the runner.
    ZenitBlur.available.value = known == "1";
  } else {
    try {
      ZenitBlur.available.value =
          await channel.invokeMethod<bool>("blurSupported") ?? false;
    } on MissingPluginException {
      // Not running in the dahliaOS apps runner (tests).
    }
  }
  // Unfocused windows go opaque unless turned off in Settings.
  void apply() => ZenitBlur.effects.value =
      CustomizationService.current.enableEffects &&
          (_windowActive.value ||
              !(PreferencesService.current
                      .get<bool>(SessionSetting.opaqueInactiveWindows.key) ??
                  SessionSetting.opaqueInactiveWindows.defaultValue));
  CustomizationService.current.addListener(apply);
  PreferencesService.current.addListener(apply);
  _windowActive.addListener(apply);
  apply();
}

/// The hairline GTK draws around the window (Settings > Appearance > Window
/// borders): light in dark mode, dark in light mode, as macOS draws it.
void _setUpBorder() {
  const MethodChannel channel = MethodChannel("io.dahliaos.apps/window");
  String? sent;
  void apply() {
    final bool on =
        PreferencesService.current.get<bool>(SessionSetting.windowBorders.key) ??
            SessionSetting.windowBorders.defaultValue;
    final String ring = !on
        ? ""
        : CustomizationService.current.darkMode
            ? "rgba(255, 255, 255, 0.16)"
            : "rgba(0, 0, 0, 0.12)";
    if (ring == sent) return;
    sent = ring;
    unawaited(channel.invokeMethod<void>("setBorder", ring).catchError((Object _) {}));
  }

  CustomizationService.current.addListener(apply);
  PreferencesService.current.addListener(apply);
  apply();
}

/// Whether the app's window is focused (see [_WindowFocus]).
final ValueNotifier<bool> _windowActive = ValueNotifier(true);

/// Follows the focus of the app's window into [_windowActive].
class _WindowFocus extends StatefulWidget {
  const _WindowFocus({required this.child});

  final Widget child;

  @override
  State<_WindowFocus> createState() => _WindowFocusState();
}

class _WindowFocusState extends State<_WindowFocus> {
  StreamSubscription<YaruWindowState>? _states;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _states ??= YaruWindow.of(context).states().listen(
          (state) => _windowActive.value = state.isActive != false,
          onError: (Object _) {},
        );
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Theming shared with the shell: light/dark mode and the accent color follow
/// the Pangolin settings live.
class DahliaApp extends StatelessWidget {
  const DahliaApp({required this.spec, this.args = const [], super.key});

  final DahliaAppSpec spec;
  final List<String> args;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Fonts live in the session settings, next to CustomizationService's.
      listenable: Listenable.merge([
        CustomizationService.current,
        PreferencesService.current,
      ]),
      builder: (context, _) {
        final CustomizationService customization = CustomizationService.current;
        final PreferencesService prefs = PreferencesService.current;
        final Color? accent = customization.accentColor.resolve();
        final String? font = prefs.get<String>(SessionSetting.interfaceFont.key);
        final String? monospace =
            prefs.get<String>(SessionSetting.monospaceFont.key);
        return MaterialApp(
          title: spec.title,
          debugShowCheckedModeBanner: false,
          theme: createZenitTheme(
            primaryColor: accent,
            fontFamily: font,
            monospaceFontFamily: monospace,
          ),
          darkTheme: createZenitTheme(
            brightness: Brightness.dark,
            primaryColor: accent,
            fontFamily: font,
            monospaceFontFamily: monospace,
          ),
          themeMode: customization.darkMode ? ThemeMode.dark : ThemeMode.light,
          // Text outside any Material (tooltips, popups, overlay entries)
          // in the interface font too, not the engine's default.
          builder: (context, child) => _WindowFocus(
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyMedium!,
              child: child!,
            ),
          ),
          home: AppSpecScope(
            spec: spec,
            child: Builder(builder: (context) => spec.builder(context, args)),
          ),
        );
      },
    );
  }
}

/// Gives widgets access to the running application's [DahliaAppSpec].
class AppSpecScope extends InheritedWidget {
  const AppSpecScope({required this.spec, required super.child, super.key});

  final DahliaAppSpec spec;

  static DahliaAppSpec? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSpecScope>()?.spec;

  @override
  bool updateShouldNotify(AppSpecScope oldWidget) => oldWidget.spec != spec;
}
