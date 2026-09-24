import 'dart:io';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Desktop left-hand Media Library and Assets Inspector panel
class DesktopAssetsPanel extends StatefulWidget {
  final EditorViewModel viewModel;

  const DesktopAssetsPanel({
    super.key,
    required this.viewModel,
  });

  @override
  State<DesktopAssetsPanel> createState() => _DesktopAssetsPanelState();
}

class _DesktopAssetsPanelState extends State<DesktopAssetsPanel> {
  int _selectedFilterIndex = 0; // 0: All, 1: Videos, 2: Photos, 3: Audio

  List<MediaAsset> get _filteredAssets {
    final library = widget.viewModel.mediaLibrary;
    switch (_selectedFilterIndex) {
      case 1:
        return library.where((a) => a.isVideo).toList();
      case 2:
        return library.where((a) => a.isPhoto).toList();
      case 3:
        return library.where((a) => a.isAudio).toList();
      default:
        return library;
    }
  }

  void _importMedia() async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await widget.viewModel.importVideoAsset();
    if (mounted && success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Media imported to project library'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.surfaceElevated,
        ),
      );
    }
  }

  void _importAudio() async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await widget.viewModel.importAudioAsset();
    if (mounted && success) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Audio imported to project library'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.surfaceElevated,
        ),
      );
    }
  }

  void _addToTimeline(MediaAsset asset) {
    if (asset.isAudio) {
      widget.viewModel.addAudioTrackFromAsset(asset);
    } else {
      widget.viewModel.addVideoClipFromAsset(asset);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${asset.displayName}" to timeline'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assets = _filteredAssets;

    return Container(
      width: 380,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Media Library',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                // Import menu
                PopupMenuButton<String>(
                  tooltip: 'Import media (Ctrl+I)',
                  color: AppColors.surfaceElevated,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: (val) {
                    if (val == 'video') _importMedia();
                    if (val == 'audio') _importAudio();
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'video',
                      child: Row(
                        children: [
                          Icon(Icons.video_library_rounded, color: AppColors.primary, size: 18),
                          SizedBox(width: 10),
                          Text('Import Video / Photo', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'audio',
                      child: Row(
                        children: [
                          Icon(Icons.audiotrack_rounded, color: AppColors.accentGreen, size: 18),
                          SizedBox(width: 10),
                          Text('Import Audio', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.black, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Import',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                _buildFilterChip('All', 0),
                const SizedBox(width: 4),
                _buildFilterChip('Videos', 1),
                const SizedBox(width: 4),
                _buildFilterChip('Photos', 2),
                const SizedBox(width: 4),
                _buildFilterChip('Audio', 3),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: AppColors.divider),

          // Content list/grid
          Expanded(
            child: assets.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: assets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      return _buildAssetItem(asset);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilterIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withOpacity(0.18) : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAssetItem(MediaAsset asset) {
    final file = asset.localPath != null ? File(asset.localPath!) : null;
    final fileExists = file != null && file.existsSync();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Row(
        children: [
          // Thumbnail / Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (fileExists && asset.isPhoto)
                    Image.file(file, fit: BoxFit.cover)
                  else if (asset.thumbnailPath != null && File(asset.thumbnailPath!).existsSync())
                    Image.file(File(asset.thumbnailPath!), fit: BoxFit.cover)
                  else
                    Container(
                      color: asset.isAudio
                          ? AppColors.audioTrackBg
                          : AppColors.surfaceHighlight,
                      child: Icon(
                        asset.isAudio
                            ? Icons.audiotrack_rounded
                            : (asset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded),
                        color: asset.isAudio
                            ? AppColors.primary
                            : AppColors.iconDefault,
                        size: 24,
                      ),
                    ),
                  if (asset.duration != null)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          TimeFormatter.formatTimecode(asset.duration!, showMilliseconds: false),
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Title & size info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  asset.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  asset.sizeBytes != null
                      ? '${(asset.sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : (asset.isPhoto ? 'Photo' : (asset.isAudio ? 'Audio' : 'Video')),
                  style: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Add to timeline button
          Tooltip(
            message: 'Add to timeline',
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 22),
              splashRadius: 18,
              onPressed: () => _addToTimeline(asset),
            ),
          ),

          // Delete from library button
          Tooltip(
            message: 'Remove from library',
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 16),
              splashRadius: 16,
              onPressed: () => widget.viewModel.removeMediaAsset(asset.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_collection_outlined,
                color: AppColors.textTertiary,
                size: 32,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Media Assets',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Import videos, photos, or music to start editing your project.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _importMedia,
              icon: const Icon(Icons.file_upload_outlined, size: 16, color: AppColors.primary),
              label: const Text(
                'Import Files (Ctrl+I)',
                style: TextStyle(color: AppColors.primary, fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.primary, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
