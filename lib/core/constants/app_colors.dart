import 'package:flutter/material.dart';

/// CapCut-style modern dark palette with vibrant accents
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background = Color(0xFF0F0F12);
  static const Color surface = Color(0xFF18181F);
  static const Color surfaceElevated = Color(0xFF22222C);
  static const Color surfaceHighlight = Color(0xFF2E2E3C);
  static const Color surfaceLight = Color(0xFF252532);

  // Accents & Brand Colors
  static const Color primary = Color(0xFF00E5FF); // Electric Cyan
  static const Color primaryVariant = Color(0xFF00B4D8);
  static const Color secondary = Color(0xFFFF4B72); // CapCut Coral Red
  static const Color accentAmber = Color(0xFFFFB300); // Yellow/Amber Selection Handle
  static const Color accentGreen = Color(0xFF00E676); // Success Green
  static const Color accentPurple = Color(0xFF9D4EDD); // Effects / Text Track
  static const Color error = Color(0xFFFF5252); // Error Red

  // Timeline Specific Colors
  static const Color timelineTrackBg = Color(0xFF14141A);
  static const Color timelineRulerBg = Color(0xFF101015);
  static const Color timelineRulerTick = Color(0xFF5A5A6E);
  static const Color timelineRulerText = Color(0xFF8E8EA0);
  static const Color playheadLine = Color(0xFFFFFFFF);
  static const Color playheadHandle = Color(0xFF00E5FF);
  static const Color selectionBorder = Color(0xFFFFB300);
  static const Color trimHandle = Color(0xFFFFB300);
  static const Color transitionNode = Color(0xFFFFFFFF);

  // Track Types
  static const Color videoTrackBorder = Color(0xFF333344);
  static const Color audioTrackBg = Color(0xFF1E3A4C);
  static const Color audioTrackWaveform = Color(0xFF00E5FF);
  static const Color textTrackBg = Color(0xFF3D234F);
  static const Color textTrackAccent = Color(0xFFC77DFF);

  // Text & Neutral Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA0A0B2);
  static const Color textTertiary = Color(0xFF757588);
  static const Color textMuted = Color(0xFF656578);
  static const Color divider = Color(0xFF272733);
  static const Color iconDefault = Color(0xFFE0E0E8);
  static const Color iconDisabled = Color(0xFF505060);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF0077B6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient exportGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF7B2CBF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient splitButtonGradient = LinearGradient(
    colors: [Color(0xFFFF4B72), Color(0xFFFF8FA3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
