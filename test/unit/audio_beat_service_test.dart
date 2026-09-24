import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/audio_beat_service.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';

void main() {
  group('AudioBeatService Tests', () {
    late AudioBeatService service;

    setUp(() {
      service = AudioBeatService.instance;
    });

    test('detectBeats returns empty list for empty waveforms or zero duration', () {
      final beatsEmpty = service.detectBeats(
        waveformPoints: [],
        duration: const Duration(seconds: 10),
      );
      expect(beatsEmpty, isEmpty);

      final beatsZeroDuration = service.detectBeats(
        waveformPoints: [0.5, 0.8, 0.2],
        duration: Duration.zero,
      );
      expect(beatsZeroDuration, isEmpty);
    });

    test('detectBeats identifies rhythmic peak transients accurately', () {
      // 100 points across 10 seconds -> dt = 0.1s
      // Introduce sharp rhythmic drum peaks every 1.0 second (every 10 points)
      final points = List<double>.filled(100, 0.1);
      for (int i = 10; i < 100; i += 10) {
        points[i] = 0.95; // strong drum beat spike
      }

      final strongBeats = service.detectBeats(
        waveformPoints: points,
        duration: const Duration(seconds: 10),
        sensitivity: BeatSensitivity.strongDownbeats,
      );

      expect(strongBeats, isNotEmpty);
      // Beats should be spaced around ~1.0s
      for (int i = 1; i < strongBeats.length; i++) {
        final interval = strongBeats[i] - strongBeats[i - 1];
        expect(interval, greaterThanOrEqualTo(0.60)); // minimum refractory window
      }
    });

    test('Fast Beats sensitivity detects more subdivisions than Strong Beats', () {
      // Create alternating rhythm: strong beats at 1s, medium hits at 0.5s
      final points = List<double>.filled(100, 0.1);
      for (int i = 5; i < 100; i += 5) {
        points[i] = (i % 10 == 0) ? 0.95 : 0.65;
      }

      final strongBeats = service.detectBeats(
        waveformPoints: points,
        duration: const Duration(seconds: 10),
        sensitivity: BeatSensitivity.strongDownbeats,
      );

      final fastBeats = service.detectBeats(
        waveformPoints: points,
        duration: const Duration(seconds: 10),
        sensitivity: BeatSensitivity.fastBeats,
      );

      expect(fastBeats.length, greaterThanOrEqualTo(strongBeats.length));
    });

    test('findNearestBeat performs magnetic snapping within threshold', () {
      final beats = [1.0, 2.0, 3.0, 4.0, 5.0];

      // Within 0.08s threshold -> snaps to 2.0
      expect(service.findNearestBeat(2.05, beats, threshold: 0.08), closeTo(2.0, 0.001));
      expect(service.findNearestBeat(1.94, beats, threshold: 0.08), closeTo(2.0, 0.001));

      // Beyond 0.08s threshold -> returns null
      expect(service.findNearestBeat(2.15, beats, threshold: 0.08), isNull);
      expect(service.findNearestBeat(0.5, beats, threshold: 0.08), isNull);
    });
  });

  group('AudioTrack Beat Properties & Serialization', () {
    test('visibleTimelineBeats handles trimming and track start time', () {
      const track = AudioTrack(
        id: 'track_1',
        assetId: 'asset_1',
        name: 'Test Beat Track',
        duration: Duration(seconds: 10),
        startTime: Duration(seconds: 2), // starts at 2s on timeline
        trimStart: Duration(seconds: 1), // starts at 1s in source
        trimEnd: Duration(seconds: 7),   // ends at 7s in source
        beats: [0.5, 1.5, 3.0, 5.5, 8.5],
      );

      // Beats within [1.0, 7.0] source range are: 1.5, 3.0, 5.5
      // 0.5 (before trimStart) and 8.5 (after trimEnd) should be excluded.
      // On timeline:
      // 1.5s -> (1.5 - 1.0) + 2.0 = 2.5s
      // 3.0s -> (3.0 - 1.0) + 2.0 = 4.0s
      // 5.5s -> (5.5 - 1.0) + 2.0 = 6.5s
      final timelineBeats = track.visibleTimelineBeats;
      expect(timelineBeats.length, equals(3));
      expect(timelineBeats[0], closeTo(2.5, 0.01));
      expect(timelineBeats[1], closeTo(4.0, 0.01));
      expect(timelineBeats[2], closeTo(6.5, 0.01));
    });

    test('AudioTrack serializes and deserializes beats and showBeats cleanly', () {
      const original = AudioTrack(
        id: 'track_beats_json',
        assetId: 'asset_json',
        name: 'Beats Serialization',
        duration: Duration(seconds: 15),
        beats: [1.2, 2.4, 3.6, 4.8],
        showBeats: true,
      );

      final json = original.toJson();
      expect(json['beats'], equals([1.2, 2.4, 3.6, 4.8]));
      expect(json['showBeats'], isTrue);

      final restored = AudioTrack.fromJson(json);
      expect(restored.beats, equals([1.2, 2.4, 3.6, 4.8]));
      expect(restored.showBeats, isTrue);
    });
  });
}
