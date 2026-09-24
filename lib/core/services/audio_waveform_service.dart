import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Professional Audio Waveform Service
///
/// Features:
/// 1. True 16-bit / 8-bit PCM RIFF WAV parsing and peak/RMS downsampling.
/// 2. High-density deterministic audio envelope generator for non-WAV media.
/// 3. Waveform slicing and zoom-adaptive resampling for timeline rendering.
/// 4. In-memory caching by assetId / filePath to prevent redundant computation.
class AudioWaveformService {
  AudioWaveformService._();
  static final AudioWaveformService instance = AudioWaveformService._();

  final Map<String, List<double>> _cache = {};

  /// Default number of waveform amplitude sample bins
  static const int defaultTargetPoints = 128;

  /// Retrieves or extracts a normalized waveform (values 0.0 - 1.0) for a given file
  Future<List<double>> getWaveformForFile(
    File file, {
    String? cacheKey,
    int targetPoints = defaultTargetPoints,
  }) async {
    final key = cacheKey ?? file.path;
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    List<double> points;
    try {
      if (file.existsSync() && file.path.toLowerCase().endsWith('.wav')) {
        final bytes = await file.readAsBytes();
        points = parseWavBytes(bytes, targetPoints: targetPoints);
      } else if (file.existsSync()) {
        final length = file.lengthSync();
        points = generateOrganicWaveform(
          seedKey: '${file.path}_$length',
          targetPoints: targetPoints,
        );
      } else {
        points = generateOrganicWaveform(
          seedKey: key,
          targetPoints: targetPoints,
        );
      }
    } catch (e) {
      debugPrint('[AudioWaveformService] Error extracting waveform from ${file.path}: $e');
      points = generateOrganicWaveform(seedKey: key, targetPoints: targetPoints);
    }

    _cache[key] = points;
    return points;
  }

  /// Synchronously retrieves a cached waveform or generates a deterministic fallback
  List<double> getWaveformSync({
    required String cacheKey,
    String? localPath,
    Duration? duration,
    int targetPoints = defaultTargetPoints,
  }) {
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    if (localPath != null) {
      try {
        final file = File(localPath);
        if (file.existsSync() && file.path.toLowerCase().endsWith('.wav')) {
          final bytes = file.readAsBytesSync();
          final points = parseWavBytes(bytes, targetPoints: targetPoints);
          _cache[cacheKey] = points;
          return points;
        }
      } catch (_) {}
    }

    final points = generateOrganicWaveform(
      seedKey: cacheKey,
      targetPoints: targetPoints,
    );
    _cache[cacheKey] = points;
    return points;
  }

  /// Parses raw 16-bit or 8-bit PCM RIFF WAV audio bytes and computes normalized peak amplitudes
  List<double> parseWavBytes(Uint8List bytes, {int targetPoints = defaultTargetPoints}) {
    if (bytes.length < 44) {
      return generateOrganicWaveform(seedKey: 'short_wav_${bytes.length}', targetPoints: targetPoints);
    }

    // Verify RIFF & WAVE header
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46 || // 'RIFF'
        bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) { // 'WAVE'
      return generateOrganicWaveform(seedKey: 'invalid_wav_${bytes.length}', targetPoints: targetPoints);
    }

    final byteData = ByteData.sublistView(bytes);
    int offset = 12;
    int numChannels = 1;
    int bitsPerSample = 16;
    int dataOffset = -1;
    int dataSize = -1;

    // Iterate through chunks to find 'fmt ' and 'data'
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = byteData.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        if (offset + 8 + 16 <= bytes.length) {
          numChannels = byteData.getUint16(offset + 8 + 2, Endian.little);
          bitsPerSample = byteData.getUint16(offset + 8 + 14, Endian.little);
        }
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = math.min(chunkSize, bytes.length - dataOffset);
        break;
      }

      offset += 8 + chunkSize;
    }

    if (dataOffset == -1 || dataSize <= 0) {
      return generateOrganicWaveform(seedKey: 'no_data_${bytes.length}', targetPoints: targetPoints);
    }

    final bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) return generateOrganicWaveform(seedKey: 'invalid_bps', targetPoints: targetPoints);

    final totalSamples = dataSize ~/ (bytesPerSample * numChannels);
    if (totalSamples <= 0) return generateOrganicWaveform(seedKey: 'zero_samples', targetPoints: targetPoints);

    final samplesPerBin = (totalSamples / targetPoints).ceil();
    final peaks = <double>[];
    double maxGlobalPeak = 0.0;

    for (int bin = 0; bin < targetPoints; bin++) {
      final startSample = bin * samplesPerBin;
      final endSample = math.min(startSample + samplesPerBin, totalSamples);

      if (startSample >= totalSamples) {
        peaks.add(0.05);
        continue;
      }

      double binPeak = 0.0;
      for (int s = startSample; s < endSample; s++) {
        final sampleOffset = dataOffset + s * (bytesPerSample * numChannels);
        if (sampleOffset + bytesPerSample > bytes.length) break;

        double sampleVal = 0.0;
        if (bitsPerSample == 16) {
          sampleVal = byteData.getInt16(sampleOffset, Endian.little).abs() / 32768.0;
        } else if (bitsPerSample == 8) {
          sampleVal = ((byteData.getUint8(sampleOffset) - 128).abs()) / 128.0;
        }

        if (sampleVal > binPeak) {
          binPeak = sampleVal;
        }
      }

      if (binPeak > maxGlobalPeak) {
        maxGlobalPeak = binPeak;
      }
      peaks.add(binPeak);
    }

    // Normalize peaks between 0.12 and 1.0 (with minimum visual height for silence)
    final scale = maxGlobalPeak > 0.001 ? (1.0 / maxGlobalPeak) : 1.0;
    return peaks.map((p) {
      final norm = (p * scale).clamp(0.0, 1.0);
      return math.max(0.08, norm);
    }).toList();
  }

  /// Generates a realistic, multi-frequency organic audio waveform envelope
  ///
  /// Combines rhythmic percussion beats, vocal envelope arcs, and musical modulation
  /// to create natural-looking waveforms rather than flat random white noise.
  List<double> generateOrganicWaveform({
    required String seedKey,
    int targetPoints = defaultTargetPoints,
  }) {
    final seed = seedKey.hashCode.abs();
    final random = math.Random(seed);

    final phraseCount = 2 + (seed % 3); // 2 to 4 distinct musical phrases
    final beatInterval = 4 + (seed % 5); // cadence rhythm

    final points = <double>[];
    for (int i = 0; i < targetPoints; i++) {
      final t = i / targetPoints;

      // 1. Overall phrase crescendo & decrescendo envelope
      final phraseEnv = 0.4 + 0.6 * math.sin(math.pi * phraseCount * t).abs();

      // 2. Rhythmic beat pulse
      final isBeat = (i % beatInterval == 0) || (i % beatInterval == 1);
      final beatBoost = isBeat ? (0.25 + 0.15 * random.nextDouble()) : 0.0;

      // 3. Fine-grain acoustic flutter
      final flutter = 0.15 + 0.45 * random.nextDouble();

      // 4. Attack and decay at extreme boundaries
      double edgeFade = 1.0;
      if (t < 0.04) {
        edgeFade = t / 0.04;
      } else if (t > 0.96) {
        edgeFade = (1.0 - t) / 0.04;
      }

      final amplitude = ((phraseEnv * flutter + beatBoost) * edgeFade).clamp(0.08, 0.98);
      points.add((amplitude * 100).round() / 100.0);
    }

    return points;
  }

  /// Resamples a sliced window of [fullWaveform] to exactly [barCount] display bars
  ///
  /// Takes [trimStart], [trimEnd], and [totalDuration] into account, sampling strictly
  /// within `[startFraction, endFraction]` with smooth linear interpolation.
  List<double> resampleSlicedWaveform({
    required List<double> fullWaveform,
    required Duration trimStart,
    required Duration? trimEnd,
    required Duration totalDuration,
    required int barCount,
  }) {
    if (fullWaveform.isEmpty || barCount <= 0) {
      return List.filled(math.max(1, barCount), 0.1);
    }

    final totalMs = math.max(1, totalDuration.inMilliseconds);
    final startMs = trimStart.inMilliseconds.clamp(0, totalMs);
    final endMs = (trimEnd?.inMilliseconds ?? totalMs).clamp(startMs, totalMs);

    final startFraction = startMs / totalMs;
    final endFraction = math.max(startFraction + 0.001, endMs / totalMs);
    final rangeFraction = endFraction - startFraction;

    final n = fullWaveform.length;
    final resampled = <double>[];

    for (int i = 0; i < barCount; i++) {
      final localT = (barCount > 1) ? (i / (barCount - 1)) : 0.0;
      final globalT = (startFraction + localT * rangeFraction).clamp(0.0, 0.9999);

      final indexFloat = globalT * (n - 1);
      final indexFloor = indexFloat.floor().clamp(0, n - 1);
      final indexCeil = (indexFloor + 1).clamp(0, n - 1);
      final fraction = indexFloat - indexFloor;

      final val = fullWaveform[indexFloor] * (1.0 - fraction) + fullWaveform[indexCeil] * fraction;
      resampled.add(val.clamp(0.02, 1.0));
    }

    return resampled;
  }

  /// Clears the in-memory waveform cache
  void clearCache() {
    _cache.clear();
  }
}
