import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/text_animation_sheet.dart';

class TextDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const TextDrawer({
    super.key,
    required this.viewModel,
  });

  static const _availableFonts = [
    (label: 'Default', family: null),
    (label: 'Roboto', family: 'Roboto'),
    (label: 'Montserrat', family: 'Montserrat'),
    (label: 'Oswald', family: 'Oswald'),
    (label: 'Bebas Neue', family: 'Bebas Neue'),
    (label: 'Playfair', family: 'Playfair Display'),
    (label: 'Pacifico', family: 'Pacifico'),
    (label: 'Monospace', family: 'monospace'),
    (label: 'Serif', family: 'serif'),
    (label: 'Sans-Serif', family: 'sans-serif'),
  ];

  void _showAddTextModal(BuildContext context, {TextOverlay? existing}) {
    final controller = TextEditingController(text: existing?.text ?? '');
    Color selectedColor = existing?.color ?? Colors.white;
    double fontSize = existing?.fontSize ?? 22.0;
    TextAlign textAlign = existing?.textAlign ?? TextAlign.center;
    bool isBold = existing?.isBold ?? true;
    bool isItalic = existing?.isItalic ?? false;
    bool isUnderline = existing?.isUnderline ?? false;
    Color? backgroundColor = existing?.backgroundColor;
    String? selectedFontFamily = existing?.fontFamily;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colors = [
              Colors.white,
              AppColors.primary,
              AppColors.secondary,
              Colors.amber,
              Colors.limeAccent,
              Colors.deepOrangeAccent,
              Colors.purpleAccent,
              Colors.cyanAccent,
            ];

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                top: 16,
                left: 16,
                right: 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          existing != null ? 'Edit Text Layer' : 'Add Text Layer',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Font Selection Menu right below header
                    Row(
                      children: [
                        const Icon(Icons.font_download_rounded, size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        const Text(
                          'Font Family:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                        ),
                        if (selectedFontFamily != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              selectedFontFamily!,
                              style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _availableFonts.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, fontIdx) {
                          final fontItem = _availableFonts[fontIdx];
                          final isSelected = (fontItem.family == null && selectedFontFamily == null) ||
                              (fontItem.family != null && fontItem.family == selectedFontFamily);
                          return InkWell(
                            onTap: () => setModalState(() => selectedFontFamily = fontItem.family),
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppColors.surfaceLight,
                                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.divider,
                                  width: isSelected ? 1.5 : 0.8,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                fontItem.label,
                                style: TextStyle(
                                  fontFamily: fontItem.family,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  color: isSelected ? Colors.black : Colors.white,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      textAlign: textAlign,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontFamily: selectedFontFamily,
                        color: selectedColor,
                        fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
                        fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                        decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type your title or caption...',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Styling Bar: Bold, Italic, Underline, Alignment
                    Row(
                      children: [
                        IconButton.filledTonal(
                          icon: const Icon(Icons.format_bold_rounded, size: 18),
                          isSelected: isBold,
                          style: IconButton.styleFrom(
                            backgroundColor: isBold ? AppColors.primary : AppColors.surfaceLight,
                            foregroundColor: isBold ? Colors.black : Colors.white,
                          ),
                          onPressed: () => setModalState(() => isBold = !isBold),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.format_italic_rounded, size: 18),
                          isSelected: isItalic,
                          style: IconButton.styleFrom(
                            backgroundColor: isItalic ? AppColors.primary : AppColors.surfaceLight,
                            foregroundColor: isItalic ? Colors.black : Colors.white,
                          ),
                          onPressed: () => setModalState(() => isItalic = !isItalic),
                        ),
                        const SizedBox(width: 6),
                        IconButton.filledTonal(
                          icon: const Icon(Icons.format_underlined_rounded, size: 18),
                          isSelected: isUnderline,
                          style: IconButton.styleFrom(
                            backgroundColor: isUnderline ? AppColors.primary : AppColors.surfaceLight,
                            foregroundColor: isUnderline ? Colors.black : Colors.white,
                          ),
                          onPressed: () => setModalState(() => isUnderline = !isUnderline),
                        ),
                        const Spacer(),
                        SegmentedButton<TextAlign>(
                          segments: const [
                            ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left_rounded, size: 16)),
                            ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center_rounded, size: 16)),
                            ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right_rounded, size: 16)),
                          ],
                          selected: {textAlign},
                          onSelectionChanged: (set) => setModalState(() => textAlign = set.first),
                          style: SegmentedButton.styleFrom(
                            backgroundColor: AppColors.surfaceLight,
                            selectedBackgroundColor: AppColors.primary,
                            selectedForegroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    const Text('Text Color:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Row(
                      children: colors.map((c) {
                        final isSelected = selectedColor == c;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedColor = c),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text('Size (${fontSize.round()}px):', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        Expanded(
                          child: Slider(
                            value: fontSize,
                            min: 12.0,
                            max: 42.0,
                            activeColor: AppColors.primary,
                            onChanged: (val) => setModalState(() => fontSize = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          if (controller.text.trim().isNotEmpty) {
                            if (existing != null) {
                              viewModel.updateTextOverlay(
                                existing.copyWith(
                                  text: controller.text.trim(),
                                  color: selectedColor,
                                  fontSize: fontSize,
                                  textAlign: textAlign,
                                  isBold: isBold,
                                  isItalic: isItalic,
                                  isUnderline: isUnderline,
                                  backgroundColor: backgroundColor,
                                  fontFamily: selectedFontFamily,
                                ),
                              );
                            } else {
                              final playhead = viewModel.playheadPosition;
                              viewModel.addTextOverlay(
                                TextOverlay(
                                  id: 'text_${DateTime.now().millisecondsSinceEpoch}',
                                  text: controller.text.trim(),
                                  startTime: Duration(milliseconds: (playhead * 1000).round()),
                                  duration: const Duration(seconds: 4),
                                  color: selectedColor,
                                  fontSize: fontSize,
                                  textAlign: textAlign,
                                  isBold: isBold,
                                  isItalic: isItalic,
                                  isUnderline: isUnderline,
                                  backgroundColor: backgroundColor,
                                  fontFamily: selectedFontFamily,
                                ),
                              );
                            }
                            Navigator.of(ctx).pop();
                          }
                        },
                        child: Text(
                          existing != null ? 'Save Changes' : 'Add Text to Video',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final texts = viewModel.textOverlays;

    return Container(
      height: 200,
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
                    Icon(Icons.title_rounded, size: 16, color: AppColors.primary),
                    SizedBox(width: 6),
                    Text('Text & Subtitles', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Done',
                  onPressed: viewModel.closeDrawer,
                ),
              ],
            ),
          ),

          // Actions: Add Text & Auto-Captions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Text'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _showAddTextModal(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.animation_rounded, size: 16, color: AppColors.secondary),
                    label: const Text('Text Animation', style: TextStyle(color: AppColors.secondary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.secondary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => TextAnimationSheet.show(context, viewModel),
                  ),
                ),
              ],
            ),
          ),

          // Current Text Overlays List
          Expanded(
            child: texts.isEmpty
                ? const Center(child: Text('No text overlays yet', style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: texts.length,
                    itemBuilder: (context, idx) {
                      final item = texts[idx];
                      final isSelected = viewModel.selectedTextId == item.id;
                      return GestureDetector(
                        onTap: () => viewModel.selectText(item.id),
                        child: Container(
                          width: 140,
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            border: Border.all(
                              color: isSelected ? AppColors.accentPurple : AppColors.textTrackAccent.withOpacity(0.5),
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: item.isBold ? FontWeight.w900 : FontWeight.bold,
                                  color: item.color,
                                ),
                              ),
                              if (item.animationType != TextAnimationType.none)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    item.animationType.displayName.toUpperCase(),
                                    style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                                ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      viewModel.selectText(item.id);
                                      TextAnimationSheet.show(context, viewModel);
                                    },
                                    child: const Icon(Icons.animation_rounded, size: 16, color: AppColors.secondary),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _showAddTextModal(context, existing: item),
                                    child: const Icon(Icons.edit_rounded, size: 16, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => viewModel.removeTextOverlay(item.id),
                                    child: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
