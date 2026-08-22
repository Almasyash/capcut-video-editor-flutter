import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/time_formatter.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class MediaPickerItem {
  final String title;
  final Duration duration;
  final List<Color> gradient;
  final IconData icon;
  final String category; // 'Video', 'Photo', 'Canvas'

  const MediaPickerItem({
    required this.title,
    required this.duration,
    required this.gradient,
    this.icon = Icons.movie_creation_rounded,
    required this.category,
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
      title: 'Mountain Landscape',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
      icon: Icons.landscape_rounded,
      category: 'Photo',
    ),
    MediaPickerItem(
      title: 'Studio Lighting Setup',
      duration: Duration(seconds: 4),
      gradient: [Color(0xFFFF8008), Color(0xFFFFC837)],
      icon: Icons.photo_camera_rounded,
      category: 'Photo',
    ),
  ];

  static const List<MediaPickerItem> _mockCanvases = [
    MediaPickerItem(
      title: 'Pure Black Screen',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF141414), Color(0xFF0A0A0A)],
      icon: Icons.crop_square_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Cyan Glow Gradient',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF00E5FF), Color(0xFF0052D4)],
      icon: Icons.gradient_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Neon Pink Backdrop',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFFFF007F), Color(0xFF7928CA)],
      icon: Icons.brush_rounded,
      category: 'Canvas',
    ),
    MediaPickerItem(
      title: 'Emerald Green Screen',
      duration: Duration(seconds: 5),
      gradient: [Color(0xFF00B09B), Color(0xFF96C93D)],
      icon: Icons.shield_rounded,
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
        );
      } else {
        widget.viewModel.addNewClipFromMedia(
          title: selected.title,
          duration: selected.duration,
          gradient: selected.gradient,
          icon: selected.icon,
        );
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
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
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
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

          // Tabs (Videos / Photos / Canvases)
          Container(
            height: 40,
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
              onTap: (_) => setState(() => _selectedIndex = null),
            ),
          ),

          const SizedBox(height: 12),

          // Media Grid
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

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(AppDimensions.md),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: Text(
                      _selectedIndex != null
                          ? (widget.isReplacing ? 'Replace Clip' : 'Add to Timeline (1)')
                          : 'Select a clip above',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedIndex != null ? AppColors.primary : AppColors.surfaceLight,
                      foregroundColor: _selectedIndex != null ? Colors.black : AppColors.textMuted,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
                    ),
                    onPressed: _selectedIndex != null ? _handleImport : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaPickerItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
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

        return GestureDetector(
          onTap: () => setState(() => _selectedIndex = index),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              gradient: LinearGradient(
                colors: item.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: isSelected ? 3.0 : 1.0,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(item.icon, size: 36, color: Colors.white38),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              TimeFormatter.formatSeconds(item.duration.inMilliseconds / 1000.0, showMilliseconds: false),
                              style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded, size: 14, color: Colors.black),
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
