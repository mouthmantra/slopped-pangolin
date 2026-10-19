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
import 'dart:math';

import 'package:animations/animations.dart';
import 'package:dahlia_shared/dahlia_shared.dart';
import 'package:flutter/rendering.dart';
import 'package:pangolin/widgets/surface/popup_transition.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_account_page.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_bluetooth_page.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_language_page.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_network_page.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_theme_page.dart';
import 'package:pangolin/components/overlays/quick_settings/pages/qs_vpn_page.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_media_card.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_slider.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_toggle_button.dart';
import 'package:pangolin/components/overlays/quick_settings/widgets/qs_tray_item.dart';
import 'package:pangolin/services/bluetooth.dart';
import 'package:pangolin/services/date_time.dart';
import 'package:pangolin/services/power.dart';
import 'package:pangolin/services/privacy.dart';
import 'package:pangolin_settings/pangolin_settings.dart';
import 'package:pangolin/services/display_power.dart';
import 'package:pangolin/services/hardware_controls.dart';
import 'package:pangolin/components/shell/screenshot.dart';
import 'package:pangolin/services/session.dart';
import 'package:pangolin/services/shell.dart';
import 'package:pangolin/services/tray.dart';
import 'package:pangolin/services/vpn.dart';
import 'package:pangolin/services/wifi.dart';
import 'package:pangolin/services/wm.dart';
import 'package:pangolin/utils/action_manager/action_manager.dart';
import 'package:pangolin/utils/data/globals.dart';
import 'package:pangolin/widgets/battery_indicator.dart';
import 'package:pangolin/widgets/quick_button.dart';
import 'package:pangolin/widgets/surface/surface_layer.dart';
import 'package:provider/provider.dart';
import 'package:yatl_flutter/yatl_flutter.dart';
import 'package:zenit_ui/zenit_ui.dart';

class QuickSettingsOverlay extends ShellOverlay {
  static const String overlayId = 'quicksettings';

  QuickSettingsOverlay({super.key}) : super(id: overlayId);

  @override
  _QuickSettingsOverlayState createState() => _QuickSettingsOverlayState();
}

enum _TransitionDirection {
  forward(false),
  reverse(true);

  final bool value;

  const _TransitionDirection(this.value);
}

class _QuickSettingsOverlayState
    extends ShellOverlayState<QuickSettingsOverlay> {
  static const Map<String, Widget> routes = {
    '/': QsMain(),
    '/pages/account': QsAccountPage(),
    '/pages/network': QsNetworkPage(),
    '/pages/theme': QsThemePage(),
    '/pages/language': QsLanguagePage(),
    '/pages/vpn': QsVpnPage(),
    '/pages/bluetooth': QsBluetoothPage(),
  };

  late final QsControllerState qsController = QsControllerState._(this);

  @override
  Future<void> requestShow(Map<String, dynamic> args) async {
    routeStack = ['/'];
    controller.showing = true;
    await animationController.forward();
  }

  @override
  Future<void> requestDismiss(Map<String, dynamic> args) async {
    controller.showing = false;
    await animationController.reverse();
  }

  void pushRoute(String name) {
    direction = _TransitionDirection.forward;
    routeStack.add(name);
    setState(() {});
    qsController._notify();
  }

  void popRoute() {
    if (!canPop()) return;
    direction = _TransitionDirection.reverse;
    routeStack.removeLast();
    setState(() {});
    qsController._notify();
  }

  bool canPop() {
    return routeStack.length > 1;
  }

  List<String> routeStack = ['/'];
  _TransitionDirection direction = _TransitionDirection.forward;

  @override
  Widget build(BuildContext context) {
    if (shouldHide) return const SizedBox();

    return Positioned(
      bottom: PangolinSession.taskbarHeight + 8.0,
      right: WindowManagerService.current.controller.wmInsets.right + 8,
      child: PopupTransition(
        animation: animation,
        showing: controller.showing,
        alignment: const FractionalOffset(0.8, 1.0),
        margin: const EdgeInsets.fromLTRB(24, 24, 8, 8),
        child: SurfaceLayer(
          shape: Constants.bigShape,
          width: 524,
          dropShadow: true,
          outline: true,
          child: AnimatedSize(
            duration: Constants.animationDuration,
            curve: Constants.animationCurve,
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            child: ChangeNotifierProvider<QsControllerState>.value(
              value: qsController,
              child: PageTransitionSwitcher(
                reverse: direction.value,
                transitionBuilder: (child, primary, secondary) {
                  return SharedAxisTransition(
                    animation: primary,
                    secondaryAnimation: secondary,
                    transitionType: SharedAxisTransitionType.horizontal,
                    fillColor: Colors.transparent,
                    child: Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                  );
                },
                layoutBuilder: (entries) {
                  return _FixedSizeTransitionStack(
                    reverseDirection: direction.value,
                    fallbackSize: const Size(524, 460),
                    children: entries,
                  );
                },
                child: Padding(
                  key: ValueKey(routeStack.last),
                  padding: const EdgeInsets.all(16.0),
                  child: routes[routeStack.last],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QsMain extends StatefulWidget {
  const QsMain({super.key});

  @override
  State<QsMain> createState() => _QsMainState();
}

class _QsMainState extends State<QsMain>
    with StateServiceListener<CustomizationService, QsMain> {
  bool showTray = false;

  /// Quick controls in edit mode (moving, adding, removing them).
  final ValueNotifier<bool> _editingControls = ValueNotifier(false);

  @override
  void dispose() {
    _editingControls.dispose();
    super.dispose();
  }

  @override
  Widget buildChild(BuildContext context, CustomizationService service) {
    // Action Button Bar
    final List<Widget> qsActionButton = [
      QuickActionButton(
        leading: const Icon(Icons.account_circle_rounded, size: 20),
        title: username,
        onPressed: () => QsController.pushRoute(context, "/pages/account"),
        margin: EdgeInsets.zero,
        textStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).foregroundColor,
        ),
      ),
      const Spacer(),
      // Editing the controls and Settings, side by side and flush with the
      // panel's edge like the account button on the other side.
      ValueListenableBuilder<bool>(
        valueListenable: _editingControls,
        builder: (context, editing, _) => Tooltip(
          message: editing ? "Done" : "Edit quick controls",
          child: _HeaderButton(
            icon: editing ? Icons.check_rounded : Icons.edit_outlined,
            highlighted: editing,
            onPressed: () => _editingControls.value = !editing,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Tooltip(
        message: "Settings",
        child: _HeaderButton(
          icon: Icons.settings_outlined,
          onPressed: () => ActionManager.openSettings(context),
        ),
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: qsActionButton,
            ),
            const _PrivacyRow(),
            _QuickControls(
              editing: _editingControls,
              title: strings.quicksettingsOverlay.quickControls,
              builder: (context, control) =>
                  _control(context, control, service),
            ),
            ListenableServiceBuilder<TrayService>(
              builder: (context, _) {
                final items = TrayService.current.items;

                if (items.isEmpty) return const SizedBox();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _qsTitle("Tray icons"),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: items
                          .map(
                            (e) => QsTrayMenuItem(item: e),
                          )
                          .toList(),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: Listenable.merge([
                VolumeControl.instance,
                BrightnessControl.instance,
              ]),
              builder: (context, _) {
                final VolumeControl volume = VolumeControl.instance;
                final BrightnessControl brightness = BrightnessControl.instance;
                return Column(
                  children: [
                    QsSlider(
                      icon: volume.muted || volume.volume == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      onChanged: volume.setVolume,
                      value: volume.muted ? 0 : volume.volume.clamp(0.0, 1.0),
                      onIconTap: () => volume.setMuted(!volume.muted),
                      onMore: () =>
                          ActionManager.openSettings(context, page: "sound"),
                    ),
                    if (brightness.available) ...[
                      const SizedBox(height: 8),
                      QsSlider(
                        icon: Icons.brightness_6_rounded,
                        onChanged: brightness.setBrightness,
                        value: brightness.brightness,
                        onMore: () => ActionManager.openSettings(
                          context,
                          page: "displays",
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const QsMediaCard(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ListenableServiceBuilder<DateTimeService>(
                  builder: (BuildContext context, _) {
                    final String date = DateTimeService.current.formattedDate;
                    final String time = DateTimeService.current.formattedTime;

                    return QuickActionButton(
                      leading: const Icon(Icons.calendar_today),
                      title: "$date - $time",
                      margin: EdgeInsets.zero,
                    );
                  },
                ),
                if (PowerService.current.hasBattery)
                  PowerServiceBuilder(
                    builder:
                        (context, child, percentage, charging, powerSaver) {
                      return QuickActionButton(
                        leading: BatteryIndicator(
                          percentage: percentage,
                          charging: charging,
                          powerSaving: powerSaver,
                        ),
                        title: "$percentage %",
                        margin: EdgeInsets.zero,
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The tile of [control].
  Widget _control(
    BuildContext context,
    QuickControl control,
    CustomizationService service,
  ) {
    switch (control) {
      case QuickControl.vpn:
        return const _VpnTile();
      case QuickControl.network:
        // NetworkManager's Wi-Fi: on/off, the connected network, the
        // networks page.
        return ListenableBuilder(
          listenable: WifiService.instance,
          builder: (context, _) {
            final WifiService wifi = WifiService.instance;
            return QsToggleButton(
              title: ToggleProperty.singleState(
                strings.quicksettingsOverlay.quickControlsNetworkTitle,
              ),
              icon: const ToggleProperty(
                base: Icons.wifi_off_rounded,
                active: Icons.wifi_rounded,
              ),
              subtitle: ToggleProperty(
                base: strings.global.off,
                active: wifi.connected?.ssid ?? strings.global.on,
              ),
              enabled: wifi.enabled,
              onPressed: (value) => unawaited(wifi.setEnabled(value)),
              onMenuPressed: () {
                QsController.pushRoute(context, "/pages/network");
              },
            );
          },
        );
      case QuickControl.bluetooth:
        // BlueZ's adapter: on/off, the connected device, the devices page.
        return ListenableBuilder(
          listenable: BluetoothService.instance,
          builder: (context, _) {
            final BluetoothService bt = BluetoothService.instance;
            final List<BluetoothDevice> connected = bt.connected;
            return QsToggleButton(
              title: ToggleProperty.singleState(
                strings.quicksettingsOverlay.quickControlsBluetoothTitle,
              ),
              subtitle: ToggleProperty(
                base: strings.global.off,
                active: connected.isNotEmpty
                    ? connected.first.name
                    : strings.global.on,
              ),
              icon: ToggleProperty(
                base: Icons.bluetooth_disabled_rounded,
                active: connected.isNotEmpty
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_rounded,
              ),
              enabled: bt.powered,
              onPressed: (value) => unawaited(bt.setPowered(value)),
              onMenuPressed: () =>
                  QsController.pushRoute(context, "/pages/bluetooth"),
            );
          },
        );
      case QuickControl.airplaneMode:
        return QsToggleButton(
          title: ToggleProperty.singleState(
            strings.quicksettingsOverlay.quickControlsAirplaneModeTitle,
          ),
          icon: const ToggleProperty(
            base: Icons.airplanemode_off_rounded,
            active: Icons.airplanemode_active_rounded,
          ),
          enabled: service.enableAirplaneMode,
          onPressed: (value) {
            service.enableAirplaneMode = value;
            unawaited(AirplaneMode.set(on: value));
          },
        );
      case QuickControl.language:
        return QsToggleButton(
          title: ToggleProperty.singleState(
            strings.quicksettingsOverlay.quickControlsLanguageTitle,
          ),
          //TODO Fix this
          subtitle: ToggleProperty.singleState(
            context.locale.toLanguageTag(),
          ),
          icon: const ToggleProperty.singleState(
            Icons.language_rounded,
          ),
          enabled: true,
          onPressed: (_) {
            final int index = context.supportedLocales.indexOf(context.locale);
            if (index + 1 < locales.supportedLocales.length) {
              context.locale = context.supportedLocales[index + 1];
            } else {
              context.locale = context.supportedLocales[0];
            }
          },
          onMenuPressed: () {
            QsController.pushRoute(context, "/pages/language");
          },
        );
      case QuickControl.theme:
        return QsToggleButton(
          title: ToggleProperty.singleState(
            strings.quicksettingsOverlay.quickControlsThemeTitle,
          ),
          // Highlighted in dark mode, which it switches.
          subtitle: const ToggleProperty(base: "Light", active: "Dark"),
          icon: const ToggleProperty(
            base: Icons.light_mode_outlined,
            active: Icons.dark_mode_rounded,
          ),
          enabled: service.darkMode,
          onPressed: (dark) => service.darkMode = dark,
          onMenuPressed: () => QsController.pushRoute(context, "/pages/theme"),
        );
      case QuickControl.doNotDisturb:
        return _setting(
          SessionSetting.doNotDisturb,
          (dnd, set) => QsToggleButton(
            title: ToggleProperty.singleState(
              strings.quicksettingsOverlay.quickControlsDonotdisturbTitle,
            ),
            subtitle: ToggleProperty(
              base: strings.global.off,
              active: strings.global.on,
            ),
            icon: const ToggleProperty(
              base: Icons.do_not_disturb_off_rounded,
              active: Icons.do_not_disturb_on_rounded,
            ),
            enabled: dnd,
            onPressed: set,
          ),
        );
      case QuickControl.nightShift:
        return _setting(
          SessionSetting.nightShift,
          (on, set) => ListenableBuilder(
            listenable: DisplayPower.instance,
            builder: (context, _) => QsToggleButton(
              title: const ToggleProperty.singleState(
                "Night Shift",
              ),
              subtitle: ToggleProperty(
                base: strings.global.off,
                active: _nightShiftSubtitle(),
              ),
              icon: const ToggleProperty(
                base: Icons.nightlight_outlined,
                active: Icons.nightlight_rounded,
              ),
              enabled: on,
              onPressed: set,
            ),
          ),
        );
      case QuickControl.screenshot:
        return QsToggleButton(
          title: const ToggleProperty.singleState("Screenshot"),
          icon: const ToggleProperty.singleState(
            Icons.screenshot_monitor_rounded,
          ),
          enabled: false,
          onPressed: (_) => ScreenshotTool.open(),
        );
      case QuickControl.lock:
        return QsToggleButton(
          title: const ToggleProperty.singleState("Lock"),
          icon: const ToggleProperty.singleState(
            Icons.lock_outline_rounded,
          ),
          enabled: false,
          onPressed: (_) => ActionManager.lock(),
        );
    }
  }

  /// A boolean session setting, rebuilt when it changes.
  Widget _setting(
    SessionSetting<bool> setting,
    Widget Function(bool value, ValueChanged<bool> set) builder,
  ) {
    final PreferencesService prefs = PreferencesService.current;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => builder(
        prefs.get<bool>(setting.key) ?? setting.defaultValue,
        (value) => prefs.set<bool>(setting.key, value),
      ),
    );
  }

  /// "Until 07:00" while active on a schedule, "From 20:00" before.
  String _nightShiftSubtitle() {
    final PreferencesService prefs = PreferencesService.current;
    T get<T extends Object>(SessionSetting<T> s) =>
        prefs.get<T>(s.key) ?? s.defaultValue;
    if (!get(SessionSetting.nightShiftScheduled)) return strings.global.on;
    String format(int minutes) =>
        "${(minutes ~/ 60).toString().padLeft(2, "0")}:"
        "${(minutes % 60).toString().padLeft(2, "0")}";
    return DisplayPower.instance.nightShiftActive
        ? "Until ${format(get(SessionSetting.nightShiftTo))}"
        : "From ${format(get(SessionSetting.nightShiftFrom))}";
  }

  Padding _qsTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4.0, 12.0, 0.0, 12.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

final class QsController {
  const QsController._();

  static void pushRoute(
    BuildContext context,
    String name, {
    bool listen = false,
  }) {
    final controller = QsController.of(context, listen: listen);
    controller.pushRoute(name);
  }

  static void popRoute(BuildContext context, {bool listen = false}) {
    final controller = QsController.of(context, listen: listen);
    controller.popRoute();
  }

  static bool canPop(BuildContext context, {bool listen = false}) {
    final controller = QsController.of(context, listen: listen);
    return controller.canPop();
  }

  static QsControllerState of(BuildContext context, {bool listen = true}) {
    return Provider.of<QsControllerState>(context, listen: listen);
  }
}

class QsControllerState with ChangeNotifier {
  final _QuickSettingsOverlayState _state;

  QsControllerState._(this._state);

  void pushRoute(String name) => _state.pushRoute(name);
  void popRoute() => _state.popRoute();
  bool canPop() => _state.canPop();

  void _notify() => notifyListeners();
}

class _FixedSizeTransitionStack extends MultiChildRenderObjectWidget {
  final bool reverseDirection;
  final Size fallbackSize;

  const _FixedSizeTransitionStack({
    required super.children,
    this.reverseDirection = false,
    required this.fallbackSize,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderFixedSizeTransitionStack(
      alignment: Alignment.bottomCenter,
      textDirection: Directionality.of(context),
      reverseDirection: reverseDirection,
      fallbackSize: fallbackSize,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFixedSizeTransitionStack renderObject,
  ) {
    renderObject
      ..alignment = Alignment.bottomCenter
      ..textDirection = Directionality.of(context)
      ..reverseDirection = reverseDirection
      ..fallbackSize = fallbackSize;
  }
}

class _RenderFixedSizeTransitionStack extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, StackParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, StackParentData> {
  _RenderFixedSizeTransitionStack({
    List<RenderBox>? children,
    AlignmentGeometry alignment = AlignmentDirectional.topStart,
    TextDirection? textDirection,
    bool reverseDirection = false,
    Size fallbackSize = Size.zero,
  })  : _alignment = alignment,
        _textDirection = textDirection,
        _reverseDirection = reverseDirection,
        _fallbackSize = fallbackSize {
    addAll(children);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! StackParentData) {
      child.parentData = StackParentData();
    }
  }

  AlignmentGeometry get alignment => _alignment;
  AlignmentGeometry _alignment;
  set alignment(AlignmentGeometry value) {
    if (_alignment == value) {
      return;
    }
    _alignment = value;
    _markNeedResolution();
  }

  TextDirection? get textDirection => _textDirection;
  TextDirection? _textDirection;
  set textDirection(TextDirection? value) {
    if (_textDirection == value) {
      return;
    }
    _textDirection = value;
    _markNeedResolution();
  }

  bool get reverseDirection => _reverseDirection;
  bool _reverseDirection;
  set reverseDirection(bool value) {
    if (_reverseDirection == value) {
      return;
    }
    _reverseDirection = value;
    markNeedsLayout();
  }

  Size get fallbackSize => _fallbackSize;
  Size _fallbackSize;
  set fallbackSize(Size value) {
    if (_fallbackSize == value) {
      return;
    }
    _fallbackSize = value;
    markNeedsLayout();
  }

  void _markNeedResolution() {
    _resolvedAlignment = null;
    markNeedsLayout();
  }

  Alignment? _resolvedAlignment;

  void _resolve() {
    if (_resolvedAlignment != null) {
      return;
    }
    _resolvedAlignment = alignment.resolve(textDirection);
  }

  RenderBox? get startChild => reverseDirection ? firstChild : lastChild;

  static double getIntrinsicDimension(
    RenderBox? childToMeasure,
    double Function(RenderBox child) mainChildSizeGetter,
  ) {
    double extent = 0.0;
    final child = childToMeasure;
    if (child != null) {
      final StackParentData childParentData =
          child.parentData! as StackParentData;
      extent = mainChildSizeGetter(child);
      assert(child.parentData == childParentData);
    }
    return extent;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    return getIntrinsicDimension(
      startChild,
      (RenderBox child) => child.getMinIntrinsicWidth(height),
    );
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return getIntrinsicDimension(
      startChild,
      (RenderBox child) => child.getMaxIntrinsicWidth(height),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return getIntrinsicDimension(
      startChild,
      (RenderBox child) => child.getMinIntrinsicHeight(width),
    );
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return getIntrinsicDimension(
      startChild,
      (RenderBox child) => child.getMaxIntrinsicHeight(width),
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return defaultComputeDistanceToHighestActualBaseline(baseline);
  }

  Size _computeSize({
    required BoxConstraints constraints,
    required ChildLayouter layoutChild,
  }) {
    _resolve();
    assert(_resolvedAlignment != null);
    if (childCount == 0) {
      return (constraints.biggest.isFinite)
          ? constraints.biggest
          : constraints.smallest;
    }

    double width = constraints.minWidth;
    double height = constraints.minHeight;

    final BoxConstraints nonPositionedConstraints = constraints.loosen();

    RenderBox? child = startChild;
    int i = 0;
    while (child != null) {
      final StackParentData childParentData =
          child.parentData! as StackParentData;

      if (!childParentData.isPositioned) {
        final Size childSize = layoutChild(child, nonPositionedConstraints);

        if (i == 0) {
          width = max(width, childSize.width);
          height = max(height, childSize.height);
        }
      }

      child = reverseDirection
          ? childParentData.nextSibling
          : childParentData.previousSibling;
      i++;
    }

    final Size size = Size(width, height);
    assert(size.width == constraints.constrainWidth(width));
    assert(size.height == constraints.constrainHeight(height));

    assert(size.isFinite);

    return size;
  }

  @override
  void performLayout() {
    final BoxConstraints constraints = this.constraints;

    size = _computeSize(
      constraints: constraints,
      layoutChild: (box, constraints) {
        final size = box.getDryLayout(constraints);

        final unboundedWidth = size.width == double.infinity &&
            constraints.maxWidth == double.infinity;
        final unboundedHeight = size.height == double.infinity &&
            constraints.maxHeight == double.infinity;

        final BoxConstraints newConstraints;
        if (unboundedWidth || unboundedHeight) {
          newConstraints = BoxConstraints(
            minWidth: constraints.minWidth,
            maxWidth:
                unboundedWidth ? fallbackSize.width : constraints.maxWidth,
            minHeight: constraints.minHeight,
            maxHeight:
                unboundedHeight ? fallbackSize.height : constraints.maxHeight,
          );
        } else {
          newConstraints = constraints;
        }
        box.layout(newConstraints, parentUsesSize: true);

        return box.size;
      },
    );

    assert(_resolvedAlignment != null);
    RenderBox? child = firstChild;
    while (child != null) {
      final StackParentData childParentData =
          child.parentData! as StackParentData;

      if (!childParentData.isPositioned) {
        childParentData.offset =
            _resolvedAlignment!.alongOffset(size - child.size as Offset);
      } else {
        layoutPositionedChild(
          child,
          childParentData,
          size,
          _resolvedAlignment!,
        );
      }

      assert(child.parentData == childParentData);
      child = childParentData.nextSibling;
    }
  }

  static bool layoutPositionedChild(
    RenderBox child,
    StackParentData childParentData,
    Size size,
    Alignment alignment,
  ) {
    assert(childParentData.isPositioned);
    assert(child.parentData == childParentData);

    bool hasVisualOverflow = false;
    BoxConstraints childConstraints = const BoxConstraints();

    if (childParentData.left != null && childParentData.right != null) {
      childConstraints = childConstraints.tighten(
        width: size.width - childParentData.right! - childParentData.left!,
      );
    } else if (childParentData.width != null) {
      childConstraints = childConstraints.tighten(width: childParentData.width);
    }

    if (childParentData.top != null && childParentData.bottom != null) {
      childConstraints = childConstraints.tighten(
        height: size.height - childParentData.bottom! - childParentData.top!,
      );
    } else if (childParentData.height != null) {
      childConstraints =
          childConstraints.tighten(height: childParentData.height);
    }

    child.layout(childConstraints, parentUsesSize: true);

    final double x;
    if (childParentData.left != null) {
      x = childParentData.left!;
    } else if (childParentData.right != null) {
      x = size.width - childParentData.right! - child.size.width;
    } else {
      x = alignment.alongOffset(size - child.size as Offset).dx;
    }

    if (x < 0.0 || x + child.size.width > size.width) {
      hasVisualOverflow = true;
    }

    final double y;
    if (childParentData.top != null) {
      y = childParentData.top!;
    } else if (childParentData.bottom != null) {
      y = size.height - childParentData.bottom! - child.size.height;
    } else {
      y = alignment.alongOffset(size - child.size as Offset).dy;
    }

    if (y < 0.0 || y + child.size.height > size.height) {
      hasVisualOverflow = true;
    }

    childParentData.offset = Offset(x, y);

    return hasVisualOverflow;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _computeSize(
      constraints: constraints,
      layoutChild: ChildLayoutHelper.dryLayoutChild,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}

/// VPN: on or off (the one used last), the list behind the arrow. Only
/// there when VPN connections are set up.
class _VpnTile extends StatelessWidget {
  const _VpnTile();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: VpnService.instance,
      builder: (context, _) {
        final VpnService vpn = VpnService.instance;
        if (!vpn.available || vpn.connections.isEmpty) {
          return const SizedBox.shrink();
        }
        final VpnConnection? current = vpn.current;
        final bool connecting =
            current != null && vpn.stateOf(current) == VpnState.connecting;
        return QsToggleButton(
          title: const ToggleProperty.singleState("VPN"),
          subtitle: ToggleProperty(
            base: strings.global.off,
            active: connecting ? "Connecting…" : current?.name,
          ),
          icon: const ToggleProperty(
            base: Icons.vpn_key_off_outlined,
            active: Icons.vpn_key_rounded,
          ),
          enabled: current != null,
          onPressed: (on) {
            final VpnConnection? target = on ? vpn.preferred : current;
            if (target != null) unawaited(vpn.toggle(target));
          },
          onMenuPressed: () => QsController.pushRoute(context, "/pages/vpn"),
        );
      },
    );
  }
}

/// Apps recording the screen, the microphone or the camera, in the colors
/// of the taskbar's indicators.
class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow();

  static const Map<PrivacyUse, IconData> _icons = {
    PrivacyUse.screen: Icons.screen_share_rounded,
    PrivacyUse.microphone: Icons.mic_rounded,
    PrivacyUse.camera: Icons.videocam_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PrivacyMonitor.instance,
      builder: (context, _) {
        final Map<PrivacyUse, Set<String>> uses = PrivacyMonitor.instance.uses;
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: uses.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final PrivacyUse use in PrivacyUse.values)
                        if (uses[use]?.isNotEmpty == true)
                          _PrivacyChip(
                            use: use,
                            icon: _icons[use]!,
                            apps: uses[use]!,
                          ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  const _PrivacyChip({
    required this.use,
    required this.icon,
    required this.apps,
  });

  final PrivacyUse use;
  final IconData icon;
  final Set<String> apps;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: use.color.withValues(alpha: 0.16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: ShapeDecoration(
              shape: const CircleBorder(),
              color: use.color,
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              "${use.label} · ${apps.join(", ")}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tiles Quick Settings can show (see [SessionSetting.quickControls]).
enum QuickControl {
  network("network", "Network", Icons.wifi_rounded),
  vpn("vpn", "VPN", Icons.vpn_key_rounded),
  bluetooth("bluetooth", "Bluetooth", Icons.bluetooth_rounded),
  airplaneMode(
    "airplane_mode",
    "Airplane mode",
    Icons.airplanemode_active_rounded,
  ),
  doNotDisturb(
    "do_not_disturb",
    "Do not disturb",
    Icons.do_not_disturb_on_rounded,
  ),
  nightShift("night_shift", "Night Shift", Icons.nightlight_rounded),
  theme("theme", "Theme", Icons.dark_mode_outlined),
  language("language", "Language", Icons.language_rounded),
  screenshot("screenshot", "Screenshot", Icons.screenshot_monitor_rounded),
  lock("lock", "Lock", Icons.lock_outline_rounded);

  const QuickControl(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;

  /// The controls shown, in order, from the setting's value.
  static List<QuickControl> parse(String value) {
    final List<QuickControl> controls = [];
    for (final String id in value.split(",")) {
      final QuickControl? control =
          values.where((c) => c.id == id.trim()).firstOrNull;
      if (control != null && !controls.contains(control)) {
        controls.add(control);
      }
    }
    return controls;
  }
}

/// The quick controls, and their edit mode: drag them around, remove them,
/// add the others back.
class _QuickControls extends StatefulWidget {
  const _QuickControls({
    required this.editing,
    required this.title,
    required this.builder,
  });

  /// Edit mode, switched by the button next to Settings.
  final ValueNotifier<bool> editing;
  final String title;
  final Widget Function(BuildContext context, QuickControl control) builder;

  @override
  State<_QuickControls> createState() => _QuickControlsState();
}

class _QuickControlsState extends State<_QuickControls> {
  bool get _editing => widget.editing.value;

  @override
  void initState() {
    super.initState();
    widget.editing.addListener(_onEditing);
  }

  @override
  void dispose() {
    widget.editing.removeListener(_onEditing);
    super.dispose();
  }

  void _onEditing() => setState(() => _order = _editing ? _saved : null);

  /// The order while editing (saved as it changes).
  List<QuickControl>? _order;

  PreferencesService get _prefs => PreferencesService.current;

  List<QuickControl> get _saved => QuickControl.parse(
        _prefs.get<String>(SessionSetting.quickControls.key) ??
            SessionSetting.quickControls.defaultValue,
      );

  void _save(List<QuickControl> order) {
    setState(() => _order = order);
    _prefs.set<String>(
      SessionSetting.quickControls.key,
      order.map((c) => c.id).join(","),
    );
  }

  void _move(QuickControl control, QuickControl before) {
    final List<QuickControl> order = [...?_order];
    if (control == before) return;
    order.remove(control);
    order.insert(order.indexOf(before), control);
    _save(order);
  }

  void _remove(QuickControl control) => _save([...?_order]..remove(control));

  void _add(QuickControl control) {
    final List<QuickControl> order = [...?_order];
    if (!order.contains(control)) _save(order..add(control));
  }

  static bool _available(QuickControl control) => switch (control) {
        QuickControl.vpn => VpnService.instance.available &&
            VpnService.instance.connections.isNotEmpty,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_prefs, VpnService.instance]),
      builder: (context, _) {
        final List<QuickControl> order =
            _editing ? (_order ??= _saved) : _saved;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? "Edit quick controls" : widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _editing
                  ? _editor(context, theme, order)
                  : Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      children: [
                        for (final QuickControl c in order)
                          if (_available(c)) widget.builder(context, c),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _editor(
    BuildContext context,
    ThemeData theme,
    List<QuickControl> order,
  ) {
    final List<QuickControl> hidden = [
      for (final QuickControl c in QuickControl.values)
        if (!order.contains(c)) c,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 8,
          children: [
            for (final QuickControl c in order)
              DragTarget<QuickControl>(
                key: ValueKey(c),
                onWillAcceptWithDetails: (details) {
                  // Placed ones make room as the dragged one passes by;
                  // others come in where they're dropped.
                  if (order.contains(details.data)) _move(details.data, c);
                  return true;
                },
                onAcceptWithDetails: (details) {
                  if (!order.contains(details.data)) {
                    final List<QuickControl> next = [...order]
                      ..insert(order.indexOf(c), details.data);
                    _save(next);
                  }
                },
                builder: (context, _, __) => _draggable(
                  c,
                  _EditTile(
                    control: c,
                    removable: true,
                    onBadge: () => _remove(c),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            hidden.isEmpty
                ? "Drag the controls to move them"
                : "Drag the controls to move them, or here to remove them",
            style: TextStyle(
              fontSize: 12,
              color: theme.foregroundColor.withValues(alpha: 0.7),
            ),
          ),
        ),
        // Dropping a placed control here removes it.
        DragTarget<QuickControl>(
          onWillAcceptWithDetails: (details) => order.contains(details.data),
          onAcceptWithDetails: (details) => _remove(details.data),
          builder: (context, candidates, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.foregroundColor
                  .withValues(alpha: candidates.isNotEmpty ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              children: [
                for (final QuickControl c in hidden)
                  _draggable(
                    c,
                    _EditTile(
                      control: c,
                      removable: false,
                      onBadge: () => _add(c),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _draggable(QuickControl control, Widget tile) {
    return Draggable<QuickControl>(
      data: control,
      feedback: Material(
        type: MaterialType.transparency,
        child: Opacity(opacity: 0.9, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: tile),
    );
  }
}

/// A control in edit mode: its icon and name, and a badge to remove it
/// (or add it).
class _EditTile extends StatelessWidget {
  const _EditTile({
    required this.control,
    required this.removable,
    required this.onBadge,
  });

  final QuickControl control;
  final bool removable;
  final VoidCallback onBadge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = removable ? theme.primaryColor : theme.surfaceColor;
    final Color foreground = theme.computedForegroundColor(color);
    return SizedBox(
      width: 160,
      height: 56,
      child: Material(
        color: color,
        shape: Constants.mediumShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onBadge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(control.icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    control.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
                Container(
                  width: 24,
                  height: 24,
                  decoration: ShapeDecoration(
                    shape: const CircleBorder(),
                    color: foreground.withValues(alpha: 0.16),
                  ),
                  child: Icon(
                    removable ? Icons.remove_rounded : Icons.add_rounded,
                    size: 16,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round button of the panel's top row (edit, Settings): the same size,
/// icon size and fill, so that they line up.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.onPressed,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fill =
        highlighted ? theme.colorScheme.primary : theme.surfaceColor;
    return SizedBox.square(
      dimension: 40,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: highlighted
                  ? theme.colorScheme.onPrimary
                  : theme.foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
