import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/constants/app_typography.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Modal bottom sheet for configuring export resolution, frame rate, and rendering video
class ExportModalSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const ExportModalSheet({super.key, required this.viewModel});

  @override
  State<ExportModalSheet> createState() => _ExportModalSheetState();
}

class _ExportModalSheetState extends State<ExportModalSheet> {
  late ExportResolution _selectedResolution;
  late ExportFps _selectedFps;

  @override
  void initState() {
    super.initState();
    _selectedResolution = widget.viewModel.exportSettings.resolution;
    _selectedFps = widget.viewModel.exportSettings.fps;
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final estimatedMb = widget.viewModel.exportSettings
        .copyWith(resolution: _selectedResolution, fps: _selectedFps)
        .estimatedSizeMb(viewModel.totalDurationInSeconds);

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        if (viewModel.isExporting) {
          return _buildExportingProgressView(viewModel);
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.lg),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Bar with Drag Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Export Video Settings', style: AppTypography.headerTitle),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.iconDefault),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Resolution Selector
                const Text('Resolution', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: ExportResolution.values.map((res) {
                    final isSel = res == _selectedResolution;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3.0),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedResolution = res);
                            viewModel.updateExportSettings(viewModel.exportSettings.copyWith(resolution: res));
                          },
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              border: Border.all(
                                color: isSel ? AppColors.primary : AppColors.divider,
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  res.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                    color: isSel ? AppColors.primary : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  res.resolutionString.split(' ').first,
                                  style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // Frame Rate (FPS) Selector
                const Text('Frame Rate (FPS)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Row(
                  children: ExportFps.values.map((fps) {
                    final isSel = fps == _selectedFps;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3.0),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedFps = fps);
                            viewModel.updateExportSettings(viewModel.exportSettings.copyWith(fps: fps));
                          },
                          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              border: Border.all(
                                color: isSel ? AppColors.primary : AppColors.divider,
                                width: isSel ? 1.5 : 1.0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                fps.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  color: isSel ? AppColors.primary : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // File Size & Quality Estimation Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Estimated File Size', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text(
                            '~${estimatedMb.toStringAsFixed(1)} MB',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Render Engine', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          SizedBox(height: 2),
                          Text(
                            'Mahmas Studio Engine (H.264)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Primary Export Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      viewModel.startExportSimulation(
                        onComplete: () {
                          if (mounted) {
                            Navigator.of(context).pop();
                            _showSuccessDialog(context);
                          }
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                      ),
                      elevation: 4,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.file_upload_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Export Video', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExportingProgressView(EditorViewModel viewModel) {
    final percent = (viewModel.exportProgress * 100).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.xl, vertical: AppDimensions.xxl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Exporting Video...', style: AppTypography.headerTitle),
            const SizedBox(height: 6),
            const Text('Please do not lock the screen or switch apps', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 24),

            // Circular Progress Indicator with Percent
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: viewModel.exportProgress,
                    strokeWidth: 6,
                    backgroundColor: AppColors.surfaceElevated,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),

            const SizedBox(height: 24),

            TextButton(
              onPressed: viewModel.cancelExport,
              child: const Text('Cancel', style: TextStyle(color: AppColors.secondary)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.accentGreen, size: 28),
            SizedBox(width: 10),
            Text('Export Complete!'),
          ],
        ),
        content: const Text(
          'Your video was rendered and saved to your device album at 1080P 60fps.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Great', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
