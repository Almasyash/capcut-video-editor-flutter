import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Export Lifecycle & Cancellation Safety Tests', () {
    test('Calling cancelExport clears isExporting, resets progress, and does not invoke success callback', () async {
      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'asset_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
        gradient: [Colors.blue, Colors.purple],
      );

      bool callbackSuccess = false;

      // Start export
      final exportFuture = viewModel.exportVideoToGallery(
        onFinished: (success, outputPath) {
          callbackSuccess = success;
        },
      );

      expect(viewModel.isExporting, isTrue);

      // Cancel immediately
      viewModel.cancelExport();

      expect(viewModel.isExporting, isFalse);
      expect(viewModel.exportProgress, equals(0.0));

      final result = await exportFuture;
      expect(result, isFalse);
      expect(callbackSuccess, isFalse);
    });

    test('Disposing EditorViewModel while exporting cancels safely and suppresses post-disposal exceptions', () async {
      final viewModel = EditorViewModel(enableMockFallback: false);
      viewModel.addNewClipFromMedia(
        assetId: 'asset_1',
        title: 'Clip 1',
        duration: const Duration(seconds: 5),
        gradient: [Colors.blue, Colors.purple],
      );

      viewModel.exportVideoToGallery(
        onFinished: (success, path) {},
      );

      expect(viewModel.isExporting, isTrue);

      // Dispose while export is running
      expect(() => viewModel.dispose(), returnsNormally);

      // Calling notifyListeners after dispose should be safely ignored and not throw
      expect(() => viewModel.notifyListeners(), returnsNormally);
    });
  });
}
