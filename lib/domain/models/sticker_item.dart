import 'package:flutter/material.dart';

enum StickerCategory {
  emojis,
  vlog,
  badges,
  neon,
}

class StickerPreset {
  final String id;
  final String label;
  final String content; // Emoji string or icon name
  final bool isEmoji;
  final IconData? icon;
  final StickerCategory category;
  final Color? color;

  const StickerPreset({
    required this.id,
    required this.label,
    required this.content,
    this.isEmoji = true,
    this.icon,
    required this.category,
    this.color,
  });

  static const List<StickerPreset> catalog = [
    // Emojis
    StickerPreset(id: 's_fire', label: 'Fire', content: '🔥', category: StickerCategory.emojis),
    StickerPreset(id: 's_sparkles', label: 'Sparkles', content: '✨', category: StickerCategory.emojis),
    StickerPreset(id: 's_heart', label: 'Heart Eyes', content: '😍', category: StickerCategory.emojis),
    StickerPreset(id: 's_laugh', label: 'Laugh', content: '😂', category: StickerCategory.emojis),
    StickerPreset(id: 's_cool', label: 'Cool', content: '😎', category: StickerCategory.emojis),
    StickerPreset(id: 's_mindblow', label: 'Mind Blown', content: '🤯', category: StickerCategory.emojis),
    StickerPreset(id: 's_rocket', label: 'Rocket', content: '🚀', category: StickerCategory.emojis),
    StickerPreset(id: 's_100', label: '100', content: '💯', category: StickerCategory.emojis),

    // Vlog
    StickerPreset(id: 's_sub', label: 'Subscribe', content: 'SUBSCRIBE', isEmoji: false, icon: Icons.subscriptions_rounded, category: StickerCategory.vlog, color: Colors.red),
    StickerPreset(id: 's_bell', label: 'Bell', content: 'NOTIFY', isEmoji: false, icon: Icons.notifications_active_rounded, category: StickerCategory.vlog, color: Colors.amber),
    StickerPreset(id: 's_like', label: 'Like', content: 'LIKE', isEmoji: false, icon: Icons.thumb_up_alt_rounded, category: StickerCategory.vlog, color: Colors.blue),
    StickerPreset(id: 's_share', label: 'Share', content: 'SHARE', isEmoji: false, icon: Icons.share_rounded, category: StickerCategory.vlog, color: Colors.green),

    // Badges
    StickerPreset(id: 's_new', label: 'NEW', content: 'NEW', isEmoji: false, icon: Icons.fiber_new_rounded, category: StickerCategory.badges, color: Colors.purpleAccent),
    StickerPreset(id: 's_star', label: 'VIP Star', content: 'VIP', isEmoji: false, icon: Icons.star_rounded, category: StickerCategory.badges, color: Colors.amberAccent),
    StickerPreset(id: 's_hot', label: 'HOT', content: 'HOT', isEmoji: false, icon: Icons.whatshot_rounded, category: StickerCategory.badges, color: Colors.deepOrange),

    // Neon
    StickerPreset(id: 's_arrow', label: 'Neon Arrow', content: 'ARROW', isEmoji: false, icon: Icons.arrow_forward_rounded, category: StickerCategory.neon, color: Color(0xFF00E5FF)),
    StickerPreset(id: 's_bolt', label: 'Lightning', content: 'BOLT', isEmoji: false, icon: Icons.bolt_rounded, category: StickerCategory.neon, color: Color(0xFFFF007F)),
    StickerPreset(id: 's_play', label: 'Neon Play', content: 'PLAY', isEmoji: false, icon: Icons.play_circle_fill_rounded, category: StickerCategory.neon, color: Color(0xFF76FF03)),
  ];
}

/// Placed sticker on the video timeline canvas
class StickerOverlay {
  final String id;
  final StickerPreset preset;
  final Duration startTime;
  final Duration duration;
  final Offset position; // Relative 0.0 to 1.0 on canvas
  final double scale; // 0.5 to 2.5
  final double rotation;

  const StickerOverlay({
    required this.id,
    required this.preset,
    required this.startTime,
    required this.duration,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;
  double get durationInSeconds => duration.inMilliseconds / 1000.0;

  StickerOverlay copyWith({
    String? id,
    StickerPreset? preset,
    Duration? startTime,
    Duration? duration,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return StickerOverlay(
      id: id ?? this.id,
      preset: preset ?? this.preset,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'presetId': preset.id,
      'startTimeMs': startTime.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'posX': position.dx,
      'posY': position.dy,
      'scale': scale,
      'rotation': rotation,
    };
  }

  factory StickerOverlay.fromJson(Map<String, dynamic> json) {
    final presetId = json['presetId'] as String? ?? 's_fire';
    final preset = StickerPreset.catalog.firstWhere(
      (p) => p.id == presetId,
      orElse: () => StickerPreset.catalog.first,
    );

    return StickerOverlay(
      id: json['id'] as String,
      preset: preset,
      startTime: Duration(milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (json['durationMs'] as num?)?.toInt() ?? 3000),
      position: Offset(
        (json['posX'] as num?)?.toDouble() ?? 0.5,
        (json['posY'] as num?)?.toDouble() ?? 0.5,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
