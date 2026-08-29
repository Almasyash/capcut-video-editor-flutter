import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class MediaPickerSheet extends StatefulWidget {
  final EditorViewModel viewModel;
  final bool isReplacing;

  const MediaPickerSheet({
    super.key,
    required this.viewModel,
    this.isReplacing = false,
  });

  @override
  State<MediaPickerSheet> createState() => _MediaPickerSheetState();
}

class _MediaPickerSheetState extends State<MediaPickerSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedId = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleImport() {
    if (_selectedId == null) return;

    final importedAsset = widget.viewModel.getAssetById(_selectedId!);
    if (importedAsset != null) {
      if (widget.isReplacing) {
        widget.viewModel.replaceSelectedClip(
          assetId: importedAsset.id,
          title: importedAsset.name,
          duration: importedAsset.duration ?? const Duration(seconds: 5),
          gradient: const [Color(0xFF00C9FF), Color(0xFF92FE9D)],
          icon: importedAsset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
        );
      } else {
        widget.viewModel.addNewClipFromMedia(
          assetId: importedAsset.id,
          title: importedAsset.name,
          duration: importedAsset.duration ?? const Duration(seconds: 5),
          gradient: const [Color(0xFF00C9FF), Color(0xFF92FE9D)],
          icon: importedAsset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
        );
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDeviceUpload() async {
    final isPhotoTab = _tabController.index == 1;
    final bool success;
    if (isPhotoTab) {
      success = await widget.viewModel.importPhotoAsset();
    } else {
      success = await widget.viewModel.importVideoAsset();
    }

    if (success && mounted) {
      final lastAdded = widget.viewModel.mediaLibrary.isNotEmpty ? widget.viewModel.mediaLibrary.last : null;
      if (lastAdded != null) {
        setState(() {
          _selectedId = lastAdded.id;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imported file into Media Library! Select it below to add to timeline.'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final importedVideos = widget.viewModel.mediaLibrary.where((a) => a.isVideo).toList();
        final importedPhotos = widget.viewModel.mediaLibrary.where((a) => a.isPhoto).toList();

        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.isReplacing ? 'Replace Media Clip' : 'Select Media to Add',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Device Upload Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
                child: InkWell(
                  onTap: _handleDeviceUpload,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 1.2),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_rounded, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Upload File from Device Storage',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Tabs (Videos / Photos)
              Container(
                height: 38,
                margin: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  ),
                  labelColor: Colors.black,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: const [
                    Tab(text: 'Videos'),
                    Tab(text: 'Photos'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Tab views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAssetGrid(
                      assets: importedVideos,
                      isVideo: true,
                      onImport: () => widget.viewModel.importVideoAsset(),
                    ),
                    _buildAssetGrid(
                      assets: importedPhotos,
                      isVideo: false,
                      onImport: () => widget.viewModel.importPhotoAsset(),
                    ),
                  ],
                ),
              ),

              // Bottom Action Bar (Add to Timeline)
              Container(
                padding: const EdgeInsets.all(AppDimensions.md),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _selectedId != null ? _handleImport : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedId != null ? AppColors.primary : AppColors.surfaceLight,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                        elevation: _selectedId != null ? 3 : 0,
                      ),
                      child: Text(
                        widget.isReplacing ? 'Replace Selected Clip' : 'Add to Timeline',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _selectedId != null ? Colors.black : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAssetGrid({
    required List<MediaAsset> assets,
    required bool isVideo,
    required VoidCallback onImport,
  }) {
    if (assets.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: AppDimensions.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVideo ? Icons.video_library_outlined : Icons.photo_library_outlined,
                size: 44,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                isVideo ? 'No imported videos yet' : 'No imported photos yet',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                isVideo
                    ? 'Import video from your device storage to add to your project.'
                    : 'Import photos from your device storage to add to your project.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(isVideo ? 'Import Video' : 'Import Photo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemCount: assets.length,
      itemBuilder: (context, index) {
        final asset = assets[index];
        final isSelected = _selectedId == asset.id;
        final hasLocalFile = asset.localPath != null && !kIsWeb && File(asset.localPath!).existsSync();

        return InkWell(
          onTap: () {
            setState(() {
              _selectedId = isSelected ? null : asset.id;
            });
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.4),
                width: isSelected ? 2.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                if (hasLocalFile && (asset.isPhoto || asset.thumbnailPath != null))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    child: Image.file(
                      File(asset.thumbnailPath ?? asset.localPath!),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (ctx, err, stack) => Center(
                        child: Icon(
                          asset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
                          size: 36,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  )
                else
                  Center(
                    child: Icon(
                      asset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
                      size: 36,
                      color: AppColors.primary.withValues(alpha: 0.8),
                    ),
                  ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      asset.isPhoto ? 'PHOTO' : 'VIDEO',
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            asset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        if (asset.duration != null)
                          Text(
                            TimeFormatter.formatSeconds(asset.duration!.inSeconds.toDouble()),
                            style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 12, color: Colors.black),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
