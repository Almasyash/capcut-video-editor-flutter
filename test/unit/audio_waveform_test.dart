import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/audio_waveform_service.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/audio_track_item.dart';

void main() {
  group('AudioWaveformService Unit Tests', () {
    late AudioWaveformService service;

    setUp(() {
      service = AudioWaveformService.instance;
      service.clearCache();
    });

    test('generateOrganicWaveform produces deterministic and clamped values', () {
      final points1 = service.generateOrganicWaveform(seedKey: 'test_track_1', targetPoints: 100);
      final points2 = service.generateOrganicWaveform(seedKey: 'test_track_1', targetPoints: 100);
      final points3 = service.generateOrganicWaveform(seedKey: 'different_track', targetPoints: 100);

      expect(points1.length, equals(100));
      expect(points2.length, equals(100));
      expect(points1, equals(points2), reason: 'Identical seeds must produce identical waveforms');
      expect(points1, isNot(equals(points3)), reason: 'Different seeds must produce distinct waveforms');

      for (final p in points1) {
        expect(p, greaterThanOrEqualTo(0.05));
        expect(p, lessThanOrEqualTo(1.0));
      }
    });

    test('parseWavBytes correctly parses synthetic 16-bit PCM WAV data', () {
      const sampleRate = 44100;
      const durationSec = 1.0;
      final numSamples = (sampleRate * durationSec).toInt();
      const numChannels = 1;
      const bitsPerSample = 16;
      final dataSize = numSamples * numChannels * (bitsPerSample ~/ 8);
      final totalSize = 36 + dataSize;

      final byteData = ByteData(44 + dataSize);
      // 'RIFF'
      byteData.setUint8(0, 0x52);
      byteData.setUint8(1, 0x49);
      byteData.setUint8(2, 0x46);
      byteData.setUint8(3, 0x46);
      byteData.setUint32(4, totalSize, Endian.little);
      // 'WAVE'
      byteData.setUint8(8, 0x57);
      byteData.setUint8(9, 0x41);
      byteData.setUint8(10, 0x56);
      byteData.setUint8(11, 0x45);
      // 'fmt '
      byteData.setUint8(12, 0x66);
      byteData.setUint8(13, 0x6d);
      byteData.setUint8(14, 0x74);
      byteData.setUint8(15, 0x20);
      byteData.setUint32(16, 16, Endian.little);
      byteData.setUint16(20, 1, Endian.little); // PCM
      byteData.setUint16(22, numChannels, Endian.little);
      byteData.setUint32(24, sampleRate, Endian.little);
      byteData.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
      byteData.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
      byteData.setUint16(34, bitsPerSample, Endian.little);
      // 'data'
      byteData.setUint8(36, 0x64);
      byteData.setUint8(37, 0x61);
      byteData.setUint8(38, 0x74);
      byteData.setUint8(39, 0x61);
      byteData.setUint32(40, dataSize, Endian.little);

      // Generate 440 Hz sine wave
      int offset = 44;
      for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final sample = (math.sin(2 * math.pi * 440 * t) * 20000).toInt();
        byteData.setInt16(offset, sample, Endian.little);
        offset += 2;
      }

      final wavBytes = byteData.buffer.asUint8List();
      final points = service.parseWavBytes(wavBytes, targetPoints: 64);

      expect(points.length, equals(64));
      for (final p in points) {
        expect(p, greaterThanOrEqualTo(0.08));
        expect(p, lessThanOrEqualTo(1.0));
      }
    });

    test('parseWavBytes handles malformed or truncated audio bytes gracefully', () {
      final truncated = Uint8List.fromList([0x52, 0x49, 0x46, 0x46]); // Only 'RIFF'
      final points = service.parseWavBytes(truncated, targetPoints: 40);

      expect(points.length, equals(40));
      expect(points.first, greaterThan(0.0));
    });

    test('resampleSlicedWaveform accurately slices waveform between trimStart and trimEnd', () {
      // 100 ascending points: 0.01, 0.02, ..., 1.0
      final fullPoints = List.generate(100, (i) => (i + 1) / 100.0);
      const totalDuration = Duration(seconds: 100);

      // Slicing Part 1: First 50% (0s -> 50s)
      final part1 = service.resampleSlicedWaveform(
        fullWaveform: fullPoints,
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 50),
        totalDuration: totalDuration,
        barCount: 50,
      );

      expect(part1.length, equals(50));
      expect(part1.first, closeTo(0.01, 0.05));
      expect(part1.last, closeTo(0.50, 0.05));

      // Slicing Part 2: Second 50% (50s -> 100s)
      final part2 = service.resampleSlicedWaveform(
        fullWaveform: fullPoints,
        trimStart: const Duration(seconds: 50),
        trimEnd: const Duration(seconds: 100),
        totalDuration: totalDuration,
        barCount: 50,
      );

      expect(part2.length, equals(50));
      expect(part2.first, closeTo(0.50, 0.05));
      expect(part2.last, closeTo(1.0, 0.05));
    });

    test('resampleSlicedWaveform handles edge cases like 0 barCount or empty waveform', () {
      final res1 = service.resampleSlicedWaveform(
        fullWaveform: const [],
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        totalDuration: const Duration(seconds: 10),
        barCount: 10,
      );
      expect(res1.length, equals(10));

      final res2 = service.resampleSlicedWaveform(
        fullWaveform: [0.5, 0.8],
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 10),
        totalDuration: const Duration(seconds: 10),
        barCount: 0,
      );
      expect(res2.length, equals(1));
    });

    test('getWaveformSync caches generated waveforms properly', () {
      final p1 = service.getWaveformSync(cacheKey: 'unique_cache_key_abc');
      final p2 = service.getWaveformSync(cacheKey: 'unique_cache_key_abc');

      expect(identical(p1, p2), isTrue);

      service.clearCache();
      final p3 = service.getWaveformSync(cacheKey: 'unique_cache_key_abc');
      expect(p3, equals(p1));
    });
  });

  group('AudioTrackItem Waveform Rendering Widget Tests', () {
    testWidgets('AudioTrackItem renders enhanced waveform and trim handles', (WidgetTester tester) async {
      final viewModel = EditorViewModel();
      final track = AudioTrack(
        id: 'test_audio_track_1',
        assetId: 'test_asset_1',
        title: 'Cyberpunk Synth Beat',
        artist: 'Producer X',
        duration: const Duration(seconds: 60),
        trimStart: const Duration(seconds: 10),
        trimEnd: const Duration(seconds: 40),
        volume: 0.9,
        waveformPoints: List.generate(80, (i) => 0.1 + (i % 10) * 0.08),
      );

      viewModel.addAudioTrack(track);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: AudioTrackItem(
                  audioTrack: track,
                  pixelsPerSecond: 50.0,
                  viewModel: viewModel,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Cyberpunk Synth Beat'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      viewModel.dispose();
    });

    testWidgets('AudioTrackItem renders properly when muted', (WidgetTester tester) async {
      final viewModel = EditorViewModel();
      const track = AudioTrack(
        id: 'muted_track',
        assetId: 'muted_asset',
        title: 'Muted Beat',
        duration: Duration(seconds: 30),
        isMuted: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioTrackItem(
              audioTrack: track,
              pixelsPerSecond: 50.0,
              viewModel: viewModel,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('MUTED'), findsOneWidget);
      viewModel.dispose();
    });
  });
}
