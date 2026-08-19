import 'package:capcut_video_editor/domain/enums/export_resolution.dart';

/// Configuration for video rendering/export
class ExportSettings {
  final ExportResolution resolution;
  final ExportFps fps;
  final String format;
  final bool includeWatermark;
  final bool smartHDR;

  const ExportSettings({
    this.resolution = ExportResolution.res1080p,
    this.fps = ExportFps.fps30,
    this.format = 'MP4 (H.264)',
    this.includeWatermark = false,
    this.smartHDR = true,
  });

  /// Approximate file size in MB based on timeline duration
  double estimatedSizeMb(double durationSeconds) {
    // Base ~1.2 MB per second for 1080p 30fps
    const baseMbPerSec = 1.1;
    final fpsMult = (fps == ExportFps.fps60 ? 1.5 : (fps == ExportFps.fps50 ? 1.3 : 1.0));
    return (durationSeconds * baseMbPerSec * resolution.sizeMultiplier * fpsMult);
  }

  ExportSettings copyWith({
    ExportResolution? resolution,
    ExportFps? fps,
    String? format,
    bool? includeWatermark,
    bool? smartHDR,
  }) {
    return ExportSettings(
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      format: format ?? this.format,
      includeWatermark: includeWatermark ?? this.includeWatermark,
      smartHDR: smartHDR ?? this.smartHDR,
    );
  }
}
