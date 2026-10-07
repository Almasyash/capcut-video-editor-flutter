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
  final double volume; // 0.0 to 2.0 (0% to 200%)
  final double speed; // Playback speed multiplier (e.g. 0.5, 1.0, 2.0)
  final bool isMuted;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final List<double> waveformPoints;

  /// List of musical beat timestamps (in seconds relative to original audio source)
  final List<double> beats;

  /// Controls whether beat markers are displayed on the waveform and used for magnetic snapping
  final bool showBeats;

  /// Layer Management (Lock & Visibility)
  final bool isLocked;
  final bool isVisible;

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
    this.fadeInDuration = Duration.zero,
    this.fadeOutDuration = Duration.zero,
    this.waveformPoints = const [],
    this.beats = const [],
    this.showBeats = true,
    this.isLocked = false,
    this.isVisible = true,
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

  /// Returns all beat timestamps that fall within the current [trimStart] and [trimEnd] window,
  /// mapped to their absolute position on the project timeline (in seconds).
  List<double> get visibleTimelineBeats {
    if (!showBeats || beats.isEmpty) return const [];
    final startSec = trimStartInSeconds;
    final endSec = trimEndInSeconds;
    final speedFactor = speed > 0 ? speed : 1.0;

    final visible = <double>[];
    for (final b in beats) {
      if (b >= startSec && b <= endSec) {
        // Offset relative to trimStart, scaled by speed, then shifted by track startTime
        final relativeSec = (b - startSec) / speedFactor;
        final timelinePos = startTimeInSeconds + relativeSec;
        visible.add(timelinePos);
      }
    }
    return visible;
  }

  /// Effective clamped fade-in duration ensuring fadeIn + fadeOut <= effectiveDuration
  Duration get effectiveFadeInDuration {
    final maxMs = effectiveDuration.inMilliseconds;
    return Duration(milliseconds: fadeInDuration.inMilliseconds.clamp(0, maxMs));
  }

  /// Effective clamped fade-out duration ensuring fadeIn + fadeOut <= effectiveDuration
  Duration get effectiveFadeOutDuration {
    final remMs = (effectiveDuration.inMilliseconds - effectiveFadeInDuration.inMilliseconds).clamp(0, effectiveDuration.inMilliseconds);
    return Duration(milliseconds: fadeOutDuration.inMilliseconds.clamp(0, remMs));
  }

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
    Duration? fadeInDuration,
    Duration? fadeOutDuration,
    List<double>? waveformPoints,
    List<double>? beats,
    bool? showBeats,
    bool? isLocked,
    bool? isVisible,
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
      fadeInDuration: fadeInDuration ?? this.fadeInDuration,
      fadeOutDuration: fadeOutDuration ?? this.fadeOutDuration,
      waveformPoints: waveformPoints ?? this.waveformPoints,
      beats: beats ?? this.beats,
      showBeats: showBeats ?? this.showBeats,
      isLocked: isLocked ?? this.isLocked,
      isVisible: isVisible ?? this.isVisible,
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
      'fadeInMs': fadeInDuration.inMilliseconds,
      'fadeOutMs': fadeOutDuration.inMilliseconds,
      'waveformPoints': waveformPoints,
      'beats': beats,
      'showBeats': showBeats,
      'isLocked': isLocked,
      'isVisible': isVisible,
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
      fadeInDuration: Duration(milliseconds: (json['fadeInMs'] as num?)?.toInt() ?? 0),
      fadeOutDuration: Duration(milliseconds: (json['fadeOutMs'] as num?)?.toInt() ?? 0),
      waveformPoints: (json['waveformPoints'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0.3, 0.5, 0.7, 0.4],
      beats: (json['beats'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      showBeats: json['showBeats'] as bool? ?? true,
      isLocked: json['isLocked'] as bool? ?? false,
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }
}
