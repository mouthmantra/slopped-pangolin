import 'package:flutter/material.dart';

// Credits to the yaru team, this file is basically just copied and altered a bit

/// Zenit's type scale, in Inter unless another [fontFamily] (installed on the
/// system) is given.
///
/// Titles and labels end in "…" when they don't fit. Body text (the
/// default text of Material widgets, paragraphs, dialog messages) wraps: an
/// ellipsis without a line limit would cut it after its first line.
TextTheme createTextTheme(Color textColor, {String? fontFamily}) {
  return TextTheme(
    displayLarge: TextStyle(
      fontSize: 64,
      fontWeight: FontWeight.w300,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    displayMedium: TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w300,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    displaySmall: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    headlineSmall: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    bodyLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).withZenitFont(fontFamily),
    bodyMedium: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).withZenitFont(fontFamily),
    bodySmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).withZenitFont(fontFamily),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    labelMedium: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
    labelSmall: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.normal,
      color: textColor,
    ).asZenitTextStyle(fontFamily),
  );
}

extension TextStyleX on TextStyle {
  /// This style in Zenit's font: [fontFamily] (installed on the system), or
  /// the bundled Inter. For the styles component themes set on their own,
  /// which don't inherit the text theme's font.
  TextStyle withZenitFont([String? fontFamily]) {
    if (fontFamily != null && fontFamily.isNotEmpty) {
      return copyWith(fontFamily: fontFamily);
    }
    return copyWith(fontFamily: 'Inter', package: 'zenit_ui');
  }

  TextStyle asZenitTextStyle([String? fontFamily]) {
    // A system font must not get the package prefix of the bundled Inter
    // (TextStyle keeps the package through copyWith/apply).
    if (fontFamily != null && fontFamily.isNotEmpty) {
      return copyWith(fontFamily: fontFamily, overflow: TextOverflow.ellipsis);
    }
    return copyWith(
      fontFamily: 'Inter',
      package: 'zenit_ui',
      overflow: TextOverflow.ellipsis,
    );
  }
}
