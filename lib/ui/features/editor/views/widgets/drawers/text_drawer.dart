import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/utils/font_helper.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/text_animation_sheet.dart';

class TextDrawer extends StatelessWidget {
  final EditorViewModel viewModel;

  const TextDrawer({
    super.key,
    required this.viewModel,
  });

  static const _availableFonts = FontHelper.availableFonts;

  void _showAddTextModal(BuildContext context, {TextOverlay? existing}) {
    showAddOrEditModal(context, viewModel, existing: existing);
  }

  static String _getFontLabel(String? family) {
    for (final f in _availableFonts) {
      if (f.family == family) return f.label;
    }
    return family ?? 'Default';
  }

  static void _showFontPicker(
    BuildContext context,
    String? currentFont,
    ValueChanged<String?> onFontSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181820),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Select Font Family',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableFonts.length,
                  itemBuilder: (context, index) {
                    final fontItem = _availableFonts[index];
                    final isSelected = (fontItem.family == null && currentFont == null) ||
                        (fontItem.family != null && fontItem.family == currentFont);
                    return ListTile(
                      dense: true,
                      tileColor: isSelected ? AppColors.primary.withOpacity(0.12) : null,
                      title: Text(
                        fontItem.label,
                        style: FontHelper.getTextStyle(
                          fontFamily: fontItem.family,
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppColors.primary : Colors.white,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        onFontSelected(fontItem.family);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays the full Add / Edit Text Layer modal with real-time typography font rendering
  static void showAddOrEditModal(
    BuildContext context,
    EditorViewModel viewModel, {
    TextOverlay? existing,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) => TextEditModalSheet(
        viewModel: viewModel,
        existing: existing,
      ),
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
                    itemBuilder: (context, index) {
                      final item = texts[index];
                      final isSelected = viewModel.selectedTextId == item.id;
                      return Container(
                        width: 140,
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary.withOpacity(0.15) : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.divider,
                            width: isSelected ? 1.5 : 0.8,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => viewModel.selectText(item.id),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                item.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: FontHelper.getTextStyle(
                                  fontFamily: item.fontFamily,
                                  fontSize: 11,
                                  fontWeight: item.isBold ? FontWeight.bold : FontWeight.normal,
                                  fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
                                  decoration: item.isUnderline ? TextDecoration.underline : TextDecoration.none,
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

class TextEditModalSheet extends StatefulWidget {
  final EditorViewModel viewModel;
  final TextOverlay? existing;

  const TextEditModalSheet({
    super.key,
    required this.viewModel,
    this.existing,
  });

  @override
  State<TextEditModalSheet> createState() => _TextEditModalSheetState();
}

class _TextEditModalSheetState extends State<TextEditModalSheet> {
  late TextEditingController _controller;
  late TextEditingController _sizeController;
  late TextOverlay _activeOverlay;
  late Color _selectedColor;
  late double _fontSize;
  late TextAlign _textAlign;
  late bool _isBold;
  late bool _isItalic;
  late bool _isUnderline;
  late Color? _backgroundColor;
  late String? _selectedFontFamily;
  bool _isSaved = false;
  late final bool _isNew;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _isNew = existing == null;
    _controller = TextEditingController(text: existing?.text ?? '');
    _selectedColor = existing?.color ?? Colors.white;
    _fontSize = (existing?.fontSize ?? 24.0).clamp(8.0, 100.0);
    _sizeController = TextEditingController(text: _fontSize.round().toString());
    _textAlign = existing?.textAlign ?? TextAlign.center;
    _isBold = existing?.isBold ?? false;
    _isItalic = existing?.isItalic ?? false;
    _isUnderline = existing?.isUnderline ?? false;
    _backgroundColor = existing?.backgroundColor;
    _selectedFontFamily = existing?.fontFamily;

    if (_isNew) {
      final playhead = widget.viewModel.playheadPosition;
      final newId = 'text_${DateTime.now().millisecondsSinceEpoch}';
      _activeOverlay = TextOverlay(
        id: newId,
        text: _controller.text.trim().isEmpty ? 'Your Title' : _controller.text.trim(),
        startTime: Duration(milliseconds: (playhead * 1000).round()),
        duration: const Duration(seconds: 4),
        textColor: _selectedColor,
        fontSize: _fontSize,
        textAlign: _textAlign,
        isBold: _isBold,
        isItalic: _isItalic,
        isUnderline: _isUnderline,
        backgroundColor: _backgroundColor,
        fontFamily: _selectedFontFamily,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.viewModel.addTextOverlay(_activeOverlay);
        widget.viewModel.selectText(_activeOverlay.id);
      });
    } else {
      _activeOverlay = existing!;
    }

    _controller.addListener(_applyLiveUpdate);
  }

  void _applyLiveUpdate() {
    if (!mounted) return;
    _activeOverlay = _activeOverlay.copyWith(
      text: _controller.text.trim().isEmpty ? (_isNew ? 'Your Title' : '') : _controller.text.trim(),
      textColor: _selectedColor,
      fontSize: _fontSize,
      textAlign: _textAlign,
      isBold: _isBold,
      isItalic: _isItalic,
      isUnderline: _isUnderline,
      backgroundColor: _backgroundColor,
      fontFamily: _selectedFontFamily,
    );
    widget.viewModel.updateTextOverlay(_activeOverlay, saveSnapshot: false, notify: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_applyLiveUpdate);
    _controller.dispose();
    _sizeController.dispose();
    if (!_isSaved) {
      if (_isNew) {
        final idToRemove = _activeOverlay.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.viewModel.removeTextOverlay(idToRemove);
        });
      } else {
        final resetSnapshot = widget.existing!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.viewModel.updateTextOverlay(resetSnapshot, saveSnapshot: false, notify: true);
        });
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
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
                  widget.existing != null ? 'Edit Text Layer' : 'Add Text Layer',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Compact Font Family Dropdown Control
            Row(
              children: [
                const Icon(Icons.font_download_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Font Family:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => TextDrawer._showFontPicker(context, _selectedFontFamily, (newFont) {
                      setState(() {
                        _selectedFontFamily = newFont;
                        _applyLiveUpdate();
                      });
                    }),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.divider, width: 1.0),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              TextDrawer._getFontLabel(_selectedFontFamily),
                              overflow: TextOverflow.ellipsis,
                              style: FontHelper.getTextStyle(
                                fontFamily: _selectedFontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded, color: AppColors.primary, size: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: false,
              textAlign: _textAlign,
              style: FontHelper.getTextStyle(
                fontSize: _fontSize.clamp(12.0, 32.0),
                fontFamily: _selectedFontFamily,
                color: _selectedColor,
                fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
                fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
                decoration: _isUnderline ? TextDecoration.underline : TextDecoration.none,
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
                  isSelected: _isBold,
                  style: IconButton.styleFrom(
                    backgroundColor: _isBold ? AppColors.primary : AppColors.surfaceLight,
                    foregroundColor: _isBold ? Colors.black : Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isBold = !_isBold;
                      _applyLiveUpdate();
                    });
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.format_italic_rounded, size: 18),
                  isSelected: _isItalic,
                  style: IconButton.styleFrom(
                    backgroundColor: _isItalic ? AppColors.primary : AppColors.surfaceLight,
                    foregroundColor: _isItalic ? Colors.black : Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isItalic = !_isItalic;
                      _applyLiveUpdate();
                    });
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.format_underlined_rounded, size: 18),
                  isSelected: _isUnderline,
                  style: IconButton.styleFrom(
                    backgroundColor: _isUnderline ? AppColors.primary : AppColors.surfaceLight,
                    foregroundColor: _isUnderline ? Colors.black : Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _isUnderline = !_isUnderline;
                      _applyLiveUpdate();
                    });
                  },
                ),
                const Spacer(),
                SegmentedButton<TextAlign>(
                  segments: const [
                    ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left_rounded, size: 16)),
                    ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center_rounded, size: 16)),
                    ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right_rounded, size: 16)),
                  ],
                  selected: {_textAlign},
                  onSelectionChanged: (val) {
                    setState(() {
                      _textAlign = val.first;
                      _applyLiveUpdate();
                    });
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.selected)) return AppColors.primary;
                      return AppColors.surfaceLight;
                    }),
                    foregroundColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.selected)) return Colors.black;
                      return Colors.white;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Color Swatches
            const Text('Text Color:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: colors.map((c) {
                final isSelected = _selectedColor.value == c.value;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = c;
                      _applyLiveUpdate();
                    });
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 6, spreadRadius: 1)]
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Font Size Controls: Numeric Input + Slider (Synchronized up to 100px)
            Row(
              children: [
                const Text('Size:', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 58,
                  height: 32,
                  child: TextField(
                    controller: _sizeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      suffixText: 'px',
                      suffixStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: AppColors.divider, width: 0.8),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val);
                      if (parsed != null && parsed >= 8 && parsed <= 100) {
                        setState(() {
                          _fontSize = parsed;
                          _applyLiveUpdate();
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _fontSize.clamp(8.0, 100.0),
                    min: 8.0,
                    max: 100.0,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.surfaceLight,
                    onChanged: (val) {
                      setState(() {
                        _fontSize = val;
                        _sizeController.text = val.round().toString();
                        _applyLiveUpdate();
                      });
                    },
                  ),
                ),
                const Text(
                  '100px',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Submit Button
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
                  final textToSave = _controller.text.trim().isEmpty ? (_isNew ? 'Your Title' : '') : _controller.text.trim();
                  if (textToSave.isNotEmpty) {
                    _isSaved = true;
                    _activeOverlay = _activeOverlay.copyWith(
                      text: textToSave,
                      textColor: _selectedColor,
                      fontSize: _fontSize,
                      textAlign: _textAlign,
                      isBold: _isBold,
                      isItalic: _isItalic,
                      isUnderline: _isUnderline,
                      backgroundColor: _backgroundColor,
                      fontFamily: _selectedFontFamily,
                    );
                    widget.viewModel.updateTextOverlay(_activeOverlay, saveSnapshot: true, notify: true);
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  widget.existing != null ? 'Save Changes' : 'Add Text to Video',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
