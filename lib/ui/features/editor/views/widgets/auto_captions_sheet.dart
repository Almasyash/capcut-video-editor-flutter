import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/auto_caption_service.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

/// Modal bottom sheet for configuring viral auto captions, word-by-word karaoke animations,
/// style presets, and batch subtitle styling.
class AutoCaptionsSheet extends StatefulWidget {
  final EditorViewModel viewModel;

  const AutoCaptionsSheet({
    super.key,
    required this.viewModel,
  });

  static Future<void> show(BuildContext context, EditorViewModel viewModel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AutoCaptionsSheet(viewModel: viewModel),
    );
  }

  @override
  State<AutoCaptionsSheet> createState() => _AutoCaptionsSheetState();
}

class _AutoCaptionsSheetState extends State<AutoCaptionsSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  CaptionStylePresetId _selectedPresetId = CaptionStylePresetId.hormozi;
  late TextAnimationType _selectedAnimation;
  String _selectedGenre = 'Motivation';
  final TextEditingController _customScriptController = TextEditingController();
  int _wordsPerChunk = 3;
  bool _alignWithBeats = true;
  bool _clearExisting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _selectedAnimation = CaptionStylePreset.findById(_selectedPresetId).defaultAnimation;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customScriptController.dispose();
    super.dispose();
  }

  void _onPresetSelected(CaptionStylePresetId id) {
    setState(() {
      _selectedPresetId = id;
      _selectedAnimation = CaptionStylePreset.findById(id).defaultAnimation;
    });
  }

  void _generateCaptions({String? customScript}) {
    final preset = CaptionStylePreset.findById(_selectedPresetId);
    final count = widget.viewModel.generateAutoCaptions(
      script: customScript,
      genre: _selectedGenre,
      preset: preset,
      animationType: _selectedAnimation,
      wordsPerChunk: _wordsPerChunk,
      alignWithBeats: _alignWithBeats,
      clearExisting: _clearExisting,
    );

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✨ Generated $count animated captions on timeline!'),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _applyToAllCaptions() {
    final preset = CaptionStylePreset.findById(_selectedPresetId);
    final dummy = TextOverlay(
      id: 'template',
      text: '',
      startTime: Duration.zero,
      duration: const Duration(seconds: 2),
      textColor: preset.textColor,
      highlightColor: preset.highlightColor,
      backgroundColor: preset.backgroundColor,
      strokeWidth: preset.strokeWidth,
      strokeColor: preset.strokeColor,
      fontSize: preset.fontSize,
      isBold: preset.isBold,
      position: preset.defaultPosition,
      animationType: _selectedAnimation,
    );

    widget.viewModel.applyCaptionStyleToAll(dummy);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🎨 Synced style across all subtitles!'),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedPreset = CaptionStylePreset.findById(_selectedPresetId);
    final hasExistingTexts = widget.viewModel.textOverlays.isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.76,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusLg)),
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.8)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.lg, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Auto & Animated Captions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar: Presets, Trending Scripts, Custom
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              labelColor: Colors.black,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(text: 'Style Presets'),
                Tab(text: 'Trending Scripts'),
                Tab(text: 'Custom Text'),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPresetsTab(selectedPreset),
                _buildTrendingScriptsTab(),
                _buildCustomScriptTab(),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(AppDimensions.md),
            decoration: const BoxDecoration(
              color: Color(0xFF131317),
              border: Border(top: BorderSide(color: AppColors.divider, width: 0.6)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Clear existing checkbox
                      Expanded(
                        child: Row(
                          children: [
                            Checkbox(
                              value: _clearExisting,
                              activeColor: AppColors.primary,
                              onChanged: (v) => setState(() => _clearExisting = v ?? false),
                            ),
                            const Text(
                              'Replace existing',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Apply to all button (if captions exist)
                      if (hasExistingTexts)
                        OutlinedButton(
                          onPressed: _applyToAllCaptions,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.secondary, width: 1.0),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Apply Style to All', style: TextStyle(color: AppColors.secondary, fontSize: 11)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text(
                        'Generate Animated Captions',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (_tabController.index == 2) {
                          _generateCaptions(customScript: _customScriptController.text);
                        } else {
                          _generateCaptions();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsTab(CaptionStylePreset selectedPreset) {
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.md),
      children: [
        // Live Preview Box
        _buildLivePreviewCard(selectedPreset),
        const SizedBox(height: 14),

        // Presets Horizontal Carousel
        const Text(
          'SELECT CAPTION STYLE',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 105,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: CaptionStylePreset.presets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final preset = CaptionStylePreset.presets[idx];
              final isSelected = preset.id == _selectedPresetId;
              return GestureDetector(
                onTap: () => _onPresetSelected(preset.id),
                child: Container(
                  width: 130,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.surfaceElevated : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.divider,
                      width: isSelected ? 2.0 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : Colors.white10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          preset.tag,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.black : Colors.white70,
                          ),
                        ),
                      ),
                      Text(
                        preset.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                      ),
                      Text(
                        preset.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // Animation Type Selector Chips
        const Text(
          'ANIMATION EFFECT',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: TextAnimationType.values.map((anim) {
            final isSelected = anim == _selectedAnimation;
            return ChoiceChip(
              avatar: Icon(anim.icon, size: 14, color: isSelected ? Colors.black : Colors.white70),
              label: Text(anim.displayName),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surfaceLight,
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.black : Colors.white70,
              ),
              onSelected: (_) => setState(() => _selectedAnimation = anim),
            );
          }).toList(),
        ),

        const SizedBox(height: 14),

        // Audio Beats Sync Switch
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sync with Audio Beats', style: TextStyle(fontSize: 13, color: Colors.white)),
          subtitle: const Text(
            'Snaps caption start markers to rhythmic drops',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          value: _alignWithBeats,
          activeColor: AppColors.primary,
          onChanged: (val) => setState(() => _alignWithBeats = val),
        ),
      ],
    );
  }

  Widget _buildTrendingScriptsTab() {
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.md),
      children: [
        const Text(
          'SELECT VIRAL TOPIC / SCRIPT',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        ...AutoCaptionService.trendingScripts.entries.map((entry) {
          final isSelected = entry.key == _selectedGenre;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.surfaceElevated : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.divider,
                width: isSelected ? 1.5 : 0.8,
              ),
            ),
            child: ListTile(
              title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(entry.value, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)
                  : const Icon(Icons.circle_outlined, color: Colors.white24, size: 20),
              onTap: () => setState(() => _selectedGenre = entry.key),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCustomScriptTab() {
    return ListView(
      padding: const EdgeInsets.all(AppDimensions.md),
      children: [
        const Text(
          'PASTE YOUR SCRIPT OR TRANSCRIPT',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customScriptController,
          maxLines: 5,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Paste voiceover text here... e.g. "Welcome to my video today we will learn how to edit like a pro..."',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Words Per Caption Block:', style: TextStyle(fontSize: 12, color: Colors.white)),
            DropdownButton<int>(
              value: _wordsPerChunk,
              dropdownColor: AppColors.surfaceElevated,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
              items: [2, 3, 4, 5].map((val) {
                return DropdownMenuItem<int>(
                  value: val,
                  child: Text('$val words'),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _wordsPerChunk = val);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(CaptionStylePreset preset) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF101014),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: Colors.white12, width: 1.0),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('PREVIEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
              Text(_selectedAnimation.displayName, style: const TextStyle(fontSize: 9, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: preset.backgroundColor ?? Colors.black54,
              borderRadius: BorderRadius.circular(6),
              border: preset.strokeWidth > 0 && preset.backgroundColor != null
                  ? Border.all(color: preset.strokeColor, width: 1.0)
                  : null,
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(
                  preset.uppercase ? 'CREATE' : 'Create',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: preset.isBold ? FontWeight.w900 : FontWeight.w600,
                    color: preset.textColor,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _selectedAnimation == TextAnimationType.karaoke ? Colors.black45 : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    preset.uppercase ? 'VIRAL' : 'Viral',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _selectedAnimation == TextAnimationType.karaoke ? preset.highlightColor : preset.textColor,
                      shadows: [
                        if (_selectedAnimation == TextAnimationType.karaoke)
                          Shadow(
                            color: preset.highlightColor.withOpacity(0.8),
                            blurRadius: 8,
                          ),
                      ],
                    ),
                  ),
                ),
                Text(
                  preset.uppercase ? 'CONTENT' : 'Content',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: preset.isBold ? FontWeight.w900 : FontWeight.w600,
                    color: preset.textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
