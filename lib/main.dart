/*
Copyright 2021 The dahliaOS Authors

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
import 'dart:ui';

import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import "package:intl/locale.dart" as intl;
import 'package:logging/logging.dart';
import 'package:pangolin/components/shell/desktop.dart';
import 'package:pangolin/components/shell/session_commands.dart';
import 'package:pangolin/components/shell/shell_popups.dart';
import 'package:pangolin/services/application.dart';
import 'package:pangolin/services/date_time.dart';
import 'package:pangolin/services/icon.dart';
import 'package:pangolin/services/input.dart';
import 'package:pangolin/services/langpacks.dart';
import 'package:pangolin/services/mpris.dart';
import 'package:pangolin/services/notifications.dart';
import 'package:pangolin/services/power.dart';
import 'package:pangolin/services/search.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/display_power.dart';
import 'package:pangolin/services/polkit_agent.dart';
import 'package:pangolin/services/session_lock.dart';
import 'package:pangolin/services/splash_cache.dart';
import 'package:pangolin/services/privacy.dart';
import 'package:pangolin/services/vpn.dart';
import 'package:pangolin/services/wallpaper_accent.dart';
import 'package:pangolin/services/wallpaper_share.dart';
import 'package:pangolin/components/greeter/greeter_screen.dart';
import 'package:pangolin/components/lock/lock_screen.dart';
import 'package:pangolin/services/system_theme.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/tray.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/data/app_ids.dart';
import 'package:pangolin/utils/other/logging.dart';
import 'package:pangolin/widgets/input_region.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:yatl_flutter/yatl_flutter.dart';
import 'package:zenit_ui/zenit_ui.dart';

const List<ServiceEntry> _services = [
  ServiceEntry<ShellService>.critical(ShellServiceFactory()),
  ServiceEntry<LocaleService>.critical(LocaleServiceFactory()),
  ServiceEntry<SearchService>(SearchServiceFactory()),
  ServiceEntry<WindowManagerService>.critical(WindowManagerServiceFactory()),
  ServiceEntry<LangPacksService>(LangPacksServiceFactory()),
  ServiceEntry<ApplicationService>(ApplicationServiceFactory()),
  ServiceEntry<IconService>(IconServiceFactory()),
  ServiceEntry<PreferencesService>.critical(PreferencesServiceFactory()),
  ServiceEntry<TrayService>(TrayServiceFactory()),
  ServiceEntry<NotificationService>(NotificationServiceFactory()),
  ServiceEntry<PowerService>(PowerServiceFactory()),
  ServiceEntry<CustomizationService>.critical(CustomizationServiceFactory()),
  ServiceEntry<DateTimeService>.critical(DateTimeServiceFactory()),
  ServiceEntry<InputService>(InputServiceFactory()),
  ServiceEntry<MprisService>(MprisServiceFactory()),
];

/// Registers the session settings next to dahlia_shared's in the `pangolin`
/// table scheme (only the table owner, the shell, may do this).
Future<void> _extendSettingsScheme() async {
  try {
    await PreferencesService.current
        .setScheme(sessionScheme(Preference.scheme));
  } catch (e) {
    // Expected with the local fallback (no dsettings): nothing to extend.
    Logger("Settings").warning("Couldn't register the session settings: $e");
  }
}

/// Waits for every service the shell UI reads while building, not just the
/// critical ones [ServiceManager.startServices] waits for. Services that fail
/// still complete (with their fallback or a FailedService).
Future<void> _waitForShellServices() async {
  await _extendSettingsScheme();
  await Future.wait([
    ServiceManager.waitForService<SearchService>(),
    ServiceManager.waitForService<LangPacksService>(),
    ServiceManager.waitForService<ApplicationService>(),
    ServiceManager.waitForService<IconService>(),
    ServiceManager.waitForService<TrayService>(),
    ServiceManager.waitForService<MprisService>(),
    ServiceManager.waitForService<NotificationService>(),
    ServiceManager.waitForService<PowerService>(),
  ]);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  setupLogger();
  // PANGOLIN_PROFILE=1: log frames that miss a 60 Hz deadline;
  // PANGOLIN_PROFILE=frames: log every frame, with the time since the
  // previous one.
  final String? profile = Platform.environment["PANGOLIN_PROFILE"];
  if (profile != null) {
    final Logger frames = Logger("FrameTiming");
    int? previousVsync;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final FrameTiming t in timings) {
        final int vsync = t.timestampInMicroseconds(FramePhase.vsyncStart);
        final int? interval =
            previousVsync == null ? null : vsync - previousVsync!;
        previousVsync = vsync;
        if (profile == "frames" ||
            t.totalSpan > const Duration(milliseconds: 17)) {
          frames.info(
            "frame: build ${t.buildDuration.inMicroseconds / 1000}ms, "
            "raster ${t.rasterDuration.inMicroseconds / 1000}ms, "
            "total ${t.totalSpan.inMicroseconds / 1000}ms"
            "${interval == null ? "" : ", since previous ${interval / 1000}ms"}"
            ", at ${vsync ~/ 1000}ms"
            ", vsync ${t.vsyncOverhead.inMicroseconds / 1000}ms, queued "
            "${(t.timestampInMicroseconds(FramePhase.rasterStart) - t.timestampInMicroseconds(FramePhase.buildFinish)) / 1000}ms",
          );
        }
      }
    });
  }
  await PangolinSession.init();

  // The login screen (display manager), run by greetd.
  if (PangolinSession.isSession &&
      Platform.environment["PANGOLIN_GREETER"] == "1") {
    await _runGreeter();
    return;
  }

  if (PangolinSession.isSession) {
    await _runSession();
  } else {
    _runWindowed();
  }
}

/// Desktop shell of a Wayland session: services (including the window
/// manager) must be up before any surface is mapped, then the desktop and the
/// shell render into their own Flutter views.
Future<void> _runSession() async {
  for (final ServiceEntry entry in _services) {
    entry.register();
  }
  await ServiceManager.startServices();
  await _waitForShellServices();
  _ensureDefaultPins();
  _followVisualEffects();
  SystemTheme.follow();
  await SessionLock.instance.init();
  unawaited(DisplayPower.instance.start());
  unawaited(PolkitAgent.instance.start());
  unawaited(VpnService.instance.start());
  unawaited(PrivacyMonitor.instance.start());
  SplashCache.follow();
  WallpaperShare.follow();
  WallpaperAccent.follow();

  runWidget(const PangolinSessionRoot());
  await PangolinSession.showSurfaces();
}

/// What the login screen needs: river (as its window manager, which layer
/// surfaces require), settings and theming.
const List<ServiceEntry> _greeterServices = [
  ServiceEntry<LocaleService>.critical(LocaleServiceFactory()),
  ServiceEntry<WindowManagerService>.critical(WindowManagerServiceFactory()),
  ServiceEntry<PreferencesService>.critical(PreferencesServiceFactory()),
  ServiceEntry<CustomizationService>.critical(CustomizationServiceFactory()),
];

Future<void> _runGreeter() async {
  for (final ServiceEntry entry in _greeterServices) {
    entry.register();
  }
  await ServiceManager.startServices();
  // The whole shell surface takes input and the keyboard.
  ShellInputRegion.instance.claim(_greeterOwner, true);
  runWidget(const _GreeterRoot());
  // River's splash (the wallpaper) shows below the login screen until it
  // draws: no desktop surface.
  await PangolinSession.showSurfaces(desktop: false);
}

final Object _greeterOwner = Object();

class _GreeterRoot extends StatefulWidget {
  const _GreeterRoot();

  @override
  State<_GreeterRoot> createState() => _GreeterRootState();
}

class _GreeterRootState extends State<_GreeterRoot>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  FlutterView? _view(int? id) =>
      WidgetsBinding.instance.platformDispatcher.views
          .where((v) => v.viewId == id)
          .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final FlutterView? desktop = _view(PangolinSession.desktopViewId);
    final FlutterView? shell = _view(PangolinSession.shellViewId);
    return ViewCollection(
      views: [
        if (desktop != null)
          // Transparent: river's splash (the last user's wallpaper, which
          // the login screen starts on) shows until the login screen draws.
          View(
            view: desktop,
            child: const SizedBox.shrink(),
          ),
        if (shell != null)
          View(
            view: shell,
            child: const PangolinApp(child: GreeterScreen()),
          ),
      ],
    );
  }
}

/// Blur and transparency follow the "Visual effects" setting.
void _followVisualEffects() {
  void apply() =>
      ZenitBlur.effects.value = CustomizationService.current.enableEffects;
  CustomizationService.current.addListener(apply);
  apply();
}

/// First start of a session: pin the core dahliaOS apps. Runs before the UI
/// is built so the change doesn't notify widgets mid-build.
void _ensureDefaultPins() {
  final String key = SessionSetting.defaultPinsApplied.key;
  final PreferencesService prefs = PreferencesService.current;
  if (prefs.get<bool>(key) ?? false) return;
  prefs.set<bool>(key, true);
  if (CustomizationService.current.pinnedApps.isEmpty) {
    CustomizationService.current.pinnedApps = DahliaApps.defaultPinned;
  }
}

void _runWindowed() {
  runApp(
    ServiceBuilderWidget(
      services: _services,
      onLoaded: _waitForShellServices,
      builder: (context, loaded, child) {
        if (!loaded) return const ColoredBox(color: Colors.black);
        if (kIsWeb) BrowserContextMenu.disableContextMenu();
        return child!;
      },
      child: const PangolinApp(child: Desktop()),
    ),
  );
}

/// Theme, localization and navigation shared by every Pangolin surface.
class PangolinApp extends StatelessWidget {
  const PangolinApp({
    required this.child,
    this.transparent = false,
    this.navigatorObservers = const [],
    this.navigatorKey,
    super.key,
  });

  final Widget child;
  final bool transparent;
  final List<NavigatorObserver> navigatorObservers;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // Fonts live in the session settings, next to CustomizationService's.
      listenable: Listenable.merge([
        CustomizationService.current,
        PreferencesService.current,
      ]),
      builder: (context, _) {
        final CustomizationService service = CustomizationService.current;
        final PreferencesService prefs = PreferencesService.current;
        final Color? accent = service.accentColor.resolve();
        final String? font =
            prefs.get<String>(SessionSetting.interfaceFont.key);
        final String? monospace =
            prefs.get<String>(SessionSetting.monospaceFont.key);

        ThemeData themed(Brightness brightness) {
          final ThemeData theme = createZenitTheme(
            brightness: brightness,
            primaryColor: accent,
            fontFamily: font,
            monospaceFontFamily: monospace,
          );
          return transparent
              ? theme.copyWith(
                  scaffoldBackgroundColor: Colors.transparent,
                  canvasColor: Colors.transparent,
                )
              : theme;
        }

        return YatlApp(
          core: yatl,
          getLocale: () =>
              intl.Locale.tryParse(service.locale)?.toFlutterLocale(),
          setLocale: (locale) => service.locale = locale?.toString(),
          child: Builder(
            builder: (context) => MaterialApp(
              navigatorKey: navigatorKey,
              home: child,
              color: transparent ? Colors.transparent : null,
              theme: themed(Brightness.light),
              darkTheme: themed(Brightness.dark),
              themeMode: service.darkMode ? ThemeMode.dark : ThemeMode.light,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              localizationsDelegates: [
                GlobalWidgetsLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                context.localizationsDelegate,
              ],
              navigatorObservers: navigatorObservers,
              debugShowCheckedModeBanner: false,
              // Text outside any Material (tooltips, popups, overlay
              // entries) in the interface font too, not the engine's
              // default.
              builder: (context, child) => DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!,
                child: child!,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Root of session mode: one Flutter view per layer-shell surface.
class PangolinSessionRoot extends StatefulWidget {
  const PangolinSessionRoot({super.key});

  @override
  State<PangolinSessionRoot> createState() => _PangolinSessionRootState();
}

class _PangolinSessionRootState extends State<PangolinSessionRoot>
    with WidgetsBindingObserver {
  final ShellModalRouteObserver _shellRoutes = ShellModalRouteObserver();
  final Map<int, _LazyView> _lazyViews = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SessionLock.instance.addListener(_onLockChanged);
  }

  @override
  void dispose() {
    SessionLock.instance.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeMetrics() {
    // Views appear once the native surfaces are realized.
    if (mounted) setState(() {});
  }

  FlutterView? _view(int? id) =>
      WidgetsBinding.instance.platformDispatcher.views
          .where((v) => v.viewId == id)
          .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final FlutterView? desktop = _view(PangolinSession.desktopViewId);
    final FlutterView? shell = _view(PangolinSession.shellViewId);
    final List<FlutterView> lockViews = [
      for (final int id in SessionLock.instance.views)
        if (_view(id) case final FlutterView view) view,
    ];
    _lazyViews.removeWhere(
      (id, lazy) =>
          lazy.view != desktop &&
          lazy.view != shell &&
          !lockViews.contains(lazy.view),
    );
    _LazyView lazy(FlutterView view) =>
        _lazyViews.putIfAbsent(view.viewId, () => _LazyView(view));

    return ViewCollection(
      views: [
        if (desktop != null)
          View(
            view: desktop,
            deprecatedDoNotUseWillBeRemovedWithoutNoticePipelineOwner:
                lazy(desktop).pipelineOwner,
            deprecatedDoNotUseWillBeRemovedWithoutNoticeRenderView:
                lazy(desktop).renderView,
            // Transparent until the wallpaper is decoded: river's splash
            // (the same wallpaper) shows through meanwhile.
            child: const PangolinApp(
              transparent: true,
              child: DesktopSurface(),
            ),
          ),
        if (shell != null)
          View(
            view: shell,
            deprecatedDoNotUseWillBeRemovedWithoutNoticePipelineOwner:
                lazy(shell).pipelineOwner,
            deprecatedDoNotUseWillBeRemovedWithoutNoticeRenderView:
                lazy(shell).renderView,
            child: PangolinApp(
              transparent: true,
              navigatorKey: shellNavigatorKey,
              navigatorObservers: [_shellRoutes],
              child: const SessionCommands(child: ShellSurface()),
            ),
          ),
        for (final FlutterView view in lockViews)
          View(
            key: ValueKey(view.viewId),
            view: view,
            deprecatedDoNotUseWillBeRemovedWithoutNoticePipelineOwner:
                lazy(view).pipelineOwner,
            deprecatedDoNotUseWillBeRemovedWithoutNoticeRenderView:
                lazy(view).renderView,
            child: const PangolinApp(child: LockScreen()),
          ),
      ],
    );
  }
}

/// Render tree root of a session surface that only sends a frame to the
/// engine when something in the surface changed.
///
/// Flutter composites every view on every frame: without this, a clock tick
/// or a hover effect on the taskbar would also redraw the full-screen
/// wallpaper surface (and the other way around), which at 4K with fractional
/// scaling means rendering two 5K surfaces per frame.
class _LazyView {
  _LazyView(this.view) {
    pipelineOwner = _LazyPipelineOwner(
      onSemanticsUpdate: view.updateSemantics,
      onSemanticsOwnerCreated: () => renderView.scheduleInitialSemantics(),
      onSemanticsOwnerDisposed: () => renderView.clearSemantics(),
    );
    renderView = _LazyRenderView(view: view, pipeline: pipelineOwner);
  }

  final FlutterView view;
  late final _LazyPipelineOwner pipelineOwner;
  late final _LazyRenderView renderView;
}

final class _LazyPipelineOwner extends PipelineOwner {
  _LazyPipelineOwner({
    super.onSemanticsOwnerCreated,
    super.onSemanticsUpdate,
    super.onSemanticsOwnerDisposed,
  });

  /// Whether a render object of the view asked for a new frame (layout,
  /// paint, compositing or semantics) since the view was last composited.
  bool dirty = true;

  @override
  void requestVisualUpdate() {
    dirty = true;
    super.requestVisualUpdate();
  }
}

class _LazyRenderView extends RenderView {
  _LazyRenderView({required super.view, required this.pipeline});

  final _LazyPipelineOwner pipeline;

  @override
  void compositeFrame() {
    if (!pipeline.dirty) return;
    pipeline.dirty = false;
    super.compositeFrame();
  }
}

/// Claims the whole shell surface while a dialog or other popup route is
/// shown on it.
class ShellModalRouteObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _popups = {};

  void _update() => ShellInputRegion.instance.claim(this, _popups.isNotEmpty);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _popups.add(route);
    _update();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _popups.remove(route);
    _update();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _popups.remove(route);
    _update();
  }
}
