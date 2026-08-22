import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class MediaPickerItem {
  final String title;
  final Duration duration;
  final List<Color> gradient;
  final IconData icon;
  final String category; // 'Video', 'Photo', 'Canvas'
  final String? assetPath;

  const MediaPickerItem({
    required this.title,
    required this.duration,
    required this.gradient,
    this.icon = Icons.movie_creation_rounded,
    required this.category,
    this.assetPath,
  });
}

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
  int? _selectedIndex;

  static const List<MediaPickerItem> _mockVideos = [
    MediaPickerItem(
      title: 'Cinematic Drone Shot',
      duration: Duration(seconds: 8),
      gradient: [Color(0xFF00B4DB), Color(0xFF0083B0)],
      icon: Icons.flight_takeoff_rounded,
      category: 'Video',
    ),
    MediaPickerItem(
      title: 'City Timelapse Night',
      duration: Duration(seconds: 12),
      gradient: [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
      icon: Icons.nights_stay_rounded,
      category: 'Video',
    ),
    MediaPickerItem(
      title: 'Slow Motion Water Splash',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF1CB5E0), Color(0xFF000046)],
      icon: Icons.water_drop_rounded,
      category: 'Video',
    ),
    MediaPickerItem(
      title: 'Vlog Studio Talking Head',
      duration: Duration(seconds: 15),
      gradient: [Color(0xFF11998E), Color(0xFF38EF7D)],
      icon: Icons.record_voice_over_rounded,
      category: 'Video',
    ),
    MediaPickerItem(
      title: 'Sunset Horizon Golden',
      duration: Duration(seconds: 6),
      gradient: [Color(0xFFFF512F), Color(0xFFDD2476)],
      icon: Icons.wb_twilight_rounded,
      category: 'Video',
    ),
    MediaPickerItem(
      title: 'Neon Cyberpunk Corridor',
      duration: Duration(seconds: 10),
      gradient: [Color(0xFFFF007F), Color(0xFF00E5FF)],
      icon: Icons.electric_bolt_rounded,
      category: 'Video',
    ),
  ];

  static const List<MediaPickerItem> _mockPhotos = [
    MediaPickerItem(
      title: 'Urban Portrait',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFF4CA1AF), Color(0xFFC4E0E5)],
      icon: Icons.portrait_rounded,
      category: 'Photo',
    ),
    MediaPickerItem(
      title: 'Abstract Geometric Art',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFF654EA3), Color(0xFFEAAFC8)],
      icon: Icons.category_rounded,
      category: 'Photo',
    ),
    MediaPickerItem(
      title: 'Mountain Landscapes',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFF56AB2F), Color(0xFFA8E063)],
      icon: Icons.landscape_rounded,
      category: 'Photo',
    ),
    MediaPickerItem(
      title: 'Studio Lighting Setup',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFF614385), Color(0xFF516395)],
      icon: Icons.camera_rounded,
      category: 'Photo',
    ),
  ];

  static const List<MediaPickerItem> _mockCanvases = [
    MediaPickerItem(
      title: 'Solid Black Background',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF141414), Color(0xFF000000)],
      icon: Icons.check_box_outline_blank_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Cyan Glow Gradient',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF00E5FF), Color(0xFF0077B6)],
      icon: Icons.gradient_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Neon Pink Backdrop',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFFFF007F), Color(0xFF7928CA)],
      icon: Icons.light_mode_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Emerald Green Screen',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF00E676), Color(0xFF00C853)],
      icon: Icons.crop_square_rounded,
      category: 'Canvas',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleImport() {
    if (_selectedIndex == null) return;

    List<MediaPickerItem> items;
    if (_tabController.index == 0) {
      items = _mockVideos;
    } else if (_tabController.index == 1) {
      items = _mockPhotos;
    } else {
      items = _mockCanvases;
    }

    if (_selectedIndex! < items.length) {
      final selected = items[_selectedIndex!];
      if (widget.isReplacing) {
        widget.viewModel.replaceSelectedClip(
          title: selected.title,
          duration: selected.duration,
          gradient: selected.gradient,
          icon: selected.icon,
          assetPath: selected.assetPath,
        );
      } else {
        widget.viewModel.addNewClipFromMedia(
          title: selected.title,
          duration: selected.duration,
          gradient: selected.gradient,
          icon: selected.icon,
          assetPath: selected.assetPath,
        );
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDeviceUpload() async {
    // 1. Try launching native system file picker intent (ACTION_GET_CONTENT)
    final nativeResult = await DeviceMediaService.pickMediaFromNativeStorage(type: 'media');

    if (nativeResult != null && mounted) {
      if (widget.isReplacing) {
        widget.viewModel.replaceSelectedClip(
          title: nativeResult.fileName,
          duration: nativeResult.estimatedDuration,
          gradient: nativeResult.gradient,
          icon: nativeResult.icon,
          assetPath: nativeResult.filePath,
        );
      } else {
        widget.viewModel.addNewClipFromMedia(
          title: nativeResult.fileName,
          duration: nativeResult.estimatedDuration,
          gradient: nativeResult.gradient,
          icon: nativeResult.icon,
          assetPath: nativeResult.filePath,
        );
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported "${nativeResult.fileName}" from device storage!'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2. If native intent dismissed or on non-android platform, open interactive storage browser
    _openDeviceFileBrowserModal();
  }

  void _openDeviceFileBrowserModal() {
    final controller = TextEditingController(text: 'VID_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    int durationSec = 12;
    String selectedFolder = 'Camera (DCIM)';
    bool isVideo = true;

    final folders = DeviceMediaService.getDeviceStorageFolders();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 24),
              SizedBox(width: 8),
              Text('Browse Device Storage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose Folder / Album:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: folders.take(4).map((f) {
                    final isSel = f['name'] == selectedFolder;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedFolder = f['name'] as String),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.primary.withOpacity(0.2) : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSel ? AppColors.primary : AppColors.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(f['icon'] as IconData, size: 12, color: isSel ? AppColors.primary : Colors.white70),
                            const SizedBox(width: 4),
                            Text(
                              f['name'] as String,
                              style: TextStyle(fontSize: 10, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? AppColors.primary : Colors.white),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.videocam_rounded, size: 14), SizedBox(width: 4), Text('Video')]),
                        selected: isVideo,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surfaceLight,
                        labelStyle: TextStyle(color: isVideo ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (val) => setDialogState(() => isVideo = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.photo_rounded, size: 14), SizedBox(width: 4), Text('Photo')]),
                        selected: !isVideo,
                        selectedColor: AppColors.primary,
                        backgroundColor: AppColors.surfaceLight,
                        labelStyle: TextStyle(color: !isVideo ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        onSelected: (val) => setDialogState(() => isVideo = false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'File Name',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: Icon(isVideo ? Icons.video_file_rounded : Icons.image_rounded, color: AppColors.primary, size: 20),
                  ),
                ),
                if (isVideo) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Video Duration:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      Text('${durationSec}s', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    ],
                  ),
                  Slider(
                    value: durationSec.toDouble(),
                    min: 2.0,
                    max: 60.0,
                    divisions: 58,
                    activeColor: AppColors.primary,
                    onChanged: (val) => setDialogState(() => durationSec = val.round()),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final fileName = controller.text.trim().isEmpty ? (isVideo ? 'Device_Video' : 'Device_Photo') : controller.text.trim();
                final result = isVideo
                    ? DeviceMediaService.createCustomVideoResult(name: fileName, duration: Duration(seconds: durationSec))
                    : DeviceMediaService.createCustomPhotoResult(name: fileName, duration: const Duration(seconds: 4));

                if (widget.isReplacing) {
                  widget.viewModel.replaceSelectedClip(
                    title: result.fileName,
                    duration: result.estimatedDuration,
                    gradient: result.gradient,
                    icon: result.icon,
                    assetPath: result.filePath,
                  );
                } else {
                  widget.viewModel.addNewClipFromMedia(
                    title: result.fileName,
                    duration: result.estimatedDuration,
                    gradient: result.gradient,
                    icon: result.icon,
                    assetPath: result.filePath,
                  );
                }
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Import & Insert', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.2),
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

          const SizedBox(height: 4),

          // Tabs (Videos / Photos / Canvases)
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
                Tab(text: 'Canvases'),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMediaGrid(_mockVideos),
                _buildMediaGrid(_mockPhotos),
                _buildMediaGrid(_mockCanvases),
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
                  onPressed: _selectedIndex != null ? _handleImport : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedIndex != null ? AppColors.primary : AppColors.surfaceLight,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
                    elevation: _selectedIndex != null ? 3 : 0,
                  ),
                  child: Text(
                    widget.isReplacing ? 'Replace Selected Clip' : 'Add to Timeline',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _selectedIndex != null ? Colors.black : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaPickerItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedIndex == index;

        return InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = isSelected ? null : index;
            });
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: item.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.white12,
                width: isSelected ? 2.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(item.icon, size: 36, color: Colors.white70),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        Text(
                          TimeFormatter.formatSeconds(item.duration.inSeconds.toDouble()),
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
