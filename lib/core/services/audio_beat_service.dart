import 'dart:math' as math;

/// Sensitivity presets for automated rhythmic beat detection
enum BeatSensitivity {
  /// Detects major percussive downbeats and bass drops (spaced ~0.6s to 1.4s)
  strongDownbeats('Strong Beats (Drop)', 0.60, 0.55),

  /// Detects fast tempo subdivisions, snare/hi-hat patterns (spaced ~0.28s to 0.65s)
  fastBeats('Fast Beats (Tempo)', 0.28, 0.32);

  final String label;
  final double minIntervalSeconds;
  final double peakThreshold;

  const BeatSensitivity(this.label, this.minIntervalSeconds, this.peakThreshold);
}

/// Service responsible for musical beat detection, transient spike analysis,
/// and magnetic timeline snapping for CapCut-style "Match Cut" workflows.
class AudioBeatService {
  AudioBeatService._();
  static final AudioBeatService instance = AudioBeatService._();

  /// Detects musical beats from normalized waveform points and track duration
  List<double> detectBeats({
    required List<double> waveformPoints,
    required Duration duration,
    BeatSensitivity sensitivity = BeatSensitivity.strongDownbeats,
  }) {
    if (waveformPoints.isEmpty || duration.inMilliseconds <= 200) {
      return const [];
    }

    final totalSeconds = duration.inMilliseconds / 1000.0;
    final n = waveformPoints.length;
    final dt = totalSeconds / n;

    // 1. Calculate statistical energy mean and standard deviation
    double sum = 0.0;
    for (final p in waveformPoints) {
      sum += p;
    }
    final mean = sum / n;

    double varianceSum = 0.0;
    for (final p in waveformPoints) {
      final diff = p - mean;
      varianceSum += diff * diff;
    }
    final stdDev = math.sqrt(varianceSum / n);

    // 2. Compute dynamic onset threshold based on sensitivity
    final dynamicCutoff = sensitivity == BeatSensitivity.strongDownbeats
        ? math.max(sensitivity.peakThreshold, mean + 0.45 * stdDev)
        : math.max(sensitivity.peakThreshold, mean + 0.15 * stdDev);

    final minSamplesApart = math.max(1, (sensitivity.minIntervalSeconds / dt).round());
    final detectedBeats = <double>[];
    int lastBeatIndex = -minSamplesApart;

    // 3. Local transient peak detection with refractory window
    for (int i = 1; i < n - 1; i++) {
      if (i - lastBeatIndex < minSamplesApart) continue;

      final current = waveformPoints[i];
      final prev = waveformPoints[i - 1];
      final next = waveformPoints[i + 1];

      // Local maximum check
      final isLocalPeak = current >= prev && current >= next && current >= dynamicCutoff;

      // Energy rise / onset acceleration
      final onsetDelta = current - prev;
      final hasStrongOnset = onsetDelta > 0.04 || current >= (mean + 0.8 * stdDev);

      if (isLocalPeak && hasStrongOnset) {
        final timestamp = (i * dt);
        // Round to 3 decimal places
        final rounded = (timestamp * 1000).round() / 1000.0;
        if (rounded <= totalSeconds) {
          detectedBeats.add(rounded);
          lastBeatIndex = i;
        }
      }
    }

    // Fallback: If track has very low dynamic range (flat audio), synthesize rhythmic tempo beats
    if (detectedBeats.isEmpty && totalSeconds > 0.5) {
      final fallbackInterval = sensitivity == BeatSensitivity.strongDownbeats ? 0.8 : 0.4;
      double t = fallbackInterval;
      while (t < totalSeconds) {
        detectedBeats.add((t * 1000).round() / 1000.0);
        t += fallbackInterval;
      }
    }

    return detectedBeats;
  }

  /// Finds the nearest beat timestamp within [threshold] seconds of [targetTimeSec].
  /// Returns `null` if no beat is within the magnetic snapping radius.
  double? findNearestBeat(
    double targetTimeSec,
    List<double> beats, {
    double threshold = 0.08,
  }) {
    if (beats.isEmpty || threshold <= 0.0) return null;

    double? nearest;
    double minDiff = threshold;

    for (final beat in beats) {
      final diff = (beat - targetTimeSec).abs();
      if (diff <= minDiff) {
        minDiff = diff;
        nearest = beat;
      }
    }

    return nearest;
  }
}
