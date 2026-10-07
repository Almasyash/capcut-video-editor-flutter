import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Professional AudioTrack Model & Serialization', () {
    test('AudioTrack enforces default values, volume range, and fades', () {
      const track = AudioTrack(
        id: 'track_1',
        assetId: 'asset_1',
        name: 'Cinematic Score',
        artist: 'Composer',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 10),
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(seconds: 7),
        volume: 1.5,
        fadeInDuration: Duration(seconds: 2),
        fadeOutDuration: Duration(seconds: 1),
      );

      expect(track.volume, equals(1.5));
      expect(track.isMuted, isFalse);
      expect(track.effectiveDuration, equals(const Duration(seconds: 6)));
      expect(track.fadeInDuration, equals(const Duration(seconds: 2)));
      expect(track.fadeOutDuration, equals(const Duration(seconds: 1)));
      expect(track.effectiveFadeInDuration, equals(const Duration(seconds: 2)));
      expect(track.effectiveFadeOutDuration, equals(const Duration(seconds: 1)));
    });

    test('AudioTrack safely clamps fades exceeding clip duration', () {
      // Effective duration is 4 seconds
      const track = AudioTrack(
        id: 'track_fade_clamp',
        assetId: 'asset_1',
        name: 'Short Sting',
        startTime: Duration.zero,
        duration: Duration(seconds: 10),
        trimStart: Duration(seconds: 2),
        trimEnd: Duration(seconds: 6),
        fadeInDuration: Duration(seconds: 3),
        fadeOutDuration: Duration(seconds: 3), // Sum is 6s > 4s
      );

      expect(track.effectiveDuration, equals(const Duration(seconds: 4)));
      // fadeIn gets up to 3s, fadeOut gets remaining 1s
      expect(track.effectiveFadeInDuration, equals(const Duration(seconds: 3)));
      expect(track.effectiveFadeOutDuration, equals(const Duration(seconds: 1)));
      expect(
        track.effectiveFadeInDuration + track.effectiveFadeOutDuration,
        lessThanOrEqualTo(track.effectiveDuration),
      );
    });

    test('AudioTrack JSON serialization round-trip maintains exact audio state', () {
      const track = AudioTrack(
        id: 'track_json',
        assetId: 'asset_music_1',
        name: 'Background Beat',
        artist: 'Audio Artist',
        startTime: Duration(milliseconds: 1500),
        duration: Duration(milliseconds: 12000),
        trimStart: Duration(milliseconds: 1000),
        trimEnd: Duration(milliseconds: 9000),
        volume: 1.75,
        speed: 1.0,
        isMuted: true,
        isVisible: true,
        fadeInDuration: Duration(milliseconds: 1200),
        fadeOutDuration: Duration(milliseconds: 800),
        waveformPoints: [0.1, 0.4, 0.8, 0.6, 0.2],
      );

      final json = track.toJson();
      expect(json['fadeInMs'], equals(1200));
      expect(json['fadeOutMs'], equals(800));
      expect(json['isMuted'], isTrue);
      expect(json['volume'], equals(1.75));

      final restored = AudioTrack.fromJson(json);
      expect(restored.id, equals(track.id));
      expect(restored.assetId, equals(track.assetId));
      expect(restored.name, equals(track.name));
      expect(restored.startTime, equals(track.startTime));
      expect(restored.duration, equals(track.duration));
      expect(restored.trimStart, equals(track.trimStart));
      expect(restored.trimEnd, equals(track.trimEnd));
      expect(restored.volume, equals(1.75));
      expect(restored.isMuted, isTrue);
      expect(restored.fadeInDuration, equals(const Duration(milliseconds: 1200)));
      expect(restored.fadeOutDuration, equals(const Duration(milliseconds: 800)));
      expect(restored.waveformPoints, equals([0.1, 0.4, 0.8, 0.6, 0.2]));
    });

    test('AudioTrack backward compatibility with legacy JSON without fade fields', () {
      final legacyJson = {
        'id': 'legacy_track',
        'assetId': 'legacy_asset',
        'name': 'Old Song',
        'startTimeMs': 0,
        'durationMs': 5000,
        'trimStartMs': 0,
        'trimEndMs': 5000,
        'volume': 0.8,
        'isMuted': false,
      };

      final restored = AudioTrack.fromJson(legacyJson);
      expect(restored.id, equals('legacy_track'));
      expect(restored.volume, equals(0.8));
      expect(restored.fadeInDuration, equals(Duration.zero));
      expect(restored.fadeOutDuration, equals(Duration.zero));
      expect(restored.effectiveFadeInDuration, equals(Duration.zero));
      expect(restored.effectiveFadeOutDuration, equals(Duration.zero));
    });
  });

  group('EditorViewModel Audio Editing Operations', () {
    late EditorViewModel viewModel;

    setUp(() {
      viewModel = EditorViewModel();

      // Add a test audio track
      viewModel.addAudioTrack(const AudioTrack(
        id: 'audio_track_1',
        assetId: 'asset_aud_1',
        name: 'Music Bed',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 10),
        trimStart: Duration.zero,
        trimEnd: Duration(seconds: 10),
        volume: 1.0,
        fadeInDuration: Duration(seconds: 1),
        fadeOutDuration: Duration(seconds: 1),
      ));
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Volume control clamps between 0.0 and 2.0 (0% - 200%)', () {
      viewModel.selectAudioTrack('audio_track_1');

      // Normal amplification
      viewModel.setAudioTrackVolume(1.5);
      expect(viewModel.selectedAudioTrack!.volume, equals(1.5));

      // Maximum amplification (200%)
      viewModel.setAudioTrackVolume(2.5); // Exceeds 2.0
      expect(viewModel.selectedAudioTrack!.volume, equals(2.0));

      // Minimum silence (0%)
      viewModel.setAudioTrackVolume(-0.5); // Below 0.0
      expect(viewModel.selectedAudioTrack!.volume, equals(0.0));
    });

    test('Mute toggling maintains track on timeline as a logical property', () {
      viewModel.selectAudioTrack('audio_track_1');
      expect(viewModel.selectedAudioTrack!.isMuted, isFalse);

      // Toggle mute ON
      viewModel.toggleAudioMute();
      expect(viewModel.selectedAudioTrack!.isMuted, isTrue);
      expect(viewModel.audioTracks.length, equals(1)); // Track remains on timeline

      // Toggle mute OFF
      viewModel.toggleAudioMute();
      expect(viewModel.selectedAudioTrack!.isMuted, isFalse);
    });

    test('Fade in and fade out adjustments with duration constraints', () {
      viewModel.selectAudioTrack('audio_track_1');

      viewModel.setAudioTrackFadeIn(const Duration(seconds: 3));
      expect(viewModel.selectedAudioTrack!.fadeInDuration, equals(const Duration(seconds: 3)));

      viewModel.setAudioTrackFadeOut(const Duration(seconds: 2));
      expect(viewModel.selectedAudioTrack!.fadeOutDuration, equals(const Duration(seconds: 2)));

      // Setting excessive fade duration clamps so fadeIn + fadeOut <= effectiveDuration (10s - 2s = 8s)
      viewModel.setAudioTrackFadeIn(const Duration(seconds: 20));
      expect(viewModel.selectedAudioTrack!.fadeInDuration, equals(const Duration(seconds: 8)));

      // Setting fadeOut to zero allows fadeIn to reach full effectiveDuration (10s)
      viewModel.setAudioTrackFadeOut(Duration.zero);
      viewModel.setAudioTrackFadeIn(const Duration(seconds: 20));
      expect(viewModel.selectedAudioTrack!.fadeInDuration, equals(const Duration(seconds: 10)));
    });

    test('Trimming audio clamps fades to new effective duration', () {
      viewModel.selectAudioTrack('audio_track_1');
      viewModel.setAudioTrackFadeIn(const Duration(seconds: 3));
      viewModel.setAudioTrackFadeOut(const Duration(seconds: 3));

      // Trim track duration down to 4 seconds (trimStart: 2s, trimEnd: 6s)
      viewModel.updateAudioTrim(
        'audio_track_1',
        const Duration(seconds: 2),
        const Duration(seconds: 6),
      );

      final trimmed = viewModel.selectedAudioTrack!;
      expect(trimmed.effectiveDuration, equals(const Duration(seconds: 4)));
      expect(trimmed.fadeInDuration, lessThanOrEqualTo(const Duration(seconds: 4)));
      expect(trimmed.fadeOutDuration, lessThanOrEqualTo(const Duration(seconds: 4)));
    });

    test('Audio Split at playhead creates two independent clips with preserved fades', () {
      // Audio starts at 1s, duration 10s (ends at 11s)
      viewModel.selectAudioTrack('audio_track_1');
      viewModel.setAudioTrackFadeIn(const Duration(seconds: 2));
      viewModel.setAudioTrackFadeOut(const Duration(seconds: 3));

      // Position playhead at 5.0s (4s into the audio track)
      viewModel.seekTo(5.0);
      viewModel.splitAudioAtPlayhead();

      expect(viewModel.audioTracks.length, equals(2));

      final partA = viewModel.audioTracks[0];
      final partB = viewModel.audioTracks[1];

      // Part A checks
      expect(partA.startTime, equals(const Duration(seconds: 1)));
      expect(partA.effectiveDuration, equals(const Duration(seconds: 4)));
      expect(partA.trimStart, equals(Duration.zero));
      expect(partA.trimEnd, equals(const Duration(seconds: 4)));
      expect(partA.fadeInDuration, equals(const Duration(seconds: 2))); // Inherited fadeIn
      expect(partA.fadeOutDuration, equals(Duration.zero)); // Reset fadeOut

      // Part B checks
      expect(partB.startTime, equals(const Duration(seconds: 5)));
      expect(partB.effectiveDuration, equals(const Duration(seconds: 6)));
      expect(partB.trimStart, equals(const Duration(seconds: 4)));
      expect(partB.trimEnd, equals(const Duration(seconds: 10)));
      expect(partB.fadeInDuration, equals(Duration.zero)); // Reset fadeIn
      expect(partB.fadeOutDuration, equals(const Duration(seconds: 3))); // Inherited fadeOut

      // Both reference same source asset safely
      expect(partA.assetId, equals(partB.assetId));

      // Undo restores original clip
      expect(viewModel.canUndo, isTrue);
      viewModel.undo();
      expect(viewModel.audioTracks.length, equals(1));
      expect(viewModel.audioTracks.first.effectiveDuration, equals(const Duration(seconds: 10)));
      expect(viewModel.audioTracks.first.fadeInDuration, equals(const Duration(seconds: 2)));
      expect(viewModel.audioTracks.first.fadeOutDuration, equals(const Duration(seconds: 3)));

      // Redo restores split
      expect(viewModel.canRedo, isTrue);
      viewModel.redo();
      expect(viewModel.audioTracks.length, equals(2));
    });

    test('Duplicate audio track preserves volume, fades, and speed', () {
      viewModel.selectAudioTrack('audio_track_1');
      viewModel.setAudioTrackVolume(1.4);
      viewModel.setAudioTrackFadeIn(const Duration(milliseconds: 1500));
      viewModel.setAudioTrackFadeOut(const Duration(milliseconds: 2500));

      viewModel.duplicateSelectedAudioTrack();

      expect(viewModel.audioTracks.length, equals(2));
      final duplicate = viewModel.audioTracks.last;

      expect(duplicate.id, isNot(equals('audio_track_1')));
      expect(duplicate.assetId, equals('asset_aud_1'));
      expect(duplicate.volume, equals(1.4));
      expect(duplicate.fadeInDuration, equals(const Duration(milliseconds: 1500)));
      expect(duplicate.fadeOutDuration, equals(const Duration(milliseconds: 2500)));
      expect(duplicate.startTime, equals(const Duration(seconds: 11))); // Appended after original
    });

    test('Move audio track modifies timeline startTime without affecting source trims', () {
      viewModel.selectAudioTrack('audio_track_1');
      viewModel.updateAudioTrim(
        'audio_track_1',
        const Duration(seconds: 2),
        const Duration(seconds: 8),
      );

      // Move audio to 4 seconds
      viewModel.moveAudioTrack('audio_track_1', const Duration(seconds: 4));

      final moved = viewModel.selectedAudioTrack!;
      expect(moved.startTime, equals(const Duration(seconds: 4)));
      // Source trims must remain completely untouched
      expect(moved.trimStart, equals(const Duration(seconds: 2)));
      expect(moved.trimEnd, equals(const Duration(seconds: 8)));
    });

    test('Main video clip volume control (0% - 200%) and mute toggle', () {
      expect(viewModel.videoClips.isNotEmpty, isTrue);
      viewModel.selectClip(0);
      expect(viewModel.selectedClip!.effectiveVolume, equals(1.0));

      // Set clip volume to 180%
      viewModel.setClipVolume(1.8);
      expect(viewModel.selectedClip!.volume, equals(1.8));
      expect(viewModel.selectedClip!.effectiveVolume, equals(1.8));

      // Toggle clip mute
      viewModel.toggleClipMute();
      expect(viewModel.selectedClip!.isMuted, isTrue);
      expect(viewModel.selectedClip!.effectiveVolume, equals(0.0));

      // Unmute
      viewModel.toggleClipMute();
      expect(viewModel.selectedClip!.isMuted, isFalse);
      expect(viewModel.selectedClip!.effectiveVolume, equals(1.8));
    });

    test('PIP overlay video audio volume and mute controls', () {
      const overlay = OverlayClip(
        id: 'pip_video_1',
        title: 'Reaction Cam',
        startTime: Duration(seconds: 2),
        duration: Duration(seconds: 5),
        volume: 1.0,
        isMuted: false,
        isPhoto: false,
      );
      viewModel.addOverlayClip(overlay);

      expect(viewModel.overlayClips.length, equals(1));

      // Adjust overlay volume to 1.25
      viewModel.setOverlayVolume(1.25, index: 0);
      expect(viewModel.overlayClips.first.volume, equals(1.25));

      // Toggle overlay mute
      viewModel.toggleOverlayMute(index: 0);
      expect(viewModel.overlayClips.first.isMuted, isTrue);

      // Set overlay fades
      viewModel.setOverlayFadeIn(1.0, index: 0);
      viewModel.setOverlayFadeOut(0.5, index: 0);
      expect(viewModel.overlayClips.first.fadeInDurationSec, equals(1.0));
      expect(viewModel.overlayClips.first.fadeOutDurationSec, equals(0.5));
    });
  });

  group('Multi-Track Audio Mixing & Export Payload Serialization', () {
    test('Project with multiple simultaneous audio sources serializes correctly', () {
      final project = Project(
        id: 'proj_multitrack',
        name: 'Music Video',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        videoClips: const [
          VideoClip(
            id: 'clip_1',
            assetId: 'asset_v1',
            title: 'Dance Video',
            originalDuration: Duration(seconds: 20),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 20),
            volume: 0.8,
            isMuted: false,
            previewGradient: [],
          ),
        ],
        audioTracks: const [
          AudioTrack(
            id: 'track_music',
            assetId: 'asset_m1',
            name: 'Upbeat Music',
            startTime: Duration.zero,
            duration: Duration(seconds: 20),
            trimStart: Duration.zero,
            trimEnd: Duration(seconds: 20),
            volume: 1.0,
            fadeInDuration: Duration(seconds: 2),
            fadeOutDuration: Duration(seconds: 3),
          ),
          AudioTrack(
            id: 'track_voice',
            assetId: 'asset_v2',
            name: 'Voiceover',
            startTime: Duration(seconds: 4),
            duration: Duration(seconds: 8),
            trimStart: Duration(seconds: 1),
            trimEnd: Duration(seconds: 7),
            volume: 1.6, // Amplified
            fadeInDuration: Duration(milliseconds: 500),
            fadeOutDuration: Duration(milliseconds: 500),
          ),
        ],
        overlayClips: const [
          OverlayClip(
            id: 'pip_audio',
            title: 'Interview PIP',
            startTime: Duration(seconds: 10),
            duration: Duration(seconds: 6),
            volume: 0.9,
            isMuted: false,
            fadeInDurationSec: 0.5,
            fadeOutDurationSec: 0.5,
            isPhoto: false,
          ),
        ],
      );

      final jsonStr = jsonEncode(project.toJson());
      final restored = Project.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

      expect(restored.videoClips.length, equals(1));
      expect(restored.videoClips[0].volume, equals(0.8));

      expect(restored.audioTracks.length, equals(2));
      expect(restored.audioTracks[0].name, equals('Upbeat Music'));
      expect(restored.audioTracks[0].fadeInDuration, equals(const Duration(seconds: 2)));
      expect(restored.audioTracks[0].fadeOutDuration, equals(const Duration(seconds: 3)));

      expect(restored.audioTracks[1].name, equals('Voiceover'));
      expect(restored.audioTracks[1].volume, equals(1.6));
      expect(restored.audioTracks[1].startTime, equals(const Duration(seconds: 4)));
      expect(restored.audioTracks[1].effectiveDuration, equals(const Duration(seconds: 6)));

      expect(restored.overlayClips.length, equals(1));
      expect(restored.overlayClips[0].volume, equals(0.9));
    });
  });
}
