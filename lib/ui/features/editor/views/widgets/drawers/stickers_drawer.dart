import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class StickersDrawer extends StatefulWidget {
  final EditorViewModel viewModel;

  const StickersDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  State<StickersDrawer> createState() => _StickersDrawerState();
}

class _StickersDrawerState extends State<StickersDrawer> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<StickerPreset> _getStickersForCategory(StickerCategory category) {
    return StickerPreset.catalog.where((s) => s.category == category).toList();
  }

  void _addSticker(StickerPreset preset) {
    widget.viewModel.addSticker(preset);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${preset.label}" sticker overlay!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Stickers & Graphics', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Done',
                  onPressed: widget.viewModel.closeDrawer,
                ),
              ],
            ),
          ),

          // Categories TabBar
          Container(
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              tabs: const [
                Tab(text: 'Emojis'),
                Tab(text: 'Vlog'),
                Tab(text: 'Badges'),
                Tab(text: 'Neon'),
              ],
            ),
          ),

          // Grid Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStickerGrid(_getStickersForCategory(StickerCategory.emojis)),
                _buildStickerGrid(_getStickersForCategory(StickerCategory.vlog)),
                _buildStickerGrid(_getStickersForCategory(StickerCategory.badges)),
                _buildStickerGrid(_getStickersForCategory(StickerCategory.neon)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerGrid(List<StickerPreset> stickers) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: stickers.length,
      itemBuilder: (context, idx) {
        final s = stickers[idx];
        return InkWell(
          onTap: () => _addSticker(s),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: Container(
            width: 76,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (s.isEmoji)
                  Text(s.content, style: const TextStyle(fontSize: 30))
                else
                  Icon(s.icon ?? Icons.star_rounded, color: s.color ?? AppColors.primary, size: 28),
                const SizedBox(height: 4),
                Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
