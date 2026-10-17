// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:zenit_ui/src/constants/constants.dart';
import 'package:zenit_ui/src/extensions/extensions.dart';
import 'package:zenit_ui/src/theme/text_theme.dart';

export 'package:zenit_ui/src/extensions/extensions.dart';

mixin ZenitTheme {
  static ZenitSwitchTheme switchTheme(BuildContext context) {
    final theme = Theme.of(context);
    return ZenitSwitchTheme(
      activeTrackColor: theme.colorScheme.primary,
      inactiveTrackColor: theme.colorScheme.surface,
      activeThumbColor: theme.colorScheme.onPrimary,
      inactiveThumbColor: theme.colorScheme.onSurface.withOpacity(0.35),
      disabledTrackColor: theme.disabledColor,
      disabledThumbColor: theme.colorScheme.background,
      outlineColor: theme.colorScheme.outline,
    );
  }

  static ZenitSliderTheme sliderTheme(BuildContext context) {
    final theme = Theme.of(context);
    return ZenitSliderTheme(
      activeTrackColor: theme.primaryColor,
      trackColor: theme.colorScheme.surface,
      thumbColor: theme.colorScheme.onPrimary,
      outlineColor: theme.colorScheme.outline,
    );
  }

  static ZenitRadioButtonTheme radioButtonTheme(BuildContext context) {
    final theme = Theme.of(context);
    return ZenitRadioButtonTheme(
      activeBackgroundColor: theme.colorScheme.primary,
      inactiveBackgroundColor: theme.colorScheme.surface,
      disabledBackgroundColor: theme.disabledColor,
      thumbColor: theme.colorScheme.background,
      outlineColor: theme.colorScheme.outline,
    );
  }

  static ZenitCheckboxTheme checkboxTheme(BuildContext context) {
    final theme = Theme.of(context);
    return ZenitCheckboxTheme(
      activeBackgroundColor: theme.colorScheme.primary,
      inactiveBackgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.background,
      disabledBackgroundColor: theme.disabledColor,
      outlineColor: theme.colorScheme.outline,
    );
  }
}

final Map<Object, ThemeData> _themeCache = {};

/// Builds the Zenit theme. The same arguments give back the same [ThemeData]
/// instance, so rebuilding an app with unchanged settings doesn't rebuild
/// every widget that depends on the theme.
ThemeData createZenitTheme({
  Brightness brightness = Brightness.light,
  Color? primaryColor,
  Color? backgroundColor,
  Color? surfaceColor,
  Color? foregroundColor,
  String? fontFamily,
  String? monospaceFontFamily,
}) {
  final Object key = (
    brightness,
    primaryColor,
    backgroundColor,
    surfaceColor,
    foregroundColor,
    fontFamily,
    monospaceFontFamily,
  );
  final ThemeData? cached = _themeCache[key];
  if (cached != null) return cached;
  if (_themeCache.length > 32) _themeCache.clear();
  return _themeCache[key] = _createZenitTheme(
    brightness: brightness,
    primaryColor: primaryColor,
    backgroundColor: backgroundColor,
    surfaceColor: surfaceColor,
    foregroundColor: foregroundColor,
    fontFamily: fontFamily,
    monospaceFontFamily: monospaceFontFamily,
  );
}

ThemeData _createZenitTheme({
  required Brightness brightness,
  Color? primaryColor,
  Color? backgroundColor,
  Color? surfaceColor,
  Color? foregroundColor,
  String? fontFamily,
  String? monospaceFontFamily,
}) {
  // Default Values

  const Color lightBackground = Color(0xFFFFFFFF);
  const Color lightForeground = Color(0xFF000000);
  const Color darkBackground = Color(0xFF1A1A1A);
  const Color darkForeground = Color(0xFFFAFAFA);

  final darkMode = brightness == Brightness.dark;
  primaryColor ??= const Color(0xFF0073cf);
  backgroundColor ??= darkMode ? darkBackground : lightBackground;
  foregroundColor ??= darkMode ? darkForeground : lightForeground;
  surfaceColor ??= darkMode ? const Color(0xFF272727) : const Color(0xFFE6E6E6);
  final TextTheme textTheme =
      createTextTheme(foregroundColor, fontFamily: fontFamily);
  final fonts = ZenitFonts(
    monospace: monospaceFontFamily != null && monospaceFontFamily.isNotEmpty
        ? monospaceFontFamily
        : "monospace",
  );

  // AppBar Theme
  final appBarTheme = AppBarTheme(
    backgroundColor: surfaceColor,
    titleTextStyle: TextStyle(
      color: foregroundColor,
      fontSize: 17,
      fontWeight: FontWeight.w600,
    ).withZenitFont(fontFamily),
  );

  // Icon Theme
  final iconTheme = IconThemeData(color: foregroundColor);

  // Card Theme
  const cardTheme = CardThemeData(
    clipBehavior: Clip.antiAlias,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: kCardBorderRadius,
    ),
  );

  // FloatingActionButton Theme
  final floatingActionButtonTheme = FloatingActionButtonThemeData(
    backgroundColor: surfaceColor,
    foregroundColor: foregroundColor,
    elevation: 0,
    focusElevation: 0,
    hoverElevation: 0,
    disabledElevation: 0,
    highlightElevation: 0,
    sizeConstraints: BoxConstraints.tight(const Size.square(52)),
    smallSizeConstraints: BoxConstraints.tight(const Size.square(44)),
    largeSizeConstraints: BoxConstraints.tight(const Size.square(56)),
    extendedSizeConstraints: const BoxConstraints.tightFor(height: 52),
    iconSize: 24,
    shape: RoundedRectangleBorder(
      borderRadius: kDefaultBorderRadiusLarge,
    ),
  );

  // PageTransitionsTheme
  const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  // Tooltip Theme
  final tooltipTheme = TooltipThemeData(
    decoration: BoxDecoration(
      color: foregroundColor,
      borderRadius: kDefaultBorderRadiusExtraLarge,
    ),
    textStyle: TextStyle(color: backgroundColor).withZenitFont(fontFamily),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    waitDuration: const Duration(milliseconds: 500),
    showDuration: Duration.zero,
  );

  // Snack bars: floating pills like the tooltips rather than a bar across
  // the bottom of the window.
  final snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: foregroundColor,
    contentTextStyle:
        TextStyle(color: backgroundColor).withZenitFont(fontFamily),
    shape: const RoundedRectangleBorder(
      borderRadius: kDefaultBorderRadiusExtraLarge,
    ),
    elevation: 0,
    insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
  );

  // Divider Theme: dividers only leave space (see "No lines" below).
  const dividerTheme = DividerThemeData(
    color: Colors.transparent,
    space: 1,
  );

  // No lines: like the dahliaOS design, Zenit sets things apart with fills
  // and spacing, never with borders or dividers. Material 3 draws borders
  // and dividers with `outline`/`outlineVariant`, which ColorScheme.light/dark
  // would default to the foreground color (solid black or white lines).
  const Color outline = Colors.transparent;
  const Color outlineVariant = Colors.transparent;
  // Secondary text, icons and checkbox frames: a mid grey rather than the
  // foreground color it would default to.
  final Color onSurfaceVariant =
      Color.lerp(foregroundColor, backgroundColor, 0.38)!;
  final Color onPrimary = (primaryColor.computeLuminance() > 0.3) != darkMode
      ? foregroundColor
      : backgroundColor;
  // Fill of text fields, readable on both the background and surfaces.
  final Color fieldFill = foregroundColor.withOpacity(darkMode ? 0.08 : 0.05);

  // Text fields: filled, no underline or frame.
  const OutlineInputBorder fieldBorder = OutlineInputBorder(
    borderRadius: kDefaultBorderRadiusMedium,
    borderSide: BorderSide.none,
  );
  final inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: fieldFill,
    border: fieldBorder,
    enabledBorder: fieldBorder,
    focusedBorder: fieldBorder,
    disabledBorder: fieldBorder,
    errorBorder: fieldBorder,
    focusedErrorBorder: fieldBorder,
  );

  // Chips: filled pills, the selected one in the accent color.
  final chipTheme = ChipThemeData(
    color: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return surfaceColor!.withOpacity(0.5);
      }
      if (states.contains(WidgetState.selected)) return primaryColor;
      return surfaceColor;
    }),
    side: BorderSide.none,
    shape: const StadiumBorder(),
    elevation: 0,
    pressElevation: 0,
    showCheckmark: false,
    labelStyle: TextStyle(
      color: WidgetStateColor.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? onPrimary : foregroundColor!,
      ),
    ).withZenitFont(fontFamily),
    iconTheme: IconThemeData(color: foregroundColor, size: 18),
  );

  // Outlined buttons: flat and filled (tonal) instead of framed.
  final outlinedButtonTheme = OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      side: BorderSide.none,
      backgroundColor: surfaceColor,
      foregroundColor: foregroundColor,
    ),
  );

  // Tab bars: just the indicator, no line below the tabs.
  const tabBarTheme = TabBarThemeData(
    dividerColor: Colors.transparent,
    dividerHeight: 0,
  );

  // ListTile Theme
  final listTileTheme = ListTileThemeData(
    subtitleTextStyle: TextStyle(
      color: foregroundColor.darken(0.4),
      fontSize: textTheme.bodyMedium?.fontSize,
    ).withZenitFont(fontFamily),
  );

  if (brightness == Brightness.light) {
    return ThemeData.from(
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        onPrimary: primaryColor.computeLuminance() > 0.3 ? foregroundColor : backgroundColor,
        secondary: primaryColor,
        onSecondary: primaryColor.computeLuminance() > 0.3 ? foregroundColor : backgroundColor,
        background: backgroundColor,
        onBackground: foregroundColor,
        surface: surfaceColor,
        onSurface: foregroundColor,
        outline: outline,
        outlineVariant: outlineVariant,
        onSurfaceVariant: onSurfaceVariant,
        // Flat surfaces: no primary tint on elevated menus and dialogs.
        surfaceTint: Colors.transparent,
      ),
    ).copyWith(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      iconTheme: iconTheme,
      cardTheme: cardTheme,
      floatingActionButtonTheme: floatingActionButtonTheme,
      pageTransitionsTheme: pageTransitionsTheme,
      tooltipTheme: tooltipTheme,
      snackBarTheme: snackBarTheme,
      dividerTheme: dividerTheme,
      listTileTheme: listTileTheme,
      chipTheme: chipTheme,
      tabBarTheme: tabBarTheme,
      inputDecorationTheme: inputDecorationTheme,
      dividerColor: outlineVariant,
      outlinedButtonTheme: outlinedButtonTheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      hoverColor: foregroundColor.withOpacity(0.05),
      extensions: [fonts],
    );
  } else {
    return ThemeData.from(
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        onPrimary: primaryColor.computeLuminance() > 0.3 ? backgroundColor : foregroundColor,
        secondary: primaryColor,
        onSecondary: primaryColor.computeLuminance() > 0.3 ? backgroundColor : foregroundColor,
        background: backgroundColor,
        onBackground: foregroundColor,
        surface: surfaceColor,
        onSurface: foregroundColor,
        outline: outline,
        outlineVariant: outlineVariant,
        onSurfaceVariant: onSurfaceVariant,
        // Flat surfaces: no primary tint on elevated menus and dialogs.
        surfaceTint: Colors.transparent,
      ),
    ).copyWith(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: appBarTheme,
      iconTheme: iconTheme,
      cardTheme: cardTheme,
      floatingActionButtonTheme: floatingActionButtonTheme,
      pageTransitionsTheme: pageTransitionsTheme,
      tooltipTheme: tooltipTheme,
      snackBarTheme: snackBarTheme,
      dividerTheme: dividerTheme,
      listTileTheme: listTileTheme,
      chipTheme: chipTheme,
      tabBarTheme: tabBarTheme,
      inputDecorationTheme: inputDecorationTheme,
      dividerColor: outlineVariant,
      outlinedButtonTheme: outlinedButtonTheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      hoverColor: foregroundColor.withOpacity(0.05),
      extensions: [fonts],
    );
  }
}

extension ZenitThemeData on ThemeData {
  bool get darkMode => brightness == Brightness.dark;

  /// Color used for raised surfaces (cards, buttons, panels).
  ///
  /// Kept for compatibility with consumers written against ZenitUI < 0.0.12,
  /// it maps to the `surface` color produced by [createZenitTheme].
  Color get surfaceColor => colorScheme.surface;

  /// Color used for text and icons drawn on top of [surfaceColor].
  Color get foregroundColor => colorScheme.onSurface;
  Color get accentForegroundColor =>
      colorScheme.primary.computeLuminance() > 0.3 ? Colors.black : Colors.white;
  Color computedForegroundColor(Color color) => color.computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

class ZenitSwitchTheme {
  final Color activeTrackColor;
  final Color inactiveTrackColor;
  final Color activeThumbColor;
  final Color inactiveThumbColor;
  final Color disabledTrackColor;
  final Color disabledThumbColor;
  final Color outlineColor;

  const ZenitSwitchTheme({
    required this.activeTrackColor,
    required this.inactiveTrackColor,
    required this.activeThumbColor,
    required this.inactiveThumbColor,
    required this.disabledTrackColor,
    required this.disabledThumbColor,
    required this.outlineColor,
  });

  ZenitSwitchTheme copyWith({
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? activeThumbColor,
    Color? inactiveThumbColor,
    Color? disabledTrackColor,
    Color? disabledThumbColor,
    Color? outlineColor,
  }) {
    return ZenitSwitchTheme(
      activeTrackColor: activeTrackColor ?? this.activeTrackColor,
      inactiveTrackColor: inactiveTrackColor ?? this.inactiveTrackColor,
      activeThumbColor: activeThumbColor ?? this.activeThumbColor,
      inactiveThumbColor: inactiveThumbColor ?? this.inactiveThumbColor,
      disabledTrackColor: disabledTrackColor ?? this.disabledTrackColor,
      disabledThumbColor: disabledThumbColor ?? this.disabledThumbColor,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }
}

class ZenitSliderTheme {
  final Color activeTrackColor;
  final Color trackColor;
  final Color outlineColor;
  final Color thumbColor;

  const ZenitSliderTheme({
    required this.activeTrackColor,
    required this.trackColor,
    required this.outlineColor,
    required this.thumbColor,
  });

  ZenitSliderTheme copyWith({
    Color? activeTrackColor,
    Color? trackColor,
    Color? outlineColor,
    Color? thumbColor,
  }) {
    return ZenitSliderTheme(
      activeTrackColor: activeTrackColor ?? this.activeTrackColor,
      trackColor: trackColor ?? this.trackColor,
      outlineColor: outlineColor ?? this.outlineColor,
      thumbColor: thumbColor ?? this.thumbColor,
    );
  }
}

class ZenitRadioButtonTheme {
  final Color activeBackgroundColor;
  final Color inactiveBackgroundColor;
  final Color disabledBackgroundColor;
  final Color thumbColor;
  final Color outlineColor;

  const ZenitRadioButtonTheme({
    required this.activeBackgroundColor,
    required this.inactiveBackgroundColor,
    required this.disabledBackgroundColor,
    required this.thumbColor,
    required this.outlineColor,
  });

  ZenitRadioButtonTheme copyWith({
    Color? activeBackgroundColor,
    Color? inactiveBackgroundColor,
    Color? disabledBackgroundColor,
    Color? thumbColor,
    Color? outlineColor,
  }) {
    return ZenitRadioButtonTheme(
      activeBackgroundColor: activeBackgroundColor ?? this.activeBackgroundColor,
      inactiveBackgroundColor: inactiveBackgroundColor ?? this.inactiveBackgroundColor,
      disabledBackgroundColor: disabledBackgroundColor ?? this.disabledBackgroundColor,
      thumbColor: thumbColor ?? this.thumbColor,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }
}

class ZenitCheckboxTheme {
  final Color activeBackgroundColor;
  final Color inactiveBackgroundColor;
  final Color foregroundColor;
  final Color disabledBackgroundColor;
  final Color outlineColor;

  const ZenitCheckboxTheme({
    required this.activeBackgroundColor,
    required this.inactiveBackgroundColor,
    required this.foregroundColor,
    required this.disabledBackgroundColor,
    required this.outlineColor,
  });

  ZenitCheckboxTheme copyWith({
    Color? activeBackgroundColor,
    Color? inactiveBackgroundColor,
    Color? foregroundColor,
    Color? disabledBackgroundColor,
    Color? outlineColor,
  }) {
    return ZenitCheckboxTheme(
      activeBackgroundColor: activeBackgroundColor ?? this.activeBackgroundColor,
      inactiveBackgroundColor: inactiveBackgroundColor ?? this.inactiveBackgroundColor,
      foregroundColor: foregroundColor ?? this.foregroundColor,
      disabledBackgroundColor: disabledBackgroundColor ?? this.disabledBackgroundColor,
      outlineColor: outlineColor ?? this.outlineColor,
    );
  }
}

/// Font families chosen by the user that the text theme doesn't carry.
class ZenitFonts extends ThemeExtension<ZenitFonts> {
  const ZenitFonts({required this.monospace});

  /// Family for code, terminals and logs.
  final String monospace;

  static String monospaceOf(BuildContext context) =>
      Theme.of(context).extension<ZenitFonts>()?.monospace ?? "monospace";

  @override
  ZenitFonts copyWith({String? monospace}) =>
      ZenitFonts(monospace: monospace ?? this.monospace);

  @override
  ZenitFonts lerp(ZenitFonts? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
