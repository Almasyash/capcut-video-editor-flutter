import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/core/utils/chroma_key_helper.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  group('OverlayClip Domain Model & Serialization Tests', () {
    test('Default OverlayClip initializes with Chroma Key disabled and standard blend mode', () {
      const overlay = OverlayClip(
        id: 'ov_test_1',
        title: 'Test Overlay',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 4),
      );

      expect(overlay.enableChromaKey, isFalse);
      expect(overlay.chromaKeyColor.value, equals(const Color(0xFF00FF00).value));
      expect(overlay.chromaSimilarity, closeTo(0.40, 1e-4));
      expect(overlay.chromaSmoothness, closeTo(0.10, 1e-4));
      expect(overlay.chromaSpill, closeTo(0.15, 1e-4));
      expect(overlay.blendMode, equals(BlendMode.srcOver));
      expect(overlay.opacity, equals(1.0));
      expect(overlay.scale, equals(0.45));
      expect(overlay.isPhoto, isFalse);
      expect(overlay.assetId, isNull);
      expect(overlay.localPath, isNull);
    });

    test('OverlayClip JSON serialization and deserialization preserves all Chroma Key and PIP properties', () {
      const original = OverlayClip(
        id: 'ov_chroma_1',
        title: 'Green Screen Actor',
        startTime: Duration(milliseconds: 1500),
        duration: Duration(milliseconds: 5000),
        position: Offset(0.5, 0.5),
        scale: 0.85,
        opacity: 0.95,
        rotation: 0.25,
        blendMode: BlendMode.screen,
        assetId: 'asset_gs_42',
        localPath: '/data/user/0/cache/actor_greenscreen.mp4',
        isPhoto: false,
        enableChromaKey: true,
        chromaKeyColor: Color(0xFF00FF00),
        chromaSimilarity: 0.55,
        chromaSmoothness: 0.20,
        chromaSpill: 0.30,
      );

      final json = original.toJson();
      final revived = OverlayClip.fromJson(json);

      expect(revived.id, equals('ov_chroma_1'));
      expect(revived.title, equals('Green Screen Actor'));
      expect(revived.startTimeMs, equals(1500));
      expect(revived.durationMs, equals(5000));
      expect(revived.position.dx, closeTo(0.5, 1e-4));
      expect(revived.position.dy, closeTo(0.5, 1e-4));
      expect(revived.scale, closeTo(0.85, 1e-4));
      expect(revived.opacity, closeTo(0.95, 1e-4));
      expect(revived.blendMode, equals(BlendMode.screen));
      expect(revived.assetId, equals('asset_gs_42'));
      expect(revived.localPath, equals('/data/user/0/cache/actor_greenscreen.mp4'));
      expect(revived.isPhoto, isFalse);
      expect(revived.enableChromaKey, isTrue);
      expect(revived.chromaKeyColor.value, equals(const Color(0xFF00FF00).value));
      expect(revived.chromaSimilarity, closeTo(0.55, 1e-4));
      expect(revived.chromaSmoothness, closeTo(0.20, 1e-4));
      expect(revived.chromaSpill, closeTo(0.30, 1e-4));
    });

    test('OverlayClip copyWith updates Chroma Key and BlendMode cleanly', () {
      const base = OverlayClip(
        id: 'ov_base',
        title: 'Base Layer',
        startTime: Duration.zero,
        duration: Duration(seconds: 3),
      );

      final updated = base.copyWith(
        blendMode: BlendMode.multiply,
        enableChromaKey: true,
        chromaKeyColor: const Color(0xFF0000FF), // Blue screen
        chromaSimilarity: 0.48,
        chromaSpill: 0.22,
        opacity: 0.8,
      );

      expect(updated.id, equals('ov_base'));
      expect(updated.blendMode, equals(BlendMode.multiply));
      expect(updated.enableChromaKey, isTrue);
      expect(updated.chromaKeyColor.value, equals(const Color(0xFF0000FF).value));
      expect(updated.chromaSimilarity, closeTo(0.48, 1e-4));
      expect(updated.chromaSpill, closeTo(0.22, 1e-4));
      expect(updated.opacity, closeTo(0.8, 1e-4));
    });
  });

  group('ChromaKeyHelper GPU Matrix Tests', () {
    test('ChromaKeyHelper presets list contains required video production colors', () {
      expect(ChromaKeyHelper.presets, isNotEmpty);
      final names = ChromaKeyHelper.presets.map((p) => p.name).toList();
      expect(names, contains('Neon Green'));
      expect(names, contains('Studio Green'));
      expect(names, contains('Chroma Blue'));
      expect(names, contains('Classic Blue'));
    });

    test('Green Screen matrix suppresses green alpha while preserving non-green pixels', () {
      final matrix = ChromaKeyHelper.buildMatrix(
        keyColor: const Color(0xFF00FF00),
        similarity: 0.40,
        smoothness: 0.10,
        spill: 0.15,
      );

      expect(matrix.length, equals(20));

      // Row 3 is Alpha: A' = m30*R + m31*G + m32*B + m33*A + m34
      final m30 = matrix[15]; // Red coeff
      final m31 = matrix[16]; // Green coeff
      final m32 = matrix[17]; // Blue coeff
      final m33 = matrix[18]; // Alpha coeff

      expect(m31, lessThan(0.0)); // Green must have negative contribution
      expect(m30, greaterThan(0.0)); // Red has positive contribution
      expect(m32, greaterThan(0.0)); // Blue has positive contribution
      expect(m33, equals(1.0));

      // Test pure green pixel: (R=0, G=1, B=0, A=1)
      final greenAlpha = m30 * 0.0 + m31 * 1.0 + m32 * 0.0 + m33 * 1.0;
      expect(greenAlpha, lessThan(0.0)); // Transparent on GPU clamp

      // Test white pixel: (R=1, G=1, B=1, A=1)
      final whiteAlpha = m30 * 1.0 + m31 * 1.0 + m32 * 1.0 + m33 * 1.0;
      expect(whiteAlpha, greaterThanOrEqualTo(1.0)); // Opaque

      // Test skin tone pixel: (R=0.9, G=0.7, B=0.6, A=1)
      final skinAlpha = m30 * 0.9 + m31 * 0.7 + m32 * 0.6 + m33 * 1.0;
      expect(skinAlpha, greaterThanOrEqualTo(1.0)); // Opaque skin tone
    });

    test('Blue Screen matrix suppresses blue alpha while preserving red and green', () {
      final matrix = ChromaKeyHelper.buildMatrix(
        keyColor: const Color(0xFF0000FF),
        similarity: 0.40,
        smoothness: 0.10,
        spill: 0.15,
      );

      expect(matrix.length, equals(20));

      final m30 = matrix[15]; // Red coeff
      final m31 = matrix[16]; // Green coeff
      final m32 = matrix[17]; // Blue coeff
      final m33 = matrix[18]; // Alpha coeff

      expect(m32, lessThan(0.0)); // Blue must have negative contribution
      expect(m30, greaterThan(0.0)); // Red has positive contribution
      expect(m31, greaterThan(0.0)); // Green has positive contribution
      expect(m33, equals(1.0));

      // Test pure blue pixel: (R=0, G=0, B=1, A=1)
      final blueAlpha = m30 * 0.0 + m31 * 0.0 + m32 * 1.0 + m33 * 1.0;
      expect(blueAlpha, lessThan(0.0)); // Transparent on GPU clamp
    });
  });

  group('EditorViewModel PIP Overlay Operations Tests', () {
    test('Adding and selecting overlay clip with blendMode and chromaKey', () {
      final viewModel = EditorViewModel();

      const overlay = OverlayClip(
        id: 'ov_vm_1',
        title: 'Logo Overlay',
        startTime: Duration(seconds: 1),
        duration: Duration(seconds: 3),
        blendMode: BlendMode.screen,
      );

      viewModel.addOverlayClip(overlay);

      expect(viewModel.overlayClips.length, equals(1));
      expect(viewModel.selectedOverlay, isNotNull);
      expect(viewModel.selectedOverlay?.id, equals('ov_vm_1'));
      expect(viewModel.selectedOverlay?.blendMode, equals(BlendMode.screen));

      // Update Blend Mode
      viewModel.updateSelectedOverlayBlendMode(BlendMode.overlay);
      expect(viewModel.selectedOverlay?.blendMode, equals(BlendMode.overlay));

      // Update Opacity
      viewModel.updateSelectedOverlayOpacity(0.75);
      expect(viewModel.selectedOverlay?.opacity, closeTo(0.75, 1e-4));

      // Update Chroma Key
      viewModel.updateSelectedOverlayChromaKey(
        enable: true,
        color: const Color(0xFF00FF00),
        similarity: 0.60,
        smoothness: 0.15,
        spill: 0.25,
      );

      expect(viewModel.selectedOverlay?.enableChromaKey, isTrue);
      expect(viewModel.selectedOverlay?.chromaKeyColor.value, equals(const Color(0xFF00FF00).value));
      expect(viewModel.selectedOverlay?.chromaSimilarity, closeTo(0.60, 1e-4));
      expect(viewModel.selectedOverlay?.chromaSmoothness, closeTo(0.15, 1e-4));
      expect(viewModel.selectedOverlay?.chromaSpill, closeTo(0.25, 1e-4));

      viewModel.dispose();
    });

    test('addOverlayFromMediaAsset creates an overlay with asset linkage at playhead', () {
      final viewModel = EditorViewModel();
      viewModel.seekTo(2.5); // 2.5 seconds playhead

      final asset = MediaAsset(
        id: 'asset_pip_1',
        type: MediaAssetType.video,
        name: 'reaction_cam.mp4',
        localPath: '/storage/reaction_cam.mp4',
        duration: const Duration(seconds: 6),
        createdAt: DateTime.now(),
      );

      viewModel.addOverlayFromMediaAsset(asset);

      expect(viewModel.overlayClips.length, equals(1));
      final added = viewModel.overlayClips.first;
      expect(added.title, equals('reaction_cam.mp4'));
      expect(added.assetId, equals('asset_pip_1'));
      expect(added.localPath, equals('/storage/reaction_cam.mp4'));
      expect(added.startTimeInSeconds, closeTo(2.5, 1e-2));
      expect(added.durationInSeconds, closeTo(6.0, 1e-2));
      expect(viewModel.selectedOverlay?.id, equals(added.id));

      viewModel.dispose();
    });
  });
}
