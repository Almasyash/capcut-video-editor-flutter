enum TransitionCategory {
  basic,
  wipe,
  slide,
  zoom,
  shape,
  blur,
  creative,
}

enum TransitionType {
  none,
  fade,
  dissolve,
  blackFade,
  whiteFade,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  zoomIn,
  zoomOut,
  circle,
  radial,
  blur,
  pixelate;

  String get displayName {
    switch (this) {
      case TransitionType.none:
        return 'None';
      case TransitionType.fade:
        return 'Fade';
      case TransitionType.dissolve:
        return 'Dissolve';
      case TransitionType.blackFade:
        return 'Black Fade';
      case TransitionType.whiteFade:
        return 'White Fade';
      case TransitionType.wipeLeft:
        return 'Wipe Left';
      case TransitionType.wipeRight:
        return 'Wipe Right';
      case TransitionType.wipeUp:
        return 'Wipe Up';
      case TransitionType.wipeDown:
        return 'Wipe Down';
      case TransitionType.slideLeft:
        return 'Slide Left';
      case TransitionType.slideRight:
        return 'Slide Right';
      case TransitionType.slideUp:
        return 'Slide Up';
      case TransitionType.slideDown:
        return 'Slide Down';
      case TransitionType.zoomIn:
        return 'Zoom In';
      case TransitionType.zoomOut:
        return 'Zoom Out';
      case TransitionType.circle:
        return 'Circle';
      case TransitionType.radial:
        return 'Radial';
      case TransitionType.blur:
        return 'Blur';
      case TransitionType.pixelate:
        return 'Pixelate';
    }
  }

  TransitionCategory get category {
    switch (this) {
      case TransitionType.none:
      case TransitionType.fade:
      case TransitionType.dissolve:
      case TransitionType.blackFade:
      case TransitionType.whiteFade:
        return TransitionCategory.basic;
      case TransitionType.wipeLeft:
      case TransitionType.wipeRight:
      case TransitionType.wipeUp:
      case TransitionType.wipeDown:
        return TransitionCategory.wipe;
      case TransitionType.slideLeft:
      case TransitionType.slideRight:
      case TransitionType.slideUp:
      case TransitionType.slideDown:
        return TransitionCategory.slide;
      case TransitionType.zoomIn:
      case TransitionType.zoomOut:
        return TransitionCategory.zoom;
      case TransitionType.circle:
      case TransitionType.radial:
        return TransitionCategory.shape;
      case TransitionType.blur:
        return TransitionCategory.blur;
      case TransitionType.pixelate:
        return TransitionCategory.creative;
    }
  }

  String? get shaderAssetPath {
    switch (this) {
      case TransitionType.none:
        return null;
      case TransitionType.fade:
      case TransitionType.dissolve:
        return 'assets/shaders/transitions/crossfade.frag';
      case TransitionType.blackFade:
        return 'assets/shaders/transitions/fade_black.frag';
      case TransitionType.whiteFade:
        return 'assets/shaders/transitions/fade_white.frag';
      case TransitionType.wipeLeft:
        return 'assets/shaders/transitions/wipe_left.frag';
      case TransitionType.wipeRight:
        return 'assets/shaders/transitions/wipe_right.frag';
      case TransitionType.wipeUp:
        return 'assets/shaders/transitions/wipe_up.frag';
      case TransitionType.wipeDown:
        return 'assets/shaders/transitions/wipe_down.frag';
      case TransitionType.slideLeft:
        return 'assets/shaders/transitions/slide_left.frag';
      case TransitionType.slideRight:
        return 'assets/shaders/transitions/slide_right.frag';
      case TransitionType.slideUp:
        return 'assets/shaders/transitions/slide_up.frag';
      case TransitionType.slideDown:
        return 'assets/shaders/transitions/slide_down.frag';
      case TransitionType.zoomIn:
        return 'assets/shaders/transitions/zoom_in.frag';
      case TransitionType.zoomOut:
        return 'assets/shaders/transitions/zoom_out.frag';
      case TransitionType.circle:
        return 'assets/shaders/transitions/circle.frag';
      case TransitionType.radial:
        return 'assets/shaders/transitions/radial.frag';
      case TransitionType.blur:
        return 'assets/shaders/transitions/blur.frag';
      case TransitionType.pixelate:
        return 'assets/shaders/transitions/pixelate.frag';
    }
  }
}
