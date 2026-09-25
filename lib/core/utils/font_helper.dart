import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Helper utility for resolving and applying genuine typography and font files
/// across the video editor text layers and preview canvas.
class FontHelper {
  /// Resolves the requested font family to its true underlying font files via Google Fonts,
  /// with graceful fallbacks for system fonts and offline environments.
  static TextStyle getTextStyle({
    String? fontFamily,
    required double fontSize,
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    Paint? foreground,
    double? letterSpacing = 0.5,
  }) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      decoration: decoration,
      foreground: foreground,
      letterSpacing: letterSpacing,
    );

    if (fontFamily == null || fontFamily.isEmpty || fontFamily == 'Default') {
      return baseStyle;
    }

    // System standard font keywords
    final lower = fontFamily.toLowerCase().trim();
    if (lower == 'monospace' || lower == 'serif' || lower == 'sans-serif') {
      return baseStyle.copyWith(fontFamily: fontFamily);
    }

    try {
      return GoogleFonts.getFont(
        fontFamily,
        textStyle: baseStyle,
      );
    } catch (_) {
      // Graceful fallback to specified fontFamily name if offline or not in GoogleFonts map
      return baseStyle.copyWith(fontFamily: fontFamily);
    }
  }

  /// List of available fonts with human-readable labels and official font family names.
  static const availableFonts = [
    (label: 'Default', family: null),
    (label: 'Roboto', family: 'Roboto'),
    (label: 'Montserrat', family: 'Montserrat'),
    (label: 'Oswald', family: 'Oswald'),
    (label: 'Bebas Neue', family: 'Bebas Neue'),
    (label: 'Playfair', family: 'Playfair Display'),
    (label: 'Pacifico', family: 'Pacifico'),
    (label: 'Monospace', family: 'monospace'),
    (label: 'Serif', family: 'serif'),
    (label: 'Sans-Serif', family: 'sans-serif'),
  ];
}
