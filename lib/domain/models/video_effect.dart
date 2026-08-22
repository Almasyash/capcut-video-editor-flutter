import 'package:flutter/material.dart';

enum VideoEffectType {
  none,
  glitch,
  vhs,
  rgbSplit,
  zoomBlur,
  sparkle,
  shake,
  filmGrain,
}

class VideoEffect {
  final VideoEffectType type;
  final String name;
  final IconData icon;
  final Color color;

  const VideoEffect({
    required this.type,
    required this.name,
    required this.icon,
    required this.color,
  });

  static const List<VideoEffect> presets = [
    VideoEffect(type: VideoEffectType.none, name: 'None', icon: Icons.block_rounded, color: Colors.grey),
    VideoEffect(type: VideoEffectType.glitch, name: 'Glitch Art', icon: Icons.electric_bolt_rounded, color: Color(0xFF00E5FF)),
    VideoEffect(type: VideoEffectType.vhs, name: 'VHS Cam', icon: Icons.videocam_rounded, color: Color(0xFFFF5252)),
    VideoEffect(type: VideoEffectType.rgbSplit, name: 'RGB Split', icon: Icons.splitscreen_rounded, color: Color(0xFFFF007F)),
    VideoEffect(type: VideoEffectType.zoomBlur, name: 'Zoom Blur', icon: Icons.zoom_in_rounded, color: Color(0xFF7C4DFF)),
    VideoEffect(type: VideoEffectType.sparkle, name: 'Sparkles', icon: Icons.auto_awesome_rounded, color: Color(0xFFFFD700)),
    VideoEffect(type: VideoEffectType.shake, name: 'Camera Shake', icon: Icons.vibration_rounded, color: Color(0xFFFF9100)),
    VideoEffect(type: VideoEffectType.filmGrain, name: 'Film Grain', icon: Icons.grain_rounded, color: Color(0xFFB0BEC5)),
  ];
}
