/// Model representing an audio or background music track on the timeline
class AudioTrack {
  final String id;

  /// Canonical reference to the source MediaAsset in central MediaLibrary
  final String assetId;

  final String name;
  final String artist;
  final Duration startTime;
  final Duration duration;
  final double volume;
  final List<double> waveformPoints;

  const AudioTrack({
    required this.id,
    required this.assetId,
    String? name,
    String? title,
    this.artist = 'Original Audio',
    this.startTime = Duration.zero,
    required this.duration,
    this.volume = 0.8,
    required this.waveformPoints,
  }) : name = title ?? name ?? 'Audio Track';

  String get title => name;

  double get durationInSeconds => duration.inMilliseconds / 1000.0;
  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;

  AudioTrack copyWith({
    String? id,
    String? assetId,
    String? name,
    String? title,
    String? artist,
    Duration? startTime,
    Duration? duration,
    double? volume,
    List<double>? waveformPoints,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      name: title ?? name ?? this.name,
      artist: artist ?? this.artist,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      waveformPoints: waveformPoints ?? this.waveformPoints,
    );
  }
}
