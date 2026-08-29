import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/duplicate_options_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/export_modal_sheet.dart';
import 'package:capcut_video_editor/ui/features/editor/views/widgets/media_picker_sheet.dart';

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
          // 1. Play / Pause Quick Toggle
          _buildPlayPauseButton(),

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
                  label: hasSelectedText ? 'Split Text' : (hasSelectedAudio ? 'Split Audio' : 'Split'),
                  isPrimary: true,
                  enabled: (hasSelectedClip && viewModel.videoClips.isNotEmpty) || hasSelectedAudio || hasSelectedText,
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

                // Duplicate Action
                _buildActionButton(
                  context: context,
                  icon: Icons.copy_all_rounded,
                  label: 'Duplicate',
                  enabled: hasSelectedClip || hasSelectedAudio || hasSelectedText,
                  onTap: () {
                    if (hasSelectedText) {
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
                  icon: (hasSelectedAudio && (viewModel.selectedAudioTrack?.isMuted ?? false))
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: hasSelectedAudio
                      ? (viewModel.selectedAudioTrack!.isMuted
                          ? 'Muted'
                          : 'Vol (${(viewModel.selectedAudioTrack!.volume * 100).round()}%)')
                      : (hasSelectedClip
                          ? 'Vol (${(viewModel.selectedClip!.volume * 100).round()}%)'
                          : 'Volume'),
                  enabled: hasSelectedClip || hasSelectedAudio,
                  onTap: () => _showVolumeDialog(context),
                ),

                // Delete Action
                _buildActionButton(
                  context: context,
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
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
    return InkWell(
      onTap: viewModel.togglePlayPause,
      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: viewModel.isPlaying ? AppColors.secondary.withValues(alpha: 0.2) : AppColors.surfaceElevated,
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
  }) {
    Color iconColor = enabled ? AppColors.iconDefault : AppColors.iconDisabled;
    Color textColor = enabled ? AppColors.textPrimary : AppColors.textMuted;
    Color? bgColor;

    if (isPrimary && enabled) {
      iconColor = AppColors.primary;
      textColor = AppColors.primary;
      bgColor = AppColors.primary.withValues(alpha: 0.12);
    } else if (isAccent && enabled) {
      iconColor = AppColors.secondary;
      textColor = AppColors.secondary;
      bgColor = AppColors.secondary.withValues(alpha: 0.12);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0, vertical: 2.0),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            border: isPrimary && enabled ? Border.all(color: AppColors.primary.withValues(alpha: 0.4)) : null,
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
    final currentSpeed = isText ? text.speed : (isAudio ? audio.speed : clip!.speed);
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

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
            final bool isMuted = isAudio ? (viewModel.selectedAudioTrack?.isMuted ?? false) : false;

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
                          if (isAudio) ...[
                            IconButton(
                              icon: Icon(
                                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                color: isMuted ? AppColors.error : AppColors.primary,
                                size: 20,
                              ),
                              tooltip: isMuted ? 'Unmute' : 'Mute',
                              onPressed: () {
                                viewModel.toggleAudioMute(audio.id);
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(width: 4),
                          ],
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
