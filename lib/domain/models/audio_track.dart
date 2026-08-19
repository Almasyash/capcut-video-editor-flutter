/// Model representing an audio or background music track on the timeline
class AudioTrack {
  final String id;
  final String name;
  final String artist;
  final Duration startTime;
  final Duration duration;
  final double volume;
  final List<double> waveformPoints;

  const AudioTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.startTime,
    required this.duration,
    this.volume = 0.8,
    required this.waveformPoints,
  });

  double get durationInSeconds => duration.inMilliseconds / 1000.0;
  double get startTimeInSeconds => startTime.inMilliseconds / 1000.0;

  AudioTrack copyWith({
    String? id,
    String? name,
    String? artist,
    Duration? startTime,
    Duration? duration,
    double? volume,
    List<double>? waveformPoints,
  }) {
    return AudioTrack(
      id: id ?? this.id,
      name: name ?? this.name,
      artist: artist ?? this.artist,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      waveformPoints: waveformPoints ?? this.waveformPoints,
    );
  }
}
