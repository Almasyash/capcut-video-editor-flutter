import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/duplicate_options_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/export_modal_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/speed_adjustment_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/beat_options_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/auto_captions_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/pip_overlay_sheet.dart';

/// Middle Action Toolbar containing Split, Trim Left/Right, Delete, Duplicate (with PIP option),
/// Speed, Volume, Add Clip (Media Picker), and Export.
class ActionToolbar extends StatelessWidget {
  final EditorViewModel viewModel;

  const ActionToolbar({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final hasSelectedClip = viewModel.selectedClip != null;
    final hasSelectedAudio = viewModel.selectedAudioTrack != null;
    final hasSelectedText = viewModel.selectedTextId != null;
    final hasSelectedOverlay = viewModel.selectedOverlay != null;
    final hasAnySelection = hasSelectedClip || hasSelectedAudio || hasSelectedText || hasSelectedOverlay;
    final canKeyframe = hasSelectedClip || hasSelectedOverlay;
    final isAtKeyframe = canKeyframe && viewModel.hasKeyframeAtPlayhead;
    final kfCount = canKeyframe ? viewModel.currentKeyframeCount : 0;

    return Container(
      height: AppDimensions.actionToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.8),
          bottom: BorderSide(color: AppColors.divider, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // Previous Cut / Boundary Jump
          Tooltip(
            message: 'Previous Cut / Boundary (Left Arrow)',
            waitDuration: const Duration(milliseconds: 350),
            child: InkWell(
              onTap: viewModel.seekToPreviousBoundary,
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.skip_previous_rounded, size: 20, color: AppColors.iconDefault),
              ),
            ),
          ),
          const SizedBox(width: 2),

          // 1. Play / Pause Quick Toggle
          _buildPlayPauseButton(),

          const SizedBox(width: 2),

          // Next Cut / Boundary Jump
          Tooltip(
            message: 'Next Cut / Boundary (Right Arrow)',
            waitDuration: const Duration(milliseconds: 350),
            child: InkWell(
              onTap: viewModel.seekToNextBoundary,
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.skip_next_rounded, size: 20, color: AppColors.iconDefault),
              ),
            ),
          ),

          const SizedBox(width: 4),
          const VerticalDivider(color: AppColors.divider, indent: 14, endIndent: 14),
          const SizedBox(width: 4),

          // 2. Scrollable Action Buttons (Split, Trim, Delete, Speed, Volume, Export, etc.)
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              children: [
                // Split Action
                _buildActionButton(
                  context: context,
                  icon: Icons.call_split_rounded,
                  label: hasSelectedText
                      ? 'Split Text'
                      : (hasSelectedAudio
                          ? 'Split Audio'
                          : (hasSelectedOverlay ? 'Split Overlay' : 'Split')),
                  tooltip: 'Split at playhead (S)',
                  isPrimary: true,
                  enabled: (hasSelectedClip && viewModel.videoClips.isNotEmpty) ||
                      hasSelectedAudio ||
                      hasSelectedText ||
                      hasSelectedOverlay ||
                      viewModel.videoClips.isNotEmpty,
                  onTap: () {
                    if (hasSelectedText) {
                      final success = viewModel.splitTextAtPlayhead();
                      if (success) {
                        _showFeedback(context, '✂️ Text layer split at playhead');
                      } else {
                        _showFeedback(context, 'Position playhead inside text layer to split');
                      }
                    } else if (hasSelectedAudio) {
                      final success = viewModel.splitAudioAtPlayhead();
                      if (success) {
                        _showFeedback(context, '✂️ Audio track split at playhead');
                      } else {
                        _showFeedback(context, 'Position playhead inside audio track to split');
                      }
                    } else if (hasSelectedOverlay) {
                      final success = viewModel.splitOverlayAtPlayhead();
                      if (success) {
                        _showFeedback(context, '✂️ Overlay split at playhead');
                      } else {
                        _showFeedback(context, 'Position playhead inside overlay to split');
                      }
                    } else {
                      final success = viewModel.splitClipAtPlayhead();
                      if (success) {
                        _showFeedback(context, '✂️ Clip split successfully at playhead');
                      } else {
                        _showFeedback(context, 'Place playhead inside a clip to split');
                      }
                    }
                  },
                ),

                // Trim Left
                _buildActionButton(
                  context: context,
                  icon: Icons.align_horizontal_left_rounded,
                  label: 'Trim Left',
                  tooltip: 'Left Cut / Trim head to playhead (Q)',
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText,
                  onTap: () {
                    if (hasSelectedText) {
                      final success = viewModel.trimTextLeftToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed text start to playhead');
                      } else {
                        _showFeedback(context, 'Position playhead past text start');
                      }
                    } else if (hasSelectedAudio) {
                      final success = viewModel.trimAudioLeftToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed audio start to playhead');
                      } else {
                        _showFeedback(context, 'Position playhead past audio start');
                      }
                    } else {
                      final success = viewModel.trimLeftToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed start to playhead');
                      } else {
                        _showFeedback(context, 'Select clip & position playhead past start');
                      }
                    }
                  },
                ),

                // Trim Right
                _buildActionButton(
                  context: context,
                  icon: Icons.align_horizontal_right_rounded,
                  label: 'Trim Right',
                  tooltip: 'Right Cut / Trim tail to playhead (W)',
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText,
                  onTap: () {
                    if (hasSelectedText) {
                      final success = viewModel.trimTextRightToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed text end to playhead');
                      } else {
                        _showFeedback(context, 'Position playhead before text end');
                      }
                    } else if (hasSelectedAudio) {
                      final success = viewModel.trimAudioRightToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed audio end to playhead');
                      } else {
                        _showFeedback(context, 'Position playhead before audio end');
                      }
                    } else {
                      final success = viewModel.trimRightToPlayhead();
                      if (success) {
                        _showFeedback(context, 'Trimmed end to playhead');
                      } else {
                        _showFeedback(context, 'Select clip & position playhead before end');
                      }
                    }
                  },
                ),

                // Extract Audio (Appears exclusively for selected Video Clips)
                if (hasSelectedClip)
                  _buildActionButton(
                    context: context,
                    icon: viewModel.isExtractingAudio ? Icons.hourglass_top_rounded : Icons.audiotrack_rounded,
                    label: viewModel.isExtractingAudio ? 'Extracting...' : 'Extract Audio',
                    isAccent: true,
                    enabled: !viewModel.isExtractingAudio,
                    onTap: () {
                      viewModel.extractAudioFromSelectedClip(
                        onFeedback: (msg) => _showFeedback(context, msg),
                      );
                    },
                  ),

                // Duplicate Action
                _buildActionButton(
                  context: context,
                  icon: Icons.copy_all_rounded,
                  label: 'Duplicate',
                  tooltip: 'Duplicate selected (Ctrl+D)',
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText || hasSelectedOverlay,
                  onTap: () {
                    if (hasSelectedOverlay) {
                      final dup = viewModel.duplicateSelectedOverlay();
                      if (dup != null) {
                        _showFeedback(context, '📋 Duplicated PIP layer "${dup.title}"');
                      }
                    } else if (hasSelectedText) {
                      final dup = viewModel.duplicateSelectedText();
                      if (dup != null) {
                        _showFeedback(context, '📋 Duplicated text layer "${dup.text}"');
                      }
                    } else if (hasSelectedAudio) {
                      final dup = viewModel.duplicateSelectedAudioTrack();
                      if (dup != null) {
                        _showFeedback(context, '📋 Duplicated audio track "${dup.title}"');
                      }
                    } else {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => DuplicateOptionsSheet(viewModel: viewModel),
                      );
                    }
                  },
                ),

                // Add Clip (Opens Gallery Media Picker)
                _buildActionButton(
                  context: context,
                  icon: Icons.add_photo_alternate_rounded,
                  label: 'Add Clip',
                  tooltip: 'Add / Import Media (Ctrl+I)',
                  enabled: true,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => MediaPickerSheet(viewModel: viewModel),
                    );
                  },
                ),

                // PIP Overlay (Import Media as Overlay or Open PIP Settings)
                _buildActionButton(
                  context: context,
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: hasSelectedOverlay ? 'PIP Studio' : 'PIP Overlay',
                  tooltip: 'Picture-in-Picture layer compositing',
                  isAccent: hasSelectedOverlay,
                  enabled: true,
                  onTap: () {
                    if (hasSelectedOverlay) {
                      PipOverlaySheet.show(context, viewModel, initialTab: 0);
                    } else if (hasSelectedClip) {
                      viewModel.duplicateSelectedClipAsOverlay();
                      _showFeedback(context, '✨ Duplicated clip as Picture-in-Picture (PIP) layer');
                    } else {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (ctx) => MediaPickerSheet(
                          viewModel: viewModel,
                          asOverlay: true,
                        ),
                      );
                    }
                  },
                ),

                // Chroma Key Action (Appears when Overlay is Selected)
                if (hasSelectedOverlay)
                  _buildActionButton(
                    context: context,
                    icon: Icons.auto_fix_high_rounded,
                    label: (viewModel.selectedOverlay?.enableChromaKey ?? false)
                        ? 'Chroma ON'
                        : 'Chroma Key',
                    isAccent: viewModel.selectedOverlay?.enableChromaKey ?? false,
                    enabled: true,
                    onTap: () {
                      PipOverlaySheet.show(context, viewModel, initialTab: 0);
                    },
                  ),

                // PIP Blending Action (Appears when Overlay is Selected)
                if (hasSelectedOverlay)
                  _buildActionButton(
                    context: context,
                    icon: Icons.layers_rounded,
                    label: viewModel.selectedOverlay?.blendMode != BlendMode.srcOver
                        ? 'Blend (${viewModel.selectedOverlay!.blendMode.name})'
                        : 'PIP Blend',
                    isAccent: viewModel.selectedOverlay?.blendMode != BlendMode.srcOver,
                    enabled: true,
                    onTap: () {
                      PipOverlaySheet.show(context, viewModel, initialTab: 1);
                    },
                  ),

                // Overlay Opacity Action (Appears when Overlay is Selected)
                if (hasSelectedOverlay)
                  _buildActionButton(
                    context: context,
                    icon: Icons.opacity_rounded,
                    label: 'Opacity (${((viewModel.selectedOverlay?.opacity ?? 1.0) * 100).round()}%)',
                    enabled: true,
                    onTap: () {
                      PipOverlaySheet.show(context, viewModel, initialTab: 2);
                    },
                  ),

                // Cut Action
                _buildActionButton(
                  context: context,
                  icon: Icons.content_cut_rounded,
                  label: 'Cut',
                  tooltip: 'Cut selected (Ctrl+X)',
                  enabled: hasAnySelection,
                  onTap: () {
                    final success = viewModel.cutSelected();
                    if (success) {
                      _showFeedback(context, '✂️ Cut element to clipboard');
                    }
                  },
                ),

                // Copy Action
                _buildActionButton(
                  context: context,
                  icon: Icons.content_copy_rounded,
                  label: 'Copy',
                  tooltip: 'Copy selected (Ctrl+C)',
                  enabled: hasAnySelection,
                  onTap: () {
                    final success = viewModel.copySelected();
                    if (success) {
                      _showFeedback(context, '📋 Copied element to clipboard');
                    }
                  },
                ),

                // Paste Action
                _buildActionButton(
                  context: context,
                  icon: Icons.content_paste_rounded,
                  label: 'Paste',
                  tooltip: 'Paste from clipboard at playhead (Ctrl+V)',
                  enabled: viewModel.canPaste,
                  onTap: () {
                    final success = viewModel.pasteAtPlayhead();
                    if (success) {
                      _showFeedback(context, '📥 Pasted element at playhead');
                    }
                  },
                ),

                // Edit Detailed Drawer
                _buildActionButton(
                  context: context,
                  icon: Icons.edit_note_rounded,
                  label: hasSelectedText ? 'Edit Text' : (hasSelectedAudio ? 'Audio Tools' : 'Edit Tools'),
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText,
                  onTap: () {
                    if (hasSelectedText) {
                      viewModel.openDrawer(EditorCategory.text);
                    } else if (hasSelectedAudio) {
                      viewModel.openDrawer(EditorCategory.audio);
                    } else {
                      viewModel.openDrawer(EditorCategory.edit);
                    }
                  },
                ),

                // Auto Captions & Subtitle Styling Action
                _buildActionButton(
                  context: context,
                  icon: Icons.subtitles_rounded,
                  label: hasSelectedText ? 'Captions Style' : 'Auto Captions',
                  enabled: true,
                  onTap: () {
                    AutoCaptionsSheet.show(context, viewModel);
                  },
                ),

                // CapCut-style Keyframe Control Group (⯇  ◆+ / ◆-  ⯈)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: isAtKeyframe
                        ? const Color(0xFFFFD600).withOpacity(0.15)
                        : (kfCount > 0 ? AppColors.surfaceLight : Colors.transparent),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                    border: Border.all(
                      color: isAtKeyframe
                          ? const Color(0xFFFFD600)
                          : (kfCount > 0 ? AppColors.divider : Colors.transparent),
                      width: isAtKeyframe ? 1.0 : 0.6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Previous Keyframe Arrow (⯇)
                      if (kfCount > 0)
                        InkWell(
                          onTap: (canKeyframe && viewModel.hasPreviousKeyframe)
                              ? viewModel.jumpToPreviousKeyframe
                              : null,
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.arrow_left_rounded,
                              size: 18,
                              color: (canKeyframe && viewModel.hasPreviousKeyframe)
                                  ? const Color(0xFFFFD600)
                                  : AppColors.iconDisabled,
                            ),
                          ),
                        ),

                      // Central Keyframe Button (◆+ / ◆-)
                      InkWell(
                        onTap: canKeyframe
                            ? () {
                                final wasAtKeyframe = viewModel.hasKeyframeAtPlayhead;
                                viewModel.toggleKeyframeAtPlayhead();
                                _showFeedback(
                                  context,
                                  wasAtKeyframe
                                      ? '◆ Keyframe removed'
                                      : '◆ Keyframe added at current position',
                                );
                              }
                            : null,
                        borderRadius: BorderRadius.circular(3),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(
                                    Icons.diamond_rounded,
                                    size: 16,
                                    color: !canKeyframe
                                        ? AppColors.iconDisabled
                                        : (isAtKeyframe
                                            ? const Color(0xFFFFD600)
                                            : (kfCount > 0 ? AppColors.primary : AppColors.iconDefault)),
                                  ),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Icon(
                                      isAtKeyframe ? Icons.remove : Icons.add,
                                      size: 9,
                                      color: isAtKeyframe ? Colors.redAccent : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              Text(
                                kfCount > 0 ? 'KF ($kfCount)' : 'Keyframe',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: isAtKeyframe ? FontWeight.bold : FontWeight.w500,
                                  color: !canKeyframe
                                      ? AppColors.iconDisabled
                                      : (isAtKeyframe
                                          ? const Color(0xFFFFD600)
                                          : (kfCount > 0 ? AppColors.textPrimary : AppColors.textSecondary)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Next Keyframe Arrow (⯈)
                      if (kfCount > 0)
                        InkWell(
                          onTap: (canKeyframe && viewModel.hasNextKeyframe)
                              ? viewModel.jumpToNextKeyframe
                              : null,
                          borderRadius: BorderRadius.circular(3),
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Icon(
                              Icons.arrow_right_rounded,
                              size: 18,
                              color: (canKeyframe && viewModel.hasNextKeyframe)
                                  ? const Color(0xFFFFD600)
                                  : AppColors.iconDisabled,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Speed Controller
                _buildActionButton(
                  context: context,
                  icon: Icons.speed_rounded,
                  label: hasSelectedText
                      ? 'Speed (${viewModel.selectedTextOverlay?.speed.toStringAsFixed(1) ?? '1.0'}x)'
                      : (hasSelectedAudio
                          ? 'Speed (${viewModel.selectedAudioTrack?.speed.toStringAsFixed(1) ?? '1.0'}x)'
                          : 'Speed (${viewModel.selectedClip?.speed.toStringAsFixed(1) ?? '1.0'}x)'),
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText,
                  onTap: () => _showSpeedDialog(context),
                ),

                // Volume Controller
                _buildActionButton(
                  context: context,
                  icon: ((hasSelectedAudio && (viewModel.selectedAudioTrack?.isMuted ?? false)) ||
                          (hasSelectedClip && ((viewModel.selectedClip?.isMuted ?? false) || (viewModel.selectedClip?.volume == 0.0))))
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: hasSelectedAudio
                      ? (viewModel.selectedAudioTrack!.isMuted
                          ? 'Muted'
                          : 'Vol (${(viewModel.selectedAudioTrack!.volume * 100).round()}%)')
                      : (hasSelectedClip
                          ? (viewModel.selectedClip!.isMuted
                              ? 'Muted'
                              : 'Vol (${(viewModel.selectedClip!.volume * 100).round()}%)')
                          : 'Volume'),
                  enabled: hasSelectedClip || hasSelectedAudio,
                  onTap: () => _showVolumeDialog(context),
                ),

                // Match Cut / Beats Action (Audio Track Selected)
                if (hasSelectedAudio)
                  _buildActionButton(
                    context: context,
                    icon: Icons.graphic_eq_rounded,
                    label: (viewModel.selectedAudioTrack?.beats.isNotEmpty ?? false)
                        ? 'Beats (${viewModel.selectedAudioTrack!.beats.length})'
                        : 'Beats',
                    isAccent: (viewModel.selectedAudioTrack?.beats.isNotEmpty ?? false),
                    enabled: true,
                    onTap: () => BeatOptionsSheet.show(context, viewModel),
                  ),

                // Delete Action (Context-Aware Normal Delete)
                _buildActionButton(
                  context: context,
                  icon: Icons.delete_outline_rounded,
                  label: hasSelectedText
                      ? 'Delete Text'
                      : (hasSelectedAudio
                          ? 'Delete Audio'
                          : (hasSelectedOverlay ? 'Delete Overlay' : 'Delete')),
                  tooltip: 'Delete selected (Delete / Backspace)',
                  enabled: hasAnySelection,
                  onTap: () {
                    if (hasSelectedText) {
                      viewModel.deleteSelectedText();
                      _showFeedback(context, '🗑️ Text layer removed');
                    } else if (hasSelectedAudio) {
                      viewModel.deleteSelectedAudioTrack();
                      _showFeedback(context, '🗑️ Audio track removed');
                    } else if (hasSelectedOverlay) {
                      viewModel.removeOverlayClip(viewModel.selectedOverlay!.id);
                      _showFeedback(context, '🗑️ Overlay layer removed');
                    } else if (hasSelectedClip) {
                      viewModel.deleteSelectedClip();
                      _showFeedback(context, '🗑️ Clip removed');
                    }
                  },
                ),

                // Ripple Delete Action (Main Video Track Gap Closure)
                if (hasSelectedClip || viewModel.videoClips.isNotEmpty)
                  _buildActionButton(
                    context: context,
                    icon: Icons.playlist_remove_rounded,
                    label: 'Ripple Delete',
                    tooltip: 'Ripple Delete (Shift+Delete)',
                    enabled: hasSelectedClip && viewModel.videoClips.isNotEmpty,
                    onTap: () {
                      final success = viewModel.rippleDeleteSelectedClip();
                      if (success) {
                        _showFeedback(context, '✂️ Ripple deleted clip (gap closed)');
                      } else {
                        _showFeedback(context, 'Select a video clip to ripple delete');
                      }
                    },
                  ),

                // Export Button
                _buildActionButton(
                  context: context,
                  icon: Icons.file_upload_outlined,
                  label: 'Export',
                  isAccent: true,
                  enabled: viewModel.videoClips.isNotEmpty || viewModel.audioTracks.isNotEmpty,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => ExportModalSheet(viewModel: viewModel),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return Tooltip(
      message: viewModel.isPlaying ? 'Pause (Space)' : 'Play (Space)',
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: viewModel.togglePlayPause,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: viewModel.isPlaying ? AppColors.secondary.withOpacity(0.2) : AppColors.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: viewModel.isPlaying ? AppColors.secondary : AppColors.divider,
              width: 1.2,
            ),
          ),
          child: Icon(
            viewModel.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
            color: viewModel.isPlaying ? AppColors.secondary : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    bool isPrimary = false,
    bool isAccent = false,
    String? tooltip,
  }) {
    Color iconColor = enabled ? AppColors.iconDefault : AppColors.iconDisabled;
    Color textColor = enabled ? AppColors.textPrimary : AppColors.textMuted;
    Color? bgColor;

    if (isPrimary && enabled) {
      iconColor = AppColors.primary;
      textColor = AppColors.primary;
      bgColor = AppColors.primary.withOpacity(0.12);
    } else if (isAccent && enabled) {
      iconColor = AppColors.secondary;
      textColor = AppColors.secondary;
      bgColor = AppColors.secondary.withOpacity(0.12);
    }

    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 350),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: bgColor ?? Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              border: isPrimary && enabled ? Border.all(color: AppColors.primary.withOpacity(0.4)) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: iconColor),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.0,
                    fontWeight: (isPrimary || isAccent) ? FontWeight.w700 : FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  void _showSpeedDialog(BuildContext context) {
    final audio = viewModel.selectedAudioTrack;
    final text = viewModel.selectedTextOverlay;
    final clip = viewModel.selectedClip;
    if (audio == null && clip == null && text == null) return;

    final isAudio = audio != null;
    final isText = text != null;

    if (!isAudio && !isText && clip != null) {
      SpeedAdjustmentSheet.show(context, viewModel);
      return;
    }

    final currentSpeed = isText ? text.speed : (isAudio ? audio.speed : clip!.speed);
    final speeds = [0.1, 0.5, 1.0, 1.5, 2.0, 5.0, 10.0, 50.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(AppDimensions.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isText
                        ? 'Text Speed Multiplier'
                        : (isAudio ? 'Audio Playback Speed' : 'Video Clip Speed'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  Text(
                    '${currentSpeed.toStringAsFixed(2)}x',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: speeds.map((s) {
                  final isSelected = (currentSpeed - s).abs() < 0.05;
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.surfaceLight,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        if (isText) {
                          viewModel.updateTextSpeed(text.id, s);
                        } else if (isAudio) {
                          viewModel.updateAudioSpeed(audio.id, s);
                        } else {
                          viewModel.setClipSpeed(s);
                        }
                        Navigator.of(ctx).pop();
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showVolumeDialog(BuildContext context) {
    final audio = viewModel.selectedAudioTrack;
    final clip = viewModel.selectedClip;
    if (audio == null && clip == null) return;

    final isAudio = audio != null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppDimensions.radiusMd)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final double currentVolume = isAudio ? (viewModel.selectedAudioTrack?.volume ?? 0.8) : (viewModel.selectedClip?.volume ?? 1.0);
            final bool isMuted = isAudio ? (viewModel.selectedAudioTrack?.isMuted ?? false) : (viewModel.selectedClip?.isMuted ?? false);

            return Padding(
              padding: const EdgeInsets.all(AppDimensions.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isAudio ? 'Audio Track Volume' : 'Clip Volume',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                              color: isMuted ? AppColors.error : AppColors.primary,
                              size: 20,
                            ),
                            tooltip: isMuted ? 'Unmute' : 'Mute',
                            onPressed: () {
                              if (isAudio) {
                                viewModel.toggleAudioMute(audio.id);
                              } else {
                                viewModel.toggleClipMute();
                              }
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMuted ? 'Muted' : '${(currentVolume * 100).round()}%',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isMuted ? AppColors.error : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: currentVolume.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    activeColor: isMuted ? AppColors.textMuted : AppColors.primary,
                    onChanged: isMuted
                        ? null
                        : (val) {
                            setSheetState(() {});
                            if (isAudio) {
                              viewModel.updateAudioVolume(audio.id, val);
                            } else {
                              viewModel.setClipVolume(val);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
