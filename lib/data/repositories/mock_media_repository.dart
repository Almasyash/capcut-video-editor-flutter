import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';

/// Provides initial mock media assets for the CapCut timeline demo
class MockMediaRepository {
  /// Generates initial demo clips for the video track
  static List<VideoClip> getInitialVideoClips() {
    return [
      const VideoClip(
        id: 'clip_01',
        assetId: 'preset_asset_video_01',
        title: 'Cyberpunk City Neon',
        originalDuration: Duration(seconds: 8),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 7),
        speed: 1.0,
        volume: 1.0,
        previewGradient: [
          Color(0xFF0F2027),
          Color(0xFF203A43),
          Color(0xFF2C5364),
        ],
        previewIcon: Icons.nightlife_rounded,
      ),
      const VideoClip(
        id: 'clip_02',
        assetId: 'preset_asset_video_02',
        title: 'Sunset Beach Drone',
        originalDuration: Duration(seconds: 10),
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(seconds: 8),
        speed: 1.0,
        volume: 0.9,
        previewGradient: [
          Color(0xFFFA709A),
          Color(0xFFFEE140),
        ],
        previewIcon: Icons.wb_sunny_rounded,
      ),
      const VideoClip(
        id: 'clip_03',
        assetId: 'preset_asset_video_03',
        title: 'Hyperlapse Highway',
        originalDuration: Duration(seconds: 6),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 6),
        speed: 1.25,
        volume: 1.0,
        previewGradient: [
          Color(0xFF654EA3),
          Color(0xFFEAAFC8),
        ],
        previewIcon: Icons.fast_forward_rounded,
      ),
    ];
  }


  /// Generates initial text captions / subtitles
  static List<TextOverlay> getInitialTextOverlays() {
    return [
      const TextOverlay(
        id: 'text_01',
        text: 'FUTURE VIBES ⚡',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
        textColor: Color(0xFF00E5FF),
        fontSize: 22.0,
        position: Offset(0.5, 0.75),
      ),
      const TextOverlay(
        id: 'text_02',
        text: 'Golden Hour Flare ✨',
        startTime: Duration(seconds: 7),
        duration: Duration(seconds: 4),
        textColor: Color(0xFFFFD166),
        fontSize: 20.0,
        position: Offset(0.5, 0.78),
      ),
    ];
  }

  /// Creates a newly added random video clip
  static VideoClip createNewClip(int index) {
    final colors = [
      [const Color(0xFF11998E), const Color(0xFF38EF7D)],
      [const Color(0xFFFF512F), const Color(0xFFDD2476)],
      [const Color(0xFF8A2387), const Color(0xFFE94057), const Color(0xFFF27121)],
      [const Color(0xFF4776E6), const Color(0xFF8E54E9)],
    ];
    final icons = [
      Icons.nature_people_rounded,
      Icons.sports_esports_rounded,
      Icons.camera_alt_rounded,
      Icons.electric_bolt_rounded,
    ];

    final colorIdx = index % colors.length;
    final iconIdx = index % icons.length;

    return VideoClip(
      id: 'clip_new_${DateTime.now().millisecondsSinceEpoch}',
      assetId: 'preset_asset_clip_$index',
      title: 'Imported Clip #${index + 1}',
      originalDuration: const Duration(seconds: 6),
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 5),
      speed: 1.0,
      volume: 1.0,
      previewGradient: colors[colorIdx],
      previewIcon: icons[iconIdx],
    );
  }
}
