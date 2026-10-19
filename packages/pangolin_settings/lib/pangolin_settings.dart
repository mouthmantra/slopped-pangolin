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

/// Settings of the Pangolin session that are not part of dahlia_shared's
/// `Preference` enum. They live in the same `pangolin` dsettings table.
///
/// The table has a scheme and dsettings silently drops batch writes to keys
/// that are not in it, so the shell (the table owner) registers these keys
/// alongside dahlia_shared's through [sessionScheme].
library;

import 'package:dsettings/dsettings.dart';

enum SessionSetting<T extends Object> {
  /// The default taskbar pins were applied on the first session start.
  defaultPinsApplied<bool>("session_default_pins_applied", false),

  /// Comma separated XKB layouts, e.g. "us,de". The first one is active.
  keyboardLayouts<String>("keyboard_layouts", "us"),

  /// XKB variants matching [keyboardLayouts], comma separated.
  keyboardVariants<String>("keyboard_variants", ""),

  /// XKB options, e.g. "grp:alt_shift_toggle,caps:escape".
  keyboardOptions<String>("keyboard_options", "grp:alt_shift_toggle"),

  /// Key repeats per second.
  keyRepeatRate<int>("key_repeat_rate", 25),

  /// Delay before keys start repeating, in milliseconds.
  keyRepeatDelay<int>("key_repeat_delay", 600),

  /// Touchpad tap-to-click.
  tapToClick<bool>("touchpad_tap_to_click", true),

  /// Natural (reversed) scrolling for touchpads.
  naturalScroll<bool>("touchpad_natural_scroll", true),

  /// Disable the touchpad while typing.
  disableWhileTyping<bool>("touchpad_disable_while_typing", true),

  /// Mouse pointer speed in [-1, 1] (the key predates the separate touchpad
  /// speed, when it applied to both).
  pointerSpeed<double>("pointer_speed", 0.0),

  /// Touchpad pointer speed in [-1, 1].
  touchpadSpeed<double>("touchpad_speed", 0.0),

  /// Mouse acceleration (libinput's adaptive profile); off moves the pointer
  /// in proportion to the mouse (flat profile).
  mouseAcceleration<bool>("mouse_acceleration", true),

  /// Touchpad acceleration (adaptive profile); off is flat.
  touchpadAcceleration<bool>("touchpad_acceleration", true),

  /// Natural (reversed) scrolling for mice.
  mouseNaturalScroll<bool>("mouse_natural_scroll", false),

  /// Swap the primary and secondary buttons (mice and touchpads).
  leftHanded<bool>("pointer_left_handed", false),

  /// The touchpad: "enabled", "disabled", or "external_mouse" (off while a
  /// mouse is connected).
  touchpadMode<String>("touchpad_mode", "enabled"),

  /// Hot corners: what pushing the pointer into each corner of the screen
  /// does (a [GestureAction] value; "none" for nothing).
  hotCornerTopLeft<String>("hot_corner_top_left", "overview"),
  hotCornerTopRight<String>("hot_corner_top_right", "none"),
  hotCornerBottomLeft<String>("hot_corner_bottom_left", "none"),
  hotCornerBottomRight<String>("hot_corner_bottom_right", "none"),

  /// Show seconds in the taskbar clock.
  clockShowSeconds<bool>("clock_show_seconds", true),

  /// Use the 24 hour format in the taskbar clock.
  clock24Hour<bool>("clock_24_hour", true),

  /// Font family of the shell and dahliaOS apps; empty for the default
  /// (Inter).
  interfaceFont<String>("interface_font", ""),

  /// Monospace font family (terminal, text editor, logs); empty for the
  /// system's monospace font.
  monospaceFont<String>("monospace_font", ""),

  /// Animate windows opening, closing, minimizing and changing size.
  windowAnimations<bool>("window_animations", true),

  /// Create and remove virtual desktops automatically, always keeping one
  /// empty desktop at the end (GNOME style), instead of a fixed set.
  dynamicDesktops<bool>("dynamic_desktops", false),

  /// Show windows of every desktop in the taskbar and the window switcher.
  taskbarAllDesktops<bool>("taskbar_all_desktops", false),

  /// Where the taskbar's app icons sit: "center" (in the middle of the
  /// screen) or "left" (next to the launcher, as Windows 11 can).
  taskbarAlignment<String>("taskbar_alignment", "center"),

  /// Taskbar height: "small" (40), "medium" (48) or "large" (56).
  taskbarSize<String>("taskbar_size", "medium"),

  /// The taskbar slides away until the pointer touches the bottom edge of
  /// the screen, and windows get the whole screen.
  taskbarAutohide<bool>("taskbar_autohide", false),

  /// The app menu covers the screen instead of opening above the taskbar.
  launcherFullscreen<bool>("launcher_fullscreen", false),

  /// Order of the app menu: "name" (A to Z) or "category" (grouped, A to Z
  /// within each group).
  launcherSort<String>("launcher_sort", "name"),

  /// Let the shell handle multi-finger touchpad gestures.
  gesturesEnabled<bool>("gestures_enabled", true),

  /// Fingers used for shell gestures: 3 or 4. Other counts go to apps.
  gestureFingers<int>("gesture_fingers", 3),

  /// Action of a swipe up, see [GestureAction].
  gestureSwipeUp<String>("gesture_swipe_up", "overview"),

  /// Action of a swipe down. An open overview or launcher always closes.
  gestureSwipeDown<String>("gesture_swipe_down", "none"),

  /// Action of left/right swipes: "switch_desktop" or "none".
  gestureSwipeHorizontal<String>("gesture_swipe_horizontal", "switch_desktop"),

  /// Move to the desktop on the other side for left/right swipes.
  gestureInvertHorizontal<bool>("gesture_invert_horizontal", false),

  /// Action of pinching in.
  gesturePinchIn<String>("gesture_pinch_in", "overview"),

  /// Action of pinching out.
  gesturePinchOut<String>("gesture_pinch_out", "show_desktop"),

  /// Written by the shell: whether the compositor lets it handle touchpad
  /// gestures (river with the river-touchpad-gestures-v1 extension).
  gesturesSupported<bool>("gestures_supported", false),

  /// Minutes without input before the screens turn off; 0 for never.
  screenOffMinutes<int>("screen_off_minutes", 5),

  /// Lock the session when the screens turn off for inactivity.
  lockOnScreenOff<bool>("lock_on_screen_off", true),

  /// Night Shift: warmer colors in the evening.
  nightShift<bool>("night_shift", false),

  /// Night Shift color temperature, in Kelvin.
  nightShiftTemperature<int>("night_shift_temperature", 4000),

  /// Whether Night Shift turns on and off by itself (from [nightShiftFrom]
  /// to [nightShiftTo]) rather than staying on.
  nightShiftScheduled<bool>("night_shift_scheduled", true),

  /// Minutes after midnight Night Shift starts (20:00).
  nightShiftFrom<int>("night_shift_from", 1200),

  /// Minutes after midnight Night Shift ends (07:00).
  nightShiftTo<int>("night_shift_to", 420),

  /// Notifications are kept in the notification center without popping up.
  doNotDisturb<bool>("do_not_disturb", false),

  /// The controls of Quick Settings, in order, comma separated (see
  /// QuickControl in the shell); the others can be added in edit mode.
  quickControls<String>(
    "quick_controls",
    "network,vpn,bluetooth,airplane_mode,do_not_disturb,night_shift,"
        "theme,screenshot,lock",
  ),

  /// Clicking the touchpad with two fingers is a right click (libinput's
  /// clickfinger method) rather than clicking its bottom right corner.
  twoFingerRightClick<bool>("touchpad_two_finger_click", true),

  /// Window title bars take a tint of the accent color.
  titlebarAccentTint<bool>("titlebar_accent_tint", true),

  /// Windows that aren't focused draw their glass (title bar, panes) opaque.
  opaqueInactiveWindows<bool>("opaque_inactive_windows", true),

  /// A hairline around floating windows, as macOS draws.
  windowBorders<bool>("window_borders", true),

  /// The accent color follows the wallpaper (the shell picks it).
  accentFromWallpaper<bool>("accent_from_wallpaper", false),

  /// Mouse pointer theme and size.
  cursorTheme<String>("cursor_theme", "Pangolin"),
  cursorSize<int>("cursor_size", 24),

  /// Terminal: color theme, lines kept in the scrollback, font size, cursor
  /// shape (block, underline or bar) and background opacity (frosted below
  /// 1 when blur is available).
  terminalTheme<String>("terminal_theme", "dahlia"),
  terminalScrollback<int>("terminal_scrollback", 10000),
  terminalFontSize<double>("terminal_font_size", 14.0),
  terminalCursorShape<String>("terminal_cursor_shape", "block"),
  terminalOpacity<double>("terminal_opacity", 1.0);

  const SessionSetting(this.key, this.defaultValue);

  final String key;
  final T defaultValue;

  /// Scheme entries for every session setting.
  static Map<String, DSettingsEntry> get scheme => {
        for (final SessionSetting setting in values)
          setting.key: DSettingsEntry(
            DSettingsTableType.fromValue(setting.defaultValue)!,
            setting.defaultValue,
          ),
      };
}

/// The full scheme of the `pangolin` table: dahlia_shared's [base] keys plus
/// the session settings.
Map<String, DSettingsEntry> sessionScheme(Map<String, DSettingsEntry> base) =>
    {...base, ...SessionSetting.scheme};

/// Actions touchpad gestures can trigger (values of the gesture settings).
enum GestureAction {
  none("none", "Nothing"),
  overview("overview", "Overview"),
  launcher("launcher", "App launcher"),
  showDesktop("show_desktop", "Show desktop"),
  quickSettings("quick_settings", "Quick settings"),
  search("search", "Search"),
  notifications("notifications", "Notifications"),
  lockScreen("lock_screen", "Lock the screen"),
  switchDesktop("switch_desktop", "Switch desktop");

  const GestureAction(this.value, this.label);

  final String value;
  final String label;

  static GestureAction parse(String? value) =>
      values.where((a) => a.value == value).firstOrNull ?? none;
}
