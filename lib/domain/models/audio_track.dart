/// Model representing an audio or background music track on the timeline
class AudioTrack {
  final String id;

  /// Canonical reference to the source MediaAsset in central MediaLibrary
  final String assetId;

  final String name;
  final String artist;
  final Duration startTime;
  final Duration duration; // Original total duration of the media file
  final Duration trimStart; // Non-destructive start offset within source file
  final Duration? trimEnd; // Non-destructive end offset within source file
  final double volume; // 0.0 to 1.0
  final double speed; // Playback speed multiplier (e.g. 0.5, 1.0, 2.0)
  final bool isMuted;
  final List<double> waveformPoints;

  const AudioTrack({
    required this.id,
    required this.assetId,
    String? name,
    String? title,
    this.artist = 'Original Audio',
    this.startTime = Duration.zero,
    required this.duration,
    this.trimStart = Duration.zero,
    this.trimEnd,
    this.volume = 0.8,
    this.speed = 1.0,
    this.isMuted = false,
    this.waveformPoints = const [],
  }) : name = title ?? name ?? 'Audio Track';

  String get title => name;

  /// Raw original total duration
  double get originalDurationInSeconds => duration.inMilliseconds / 1000.0;

  /// Effective duration on timeline after trim and speed adjustments
  Duration get effectiveTrimEnd => trimEnd ?? duration;

  Duration get effectiveDuration {
    final trimmedMs = (effectiveTrimEnd.inMilliseconds - trimStart.inMilliseconds).clamp(0, duration.inMilliseconds);
    final adjustedMs = (trimmedMs / (speed > 0 ? speed : 1.0)).round();
    return Duration(milliseconds: adjustedMs);
  }

  double get durationInSeconds => effectiveDuration.inMilliseconds / 1000.0;
  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;
  double get endTimeInSeconds => startTimeInSeconds + durationInSeconds;

  double get trimStartInSeconds => trimStart.inMilliseconds / 1000.0;
  double get trimEndInSeconds => effectiveTrimEnd.inMilliseconds / 1000.0;

  AudioTrack copyWith({
    String? id,
    String? assetId,
    String? name,
    String? title,
    String? artist,
    Duration? startTime,
    Duration? duration,
    Duration? trimStart,
    Duration? trimEnd,
    double? volume,
    double? speed,
    bool? isMuted,
    List<double>? waveformPoints,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      name: title ?? name ?? this.name,
      artist: artist ?? this.artist,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      isMuted: isMuted ?? this.isMuted,
      waveformPoints: waveformPoints ?? this.waveformPoints,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'name': name,
      'artist': artist,
      'startTimeMs': startTime.inMilliseconds,
      'durationMs': duration.inMilliseconds,
      'trimStartMs': trimStart.inMilliseconds,
      'trimEndMs': (trimEnd ?? duration).inMilliseconds,
      'volume': volume,
      'speed': speed,
      'isMuted': isMuted,
      'waveformPoints': waveformPoints,
    };
  }

  factory AudioTrack.fromJson(Map<String, dynamic> json) {
    final totalDurationMs = (json['durationMs'] as num?)?.toInt() ?? 10000;
    final totalDuration = Duration(milliseconds: totalDurationMs);
    final trimStartMs = (json['trimStartMs'] as num?)?.toInt() ?? 0;
    final trimEndMs = (json['trimEndMs'] as num?)?.toInt() ?? totalDurationMs;

    return AudioTrack(
      id: json['id'] as String,
      assetId: json['assetId'] as String? ?? '',
      name: json['name'] as String? ?? 'Audio Track',
      artist: json['artist'] as String? ?? 'Original Audio',
      startTime: Duration(milliseconds: (json['startTimeMs'] as num?)?.toInt() ?? 0),
      duration: totalDuration,
      trimStart: Duration(milliseconds: trimStartMs),
      trimEnd: Duration(milliseconds: trimEndMs),
      volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      isMuted: json['isMuted'] as bool? ?? false,
      waveformPoints: (json['waveformPoints'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0.3, 0.5, 0.7, 0.4],
    );
  }
}
