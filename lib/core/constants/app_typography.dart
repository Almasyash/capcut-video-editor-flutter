import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';

/// Clean modern typography presets for the video editor UI
class AppTypography {
  AppTypography._();

  static const TextStyle headerTitle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.2,
  );

  static const TextStyle timecodeLarge = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle timecodeMuted = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.textSecondary,
  );

  static const TextStyle rulerTick = TextStyle(
    fontSize: 10.0,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.timelineRulerText,
  );

  static const TextStyle actionLabel = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle actionLabelDisabled = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    color: AppColors.iconDisabled,
    letterSpacing: 0.1,
  );

  static const TextStyle bottomNavLabel = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static const TextStyle bottomNavLabelSelected = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const TextStyle badgeText = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  );
}
