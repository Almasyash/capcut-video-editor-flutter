/// Explicit interaction modes for touch manipulation in the video editor canvas.
/// Guarantees that text manipulation, corner resizing, crop resizing, and canvas
/// background gestures remain strictly isolated without stealing pointers or
/// conflicting in the Flutter gesture arena.
enum InteractionMode {
  /// No active touch interaction.
  none,

  /// One-finger direct translation of active text overlay.
  textMove,

  /// Two-finger direct pinch-to-zoom scaling of active text overlay.
  textPinch,

  /// Corner handle explicit resize of active text overlay.
  textResize,

  /// Crop-area bounding box resize handle interaction.
  cropResize,
}

extension InteractionModeExtension on InteractionMode {
  /// Whether an active text manipulation gesture is currently in progress.
  bool get isTextActive =>
      this == InteractionMode.textMove ||
      this == InteractionMode.textPinch ||
      this == InteractionMode.textResize;

  /// Whether a crop-area resize gesture is currently in progress.
  bool get isCropActive => this == InteractionMode.cropResize;
}
