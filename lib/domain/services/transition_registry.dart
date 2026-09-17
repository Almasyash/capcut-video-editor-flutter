import 'package:capcut_video_editor/domain/enums/transition_type.dart';

/// Metadata definition for a transition effect.
class TransitionDefinition {
  final TransitionType type;
  final String id;
  final String name;
  final TransitionCategory category;
  final String? shaderPath;
  final double defaultDuration;
  final double minDuration;
  final double maxDuration;

  const TransitionDefinition({
    required this.type,
    required this.id,
    required this.name,
    required this.category,
    this.shaderPath,
    this.defaultDuration = 0.5,
    this.minDuration = 0.1,
    this.maxDuration = 3.0,
  });
}

/// Central registry managing all available transition effects, categories,
/// metadata, and shader bindings in Editor FS.
class TransitionRegistry {
  TransitionRegistry._();

  static const double defaultDuration = 0.5;
  static const double minDuration = 0.1;
  static const double maxDuration = 3.0;

  static final List<TransitionDefinition> _definitions = [
    // Basic
    const TransitionDefinition(
      type: TransitionType.none,
      id: 'none',
      name: 'None',
      category: TransitionCategory.basic,
    ),
    const TransitionDefinition(
      type: TransitionType.fade,
      id: 'fade',
      name: 'Fade',
      category: TransitionCategory.basic,
      shaderPath: 'assets/shaders/transitions/crossfade.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.dissolve,
      id: 'dissolve',
      name: 'Dissolve',
      category: TransitionCategory.basic,
      shaderPath: 'assets/shaders/transitions/crossfade.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.blackFade,
      id: 'blackFade',
      name: 'Black Fade',
      category: TransitionCategory.basic,
      shaderPath: 'assets/shaders/transitions/fade_black.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.whiteFade,
      id: 'whiteFade',
      name: 'White Fade',
      category: TransitionCategory.basic,
      shaderPath: 'assets/shaders/transitions/fade_white.frag',
    ),

    // Wipe
    const TransitionDefinition(
      type: TransitionType.wipeLeft,
      id: 'wipeLeft',
      name: 'Wipe Left',
      category: TransitionCategory.wipe,
      shaderPath: 'assets/shaders/transitions/wipe_left.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.wipeRight,
      id: 'wipeRight',
      name: 'Wipe Right',
      category: TransitionCategory.wipe,
      shaderPath: 'assets/shaders/transitions/wipe_right.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.wipeUp,
      id: 'wipeUp',
      name: 'Wipe Up',
      category: TransitionCategory.wipe,
      shaderPath: 'assets/shaders/transitions/wipe_up.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.wipeDown,
      id: 'wipeDown',
      name: 'Wipe Down',
      category: TransitionCategory.wipe,
      shaderPath: 'assets/shaders/transitions/wipe_down.frag',
    ),

    // Slide
    const TransitionDefinition(
      type: TransitionType.slideLeft,
      id: 'slideLeft',
      name: 'Slide Left',
      category: TransitionCategory.slide,
      shaderPath: 'assets/shaders/transitions/slide_left.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.slideRight,
      id: 'slideRight',
      name: 'Slide Right',
      category: TransitionCategory.slide,
      shaderPath: 'assets/shaders/transitions/slide_right.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.slideUp,
      id: 'slideUp',
      name: 'Slide Up',
      category: TransitionCategory.slide,
      shaderPath: 'assets/shaders/transitions/slide_up.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.slideDown,
      id: 'slideDown',
      name: 'Slide Down',
      category: TransitionCategory.slide,
      shaderPath: 'assets/shaders/transitions/slide_down.frag',
    ),

    // Zoom
    const TransitionDefinition(
      type: TransitionType.zoomIn,
      id: 'zoomIn',
      name: 'Zoom In',
      category: TransitionCategory.zoom,
      shaderPath: 'assets/shaders/transitions/zoom_in.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.zoomOut,
      id: 'zoomOut',
      name: 'Zoom Out',
      category: TransitionCategory.zoom,
      shaderPath: 'assets/shaders/transitions/zoom_out.frag',
    ),

    // Shape
    const TransitionDefinition(
      type: TransitionType.circle,
      id: 'circle',
      name: 'Circle',
      category: TransitionCategory.shape,
      shaderPath: 'assets/shaders/transitions/circle.frag',
    ),
    const TransitionDefinition(
      type: TransitionType.radial,
      id: 'radial',
      name: 'Radial',
      category: TransitionCategory.shape,
      shaderPath: 'assets/shaders/transitions/radial.frag',
    ),

    // Blur
    const TransitionDefinition(
      type: TransitionType.blur,
      id: 'blur',
      name: 'Blur',
      category: TransitionCategory.blur,
      shaderPath: 'assets/shaders/transitions/blur.frag',
    ),

    // Creative
    const TransitionDefinition(
      type: TransitionType.pixelate,
      id: 'pixelate',
      name: 'Pixelate',
      category: TransitionCategory.creative,
      shaderPath: 'assets/shaders/transitions/pixelate.frag',
    ),
  ];

  static List<TransitionDefinition> get allDefinitions => List.unmodifiable(_definitions);

  static List<TransitionCategory> get categories => TransitionCategory.values;

  static List<TransitionDefinition> getByCategory(TransitionCategory category) {
    return _definitions.where((d) => d.category == category).toList();
  }

  static TransitionDefinition getByType(TransitionType type) {
    return _definitions.firstWhere(
      (d) => d.type == type,
      orElse: () => _definitions.first,
    );
  }

  static TransitionDefinition? getById(String id) {
    try {
      return _definitions.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  static String getCategoryTitle(TransitionCategory category) {
    switch (category) {
      case TransitionCategory.basic:
        return 'Basic';
      case TransitionCategory.wipe:
        return 'Wipe';
      case TransitionCategory.slide:
        return 'Slide';
      case TransitionCategory.zoom:
        return 'Zoom';
      case TransitionCategory.shape:
        return 'Shape';
      case TransitionCategory.blur:
        return 'Blur';
      case TransitionCategory.creative:
        return 'Creative';
    }
  }
}
