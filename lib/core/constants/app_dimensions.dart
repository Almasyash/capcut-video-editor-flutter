/// Layout dimensions and constraints for the video editor UI
class AppDimensions {
  AppDimensions._();

  // Spacing & Padding
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // Border Radius
  static const double radiusSm = 6.0;
  static const double radiusMd = 10.0;
  static const double radiusLg = 16.0;
  static const double radiusFull = 999.0;

  // App Bar & Header
  static const double topBarHeight = 56.0;
  static const double bottomNavHeight = 64.0;
  static const double actionToolbarHeight = 64.0;

  // Timeline Dimensions
  static const double timelineRulerHeight = 28.0;
  static const double videoTrackHeight = 68.0;
  static const double audioTrackHeight = 44.0;
  static const double textTrackHeight = 36.0;
  static const double playheadNeedleWidth = 2.0;
  static const double playheadHandleSize = 14.0;
  static const double trimHandleWidth = 14.0;

  // Default Zoom Scaling (pixels per second)
  static const double defaultPixelsPerSecond = 50.0;
  static const double minPixelsPerSecond = 20.0;
  static const double maxPixelsPerSecond = 150.0;
}
