import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/timeline_coordinate_system.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/timeline_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. TimelineCoordinateSystem Tests', () {
    test('timeToPixel and pixelToTime scale accurately', () {
      // 2 seconds @ 50.0 px/sec -> 100 pixels
      expect(TimelineCoordinateSystem.timeToPixel(2.0, 50.0), 100.0);
      expect(TimelineCoordinateSystem.pixelToTime(100.0, 50.0), 2.0);

      // With zoom @ 100.0 px/sec -> 2 seconds -> 200 pixels
      expect(TimelineCoordinateSystem.timeToPixel(2.0, 100.0), 200.0);
      expect(TimelineCoordinateSystem.pixelToTime(200.0, 100.0), 2.0);
    });

    test('Clamping time, pixel, and zoom bounds', () {
      // Negative offset clamped to zero
      expect(TimelineCoordinateSystem.pixelToTime(-50.0, 50.0), 0.0);
      expect(TimelineCoordinateSystem.timeToPixel(-10.0, 50.0), 0.0);

      // Clamping time
      expect(TimelineCoordinateSystem.clampTime(12.0, 10.0), 10.0);
      expect(TimelineCoordinateSystem.clampTime(-2.0, 10.0), 0.0);

      // Clamping pixel
      expect(TimelineCoordinateSystem.clampPixel(1200.0, 1000.0), 1000.0);
      expect(TimelineCoordinateSystem.clampPixel(-50.0, 1000.0), 0.0);

      // Clamping zoom
      expect(TimelineCoordinateSystem.clampZoom(10.0, min: 20.0, max: 600.0), 20.0);
      expect(TimelineCoordinateSystem.clampZoom(800.0, min: 20.0, max: 600.0), 600.0);
    });

    test('Frame conversion and snapping at 30fps', () {
      // 1 second @ 30fps = 30 frames
      expect(TimelineCoordinateSystem.timeToFrame(1.0, fps: 30.0), 30);
      expect(TimelineCoordinateSystem.frameToTime(30, fps: 30.0), 1.0);

      // Sub-frame snap
      // 1 frame = ~0.0333s. 0.04s should snap to frame 1 (0.0333s)
      final snapped = TimelineCoordinateSystem.snapToFrame(0.04, fps: 30.0);
      expect(TimelineCoordinateSystem.timeToFrame(snapped, fps: 30.0), 1);

      // Format timecode
      final tc = TimelineCoordinateSystem.formatFrameTimecode(1.5, fps: 30.0, showFpsBadge: true);
      expect(tc.contains('@ 30fps'), isTrue);
    });

    test('snapToNearestBoundary within threshold', () {
      final boundaries = [0.0, 2.0, 5.0];

      // Near 2 seconds (e.g. 2.05s is within 0.08s threshold)
      final snapped = TimelineCoordinateSystem.snapToNearestBoundary(
        2.05,
        boundaries,
        thresholdSeconds: 0.08,
      );
      expect(snapped, 2.0);

      // Far from boundary (e.g. 3.5s is > 1s away from 2.0 and 5.0)
      final notSnapped = TimelineCoordinateSystem.snapToNearestBoundary(
        3.5,
        boundaries,
        thresholdSeconds: 0.08,
      );
      expect(notSnapped, 3.5);
    });
  });

  group('2. Layer Model State & Serialization Tests', () {
    test('OverlayClip has default lock=false, visible=true and serializes cleanly', () {
      final overlay = OverlayClip(
        id: 'ov_1',
        title: 'PIP 1',
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
        localPath: '/test/image.png',
        isPhoto: true,
      );

      expect(overlay.isLocked, isFalse);
      expect(overlay.isVisible, isTrue);

      final json = overlay.toJson();
      expect(json['isLocked'], isFalse);
      expect(json['isVisible'], isTrue);

      final fromJson = OverlayClip.fromJson(json);
      expect(fromJson.isLocked, isFalse);
      expect(fromJson.isVisible, isTrue);

      // Backward compatibility when keys are absent
      final legacyJson = Map<String, dynamic>.from(json)
        ..remove('isLocked')
        ..remove('isVisible');
      final legacyOverlay = OverlayClip.fromJson(legacyJson);
      expect(legacyOverlay.isLocked, isFalse);
      expect(legacyOverlay.isVisible, isTrue);

      // CopyWith with modifications
      final modified = overlay.copyWith(isLocked: true, isVisible: false);
      expect(modified.isLocked, isTrue);
      expect(modified.isVisible, isFalse);
    });

    test('TextOverlay has default lock=false, visible=true and serializes cleanly', () {
      final text = TextOverlay(
        id: 'txt_1',
        text: 'Sample Text',
        startTime: Duration.zero,
        duration: const Duration(seconds: 4),
      );

      expect(text.isLocked, isFalse);
      expect(text.isVisible, isTrue);

      final json = text.toJson();
      expect(json['isLocked'], isFalse);
      expect(json['isVisible'], isTrue);

      final fromJson = TextOverlay.fromJson(json);
      expect(fromJson.isLocked, isFalse);
      expect(fromJson.isVisible, isTrue);

      // Backward compatibility
      final legacyJson = Map<String, dynamic>.from(json)
        ..remove('isLocked')
        ..remove('isVisible');
      final legacyText = TextOverlay.fromJson(legacyJson);
      expect(legacyText.isLocked, isFalse);
      expect(legacyText.isVisible, isTrue);

      // CopyWith
      final modified = text.copyWith(isLocked: true, isVisible: false);
      expect(modified.isLocked, isTrue);
      expect(modified.isVisible, isFalse);
    });

    test('VideoClip has default lock=false, visible=true and serializes cleanly', () {
      final clip = VideoClip(
        id: 'vid_1',
        assetId: 'asset_vid_1',
        title: 'Video 1',
        originalDuration: const Duration(seconds: 5),
        trimStart: Duration.zero,
        trimEnd: const Duration(seconds: 5),
        previewGradient: const [Color(0xFF000000), Color(0xFF111111)],
      );

      expect(clip.isLocked, isFalse);
      expect(clip.isVisible, isTrue);

      final json = clip.toJson();
      expect(json['isLocked'], isFalse);
      expect(json['isVisible'], isTrue);

      final fromJson = VideoClip.fromJson(json);
      expect(fromJson.isLocked, isFalse);
      expect(fromJson.isVisible, isTrue);

      // Backward compatibility
      final legacyJson = Map<String, dynamic>.from(json)
        ..remove('isLocked')
        ..remove('isVisible');
      final legacyClip = VideoClip.fromJson(legacyJson);
      expect(legacyClip.isLocked, isFalse);
      expect(legacyClip.isVisible, isTrue);
    });

    test('AudioTrack has default lock=false, visible=true and serializes cleanly', () {
      final audio = AudioTrack(
        id: 'aud_1',
        assetId: 'asset_1',
        name: 'Background Music',
        duration: const Duration(seconds: 10),
      );

      expect(audio.isLocked, isFalse);
      expect(audio.isVisible, isTrue);

      final json = audio.toJson();
      expect(json['isLocked'], isFalse);
      expect(json['isVisible'], isTrue);

      final fromJson = AudioTrack.fromJson(json);
      expect(fromJson.isLocked, isFalse);
      expect(fromJson.isVisible, isTrue);

      // Backward compatibility
      final legacyJson = Map<String, dynamic>.from(json)
        ..remove('isLocked')
        ..remove('isVisible');
      final legacyAudio = AudioTrack.fromJson(legacyJson);
      expect(legacyAudio.isLocked, isFalse);
      expect(legacyAudio.isVisible, isTrue);
    });
  });

  group('3. EditorViewModel Layer Lock & Visibility Management Tests', () {
    test('Toggle lock on Video Clip', () {
      final vm = EditorViewModel();
      expect(vm.videoClips.isNotEmpty, isTrue);
      final clipId = vm.videoClips.first.id;

      expect(vm.videoClips.first.isLocked, isFalse);
      vm.toggleClipLock(clipId);
      expect(vm.videoClips.first.isLocked, isTrue);
      vm.toggleClipLock(clipId);
      expect(vm.videoClips.first.isLocked, isFalse);
      vm.dispose();
    });

    test('Toggle lock on Overlay Clip', () {
      final vm = EditorViewModel();
      final overlay = OverlayClip(
        id: 'test_ov',
        title: 'Overlay',
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
        localPath: '/path/test.png',
        isPhoto: true,
      );
      vm.addOverlayClip(overlay);

      expect(vm.overlayClips.first.isLocked, isFalse);
      vm.toggleOverlayLock('test_ov');
      expect(vm.overlayClips.first.isLocked, isTrue);
      vm.toggleOverlayLock('test_ov');
      expect(vm.overlayClips.first.isLocked, isFalse);
      vm.dispose();
    });

    test('Toggle lock on Text Overlay', () {
      final vm = EditorViewModel();
      for (final t in List<TextOverlay>.from(vm.textOverlays)) {
        vm.removeTextOverlay(t.id);
      }
      final text = TextOverlay(
        id: 'test_txt',
        text: 'Title',
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
      );
      vm.addTextOverlay(text);

      expect(vm.textOverlays.first.isLocked, isFalse);
      vm.toggleTextLock('test_txt');
      expect(vm.textOverlays.first.isLocked, isTrue);
      vm.toggleTextLock('test_txt');
      expect(vm.textOverlays.first.isLocked, isFalse);
      vm.dispose();
    });

    test('Toggle lock on Audio Track', () {
      final vm = EditorViewModel();
      final audio = AudioTrack(
        id: 'test_aud',
        assetId: 'aud_asset',
        name: 'Track 1',
        duration: const Duration(seconds: 5),
      );
      vm.addAudioTrack(audio);

      expect(vm.audioTracks.first.isLocked, isFalse);
      vm.toggleAudioTrackLock('test_aud');
      expect(vm.audioTracks.first.isLocked, isTrue);
      vm.toggleAudioTrackLock('test_aud');
      expect(vm.audioTracks.first.isLocked, isFalse);
      vm.dispose();
    });

    test('Toggle visibility on Video, Overlay, Text, and Audio', () {
      final vm = EditorViewModel();
      final clipId = vm.videoClips.first.id;

      // Video visibility
      expect(vm.videoClips.first.isVisible, isTrue);
      vm.toggleClipVisibility(clipId);
      expect(vm.videoClips.first.isVisible, isFalse);
      vm.toggleClipVisibility(clipId);
      expect(vm.videoClips.first.isVisible, isTrue);

      // Overlay visibility
      vm.addOverlayClip(OverlayClip(
        id: 'ov_vis',
        title: 'Vis PIP',
        startTime: Duration.zero,
        duration: const Duration(seconds: 2),
      ));
      expect(vm.overlayClips.first.isVisible, isTrue);
      vm.toggleOverlayVisibility('ov_vis');
      expect(vm.overlayClips.first.isVisible, isFalse);

      // Text visibility
      for (final t in List<TextOverlay>.from(vm.textOverlays)) {
        vm.removeTextOverlay(t.id);
      }
      vm.addTextOverlay(TextOverlay(
        id: 'txt_vis',
        text: 'Hello',
        startTime: Duration.zero,
        duration: const Duration(seconds: 2),
      ));
      expect(vm.textOverlays.first.isVisible, isTrue);
      vm.toggleTextVisibility('txt_vis');
      expect(vm.textOverlays.first.isVisible, isFalse);

      // Audio visibility
      vm.addAudioTrack(AudioTrack(
        id: 'aud_vis',
        assetId: 'song_asset',
        name: 'Song',
        duration: const Duration(seconds: 5),
      ));
      expect(vm.audioTracks.first.isVisible, isTrue);
      vm.toggleAudioTrackVisibility('aud_vis');
      expect(vm.audioTracks.first.isVisible, isFalse);

      vm.dispose();
    });
  });

  group('4. EditorViewModel Layer Reordering Tests', () {
    test('Overlay layer reordering: up, down, front, back', () {
      final vm = EditorViewModel();
      vm.addOverlayClip(OverlayClip(id: 'ov_A', title: 'A', startTime: Duration.zero, duration: const Duration(seconds: 3)));
      vm.addOverlayClip(OverlayClip(id: 'ov_B', title: 'B', startTime: Duration.zero, duration: const Duration(seconds: 3)));
      vm.addOverlayClip(OverlayClip(id: 'ov_C', title: 'C', startTime: Duration.zero, duration: const Duration(seconds: 3)));

      expect(vm.overlayClips.map((o) => o.id).toList(), ['ov_A', 'ov_B', 'ov_C']);

      // Move A up (towards front, index increases)
      vm.moveOverlayUp('ov_A');
      expect(vm.overlayClips.map((o) => o.id).toList(), ['ov_B', 'ov_A', 'ov_C']);

      // Send C to back (index 0)
      vm.sendOverlayToBack('ov_C');
      expect(vm.overlayClips.map((o) => o.id).toList(), ['ov_C', 'ov_B', 'ov_A']);

      // Bring C to front (last index)
      vm.bringOverlayToFront('ov_C');
      expect(vm.overlayClips.map((o) => o.id).toList(), ['ov_B', 'ov_A', 'ov_C']);

      // Move C down
      vm.moveOverlayDown('ov_C');
      expect(vm.overlayClips.map((o) => o.id).toList(), ['ov_B', 'ov_C', 'ov_A']);

      vm.dispose();
    });

    test('Text layer reordering: up, down, front, back', () {
      final vm = EditorViewModel();
      for (final t in List<TextOverlay>.from(vm.textOverlays)) {
        vm.removeTextOverlay(t.id);
      }
      vm.addTextOverlay(TextOverlay(id: 'txt_A', text: 'A', startTime: Duration.zero, duration: const Duration(seconds: 3)));
      vm.addTextOverlay(TextOverlay(id: 'txt_B', text: 'B', startTime: Duration.zero, duration: const Duration(seconds: 3)));
      vm.addTextOverlay(TextOverlay(id: 'txt_C', text: 'C', startTime: Duration.zero, duration: const Duration(seconds: 3)));

      expect(vm.textOverlays.map((t) => t.id).toList(), ['txt_A', 'txt_B', 'txt_C']);

      // Bring A to front
      vm.bringTextToFront('txt_A');
      expect(vm.textOverlays.map((t) => t.id).toList(), ['txt_B', 'txt_C', 'txt_A']);

      // Send A to back
      vm.sendTextToBack('txt_A');
      expect(vm.textOverlays.map((t) => t.id).toList(), ['txt_A', 'txt_B', 'txt_C']);

      // Move B up
      vm.moveTextUp('txt_B');
      expect(vm.textOverlays.map((t) => t.id).toList(), ['txt_A', 'txt_C', 'txt_B']);

      // Move B down
      vm.moveTextDown('txt_B');
      expect(vm.textOverlays.map((t) => t.id).toList(), ['txt_A', 'txt_B', 'txt_C']);

      vm.dispose();
    });
  });

  group('5. Multi-Layer Split at Playhead Tests', () {
    test('Split Overlay at Playhead divides clip into two sequential parts', () {
      final vm = EditorViewModel();
      vm.addOverlayClip(OverlayClip(
        id: 'ov_split',
        title: 'Split PIP',
        startTime: Duration.zero,
        duration: const Duration(seconds: 6),
      ));

      // Move playhead to 2 seconds
      vm.seekTo(2.0);
      final didSplit = vm.splitOverlayAtPlayhead('ov_split');
      expect(didSplit, isTrue);

      expect(vm.overlayClips.length, 2);
      final first = vm.overlayClips[0];
      final second = vm.overlayClips[1];

      expect(first.startTime, Duration.zero);
      expect(first.duration, const Duration(seconds: 2));

      expect(second.startTime, const Duration(seconds: 2));
      expect(second.duration, const Duration(seconds: 4));

      vm.dispose();
    });

    test('Split Text at Playhead divides text into two sequential parts', () {
      final vm = EditorViewModel();
      for (final t in List<TextOverlay>.from(vm.textOverlays)) {
        vm.removeTextOverlay(t.id);
      }
      vm.addTextOverlay(TextOverlay(
        id: 'txt_split',
        text: 'Long Subtitle',
        startTime: const Duration(seconds: 1),
        duration: const Duration(seconds: 5),
      ));

      // Move playhead to 3 seconds (2 seconds into text)
      vm.seekTo(3.0);
      final didSplit = vm.splitTextAtPlayhead('txt_split');
      expect(didSplit, isTrue);

      expect(vm.textOverlays.length, 2);
      final first = vm.textOverlays[0];
      final second = vm.textOverlays[1];

      expect(first.startTime, const Duration(seconds: 1));
      expect(first.duration, const Duration(seconds: 2));

      expect(second.startTime, const Duration(seconds: 3));
      expect(second.duration, const Duration(seconds: 3));

      vm.dispose();
    });

    test('Split Audio at Playhead divides audio track into two sequential parts', () {
      final vm = EditorViewModel();
      vm.addAudioTrack(AudioTrack(
        id: 'aud_split',
        assetId: 'split_asset',
        name: 'Voice',
        startTime: Duration.zero,
        duration: const Duration(seconds: 8),
      ));

      // Move playhead to 4 seconds
      vm.seekTo(4.0);
      final didSplit = vm.splitAudioTrackAtPlayhead('aud_split');
      expect(didSplit, isTrue);

      expect(vm.audioTracks.length, 2);
      final first = vm.audioTracks[0];
      final second = vm.audioTracks[1];

      expect(first.startTime, Duration.zero);
      expect(first.trimEnd, const Duration(seconds: 4));

      expect(second.startTime, const Duration(seconds: 4));
      expect(second.trimStart, const Duration(seconds: 4));

      vm.dispose();
    });
  });

  group('6. Snapping, Ripple Editing & Zoom Tests', () {
    test('Toggle ripple editing and snapping', () {
      final vm = EditorViewModel();
      expect(vm.isRippleEditingEnabled, isFalse);
      vm.toggleRippleEditing();
      expect(vm.isRippleEditingEnabled, isTrue);

      expect(vm.isSnapToClipsEnabled, isTrue);
      vm.toggleSnapToClips();
      expect(vm.isSnapToClipsEnabled, isFalse);
      vm.dispose();
    });

    test('Snap boundaries include clips, overlays, texts, and audios', () {
      final vm = EditorViewModel();
      vm.addOverlayClip(OverlayClip(
        id: 'ov_snap',
        title: 'Snap OV',
        startTime: const Duration(seconds: 2),
        duration: const Duration(seconds: 3), // ends at 5s
      ));
      vm.addTextOverlay(TextOverlay(
        id: 'txt_snap',
        text: 'Snap Text',
        startTime: const Duration(seconds: 7),
        duration: const Duration(seconds: 2), // ends at 9s
      ));

      final bounds = vm.snapBoundaries;
      expect(bounds.contains(0.0), isTrue);
      expect(bounds.contains(2.0), isTrue);
      expect(bounds.contains(5.0), isTrue);
      expect(bounds.contains(7.0), isTrue);
      expect(bounds.contains(9.0), isTrue);

      // Snapping position: near 2.05s -> snaps to 2.0s
      final snapped = vm.snapTimelinePosition(2.05);
      expect(snapped, 2.0);

      vm.dispose();
    });

    test('Zoom In, Zoom Out, Reset Zoom operate on pixelsPerSecond', () {
      final vm = EditorViewModel();
      final defaultPps = AppDimensions.defaultPixelsPerSecond;
      expect(vm.pixelsPerSecond, defaultPps);

      vm.zoomIn(1.25);
      expect(vm.pixelsPerSecond, defaultPps * 1.25);

      vm.zoomOut(0.8);
      expect((vm.pixelsPerSecond - defaultPps).abs() < 0.01, isTrue);

      vm.setZoomScale(100.0);
      expect(vm.pixelsPerSecond, 100.0);

      vm.resetZoom();
      expect(vm.pixelsPerSecond, defaultPps);

      vm.dispose();
    });
  });

  group('7. Unified Duplicate Dispatcher Tests', () {
    test('duplicateSelectedItem duplicates video clip when video is selected', () {
      final vm = EditorViewModel();
      final initialCount = vm.videoClips.length;
      expect(initialCount > 0, isTrue);

      // Select first video clip
      vm.selectClip(0);
      final didDuplicate = vm.duplicateSelectedItem();
      expect(didDuplicate, isTrue);
      expect(vm.videoClips.length, initialCount + 1);

      vm.dispose();
    });

    test('duplicateSelectedItem duplicates overlay clip when overlay is selected', () {
      final vm = EditorViewModel();
      final overlay = OverlayClip(
        id: 'dup_ov',
        title: 'Original PIP',
        startTime: Duration.zero,
        duration: const Duration(seconds: 3),
      );
      vm.addOverlayClip(overlay);
      vm.selectOverlay(0);

      final didDuplicate = vm.duplicateSelectedItem();
      expect(didDuplicate, isTrue);
      expect(vm.overlayClips.length, 2);

      vm.dispose();
    });

    test('duplicateSelectedItem duplicates text when text overlay is selected', () {
      final vm = EditorViewModel();
      for (final t in List<TextOverlay>.from(vm.textOverlays)) {
        vm.removeTextOverlay(t.id);
      }
      final text = TextOverlay(
        id: 'dup_txt',
        text: 'Duplicate Me',
        startTime: Duration.zero,
        duration: const Duration(seconds: 2),
      );
      vm.addTextOverlay(text);
      vm.selectText('dup_txt');

      final didDuplicate = vm.duplicateSelectedItem();
      expect(didDuplicate, isTrue);
      expect(vm.textOverlays.length, 2);

      vm.dispose();
    });

    test('duplicateSelectedItem duplicates audio when audio track is selected', () {
      final vm = EditorViewModel();
      final audio = AudioTrack(
        id: 'dup_aud',
        assetId: 'dup_aud_asset',
        name: 'Track',
        duration: const Duration(seconds: 4),
      );
      vm.addAudioTrack(audio);
      vm.selectAudioTrack('dup_aud');

      final didDuplicate = vm.duplicateSelectedItem();
      expect(didDuplicate, isTrue);
      expect(vm.audioTracks.length, 2);

      vm.dispose();
    });
  });

  group('8. TimelineSection Pinned Headers & Interactive Canvas Tests', () {
    testWidgets('TimelineSection renders Pinned Track Headers and zoom controls without overflows', (tester) async {
      final vm = EditorViewModel();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 800,
              child: TimelineSection(viewModel: vm),
            ),
          ),
        ),
      );
      await tester.pump();

      // Check header tracks
      expect(find.text('VIDEO'), findsWidgets);
      expect(find.byIcon(Icons.videocam_rounded), findsWidgets);

      // Check timecode and frame pills
      expect(find.byType(TimelineSection), findsOneWidget);

      // Check zoom buttons
      expect(find.byIcon(Icons.add_circle_outline), findsWidgets);
      expect(find.byIcon(Icons.remove_circle_outline), findsWidgets);
      expect(find.text('100%'), findsWidgets);

      // Tap zoom in
      final zoomInBtn = find.byIcon(Icons.add_circle_outline).first;
      await tester.tap(zoomInBtn);
      await tester.pump();

      // Tap zoom out
      final zoomOutBtn = find.byIcon(Icons.remove_circle_outline).first;
      await tester.tap(zoomOutBtn);
      await tester.pump();

      // Tap reset zoom
      final resetBtn = find.text('100%').first;
      await tester.tap(resetBtn);
      await tester.pump();

      expect(tester.takeException(), isNull);
      vm.dispose();
    });
  });
}

