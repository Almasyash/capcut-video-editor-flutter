import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/data/repositories/mock_media_repository.dart';

/// State representation for undo/redo history
class _EditorSnapshot {
  final List<VideoClip> clips;
  final int? selectedIndex;
  final double playheadPosition;

  _EditorSnapshot({
    required this.clips,
    required this.selectedIndex,
    required this.playheadPosition,
  });
}

/// Comprehensive ViewModel managing the CapCut video editor state, timeline playback,
/// clip modifications (split, trim, delete, duplicate), undo/redo history, and export.
class EditorViewModel extends ChangeNotifier {
  EditorViewModel() {
    _initializeProject();
  }

  // --- State Variables ---

  List<VideoClip> _videoClips = [];
  AudioTrack? _audioTrack;
  List<TextOverlay> _textOverlays = [];

  int? _selectedClipIndex;
  double _playheadPosition = 0.0; // In seconds
  bool _isPlaying = false;
  Timer? _playbackTimer;

  double _pixelsPerSecond = AppDimensions.defaultPixelsPerSecond;
  AspectRatioPreset _aspectRatio = AspectRatioPreset.ratio9x16;
  EditorCategory _activeCategory = EditorCategory.edit;
  ExportSettings _exportSettings = const ExportSettings();

  // Undo / Redo Stacks
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  // Export Progress State
  bool _isExporting = false;
  double _exportProgress = 0.0;
  Timer? _exportTimer;

  // --- Getters ---

  List<VideoClip> get videoClips => List.unmodifiable(_videoClips);
  AudioTrack? get audioTrack => _audioTrack;
  List<TextOverlay> get textOverlays => List.unmodifiable(_textOverlays);

  int? get selectedClipIndex => _selectedClipIndex;
  VideoClip? get selectedClip =>
      (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length)
          ? _videoClips[_selectedClipIndex!]
          : null;

  double get playheadPosition => _playheadPosition;
  bool get isPlaying => _isPlaying;
  double get pixelsPerSecond => _pixelsPerSecond;
  AspectRatioPreset get aspectRatio => _aspectRatio;
  EditorCategory get activeCategory => _activeCategory;
  ExportSettings get exportSettings => _exportSettings;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  bool get isExporting => _isExporting;
  double get exportProgress => _exportProgress;

  /// Total timeline duration in seconds based on active video clips
  double get totalDurationInSeconds {
    if (_videoClips.isEmpty) return 0.0;
    return _videoClips.fold(0.0, (sum, clip) => sum + clip.durationInSeconds);
  }

  /// Formatted duration object
  Duration get totalDuration => Duration(milliseconds: (totalDurationInSeconds * 1000).round());
  Duration get currentPlayheadDuration => Duration(milliseconds: (_playheadPosition * 1000).round());

  /// Returns the video clip currently visible at the playhead
  VideoClip? get currentActiveClipAtPlayhead {
    double accumulated = 0.0;
    for (final clip in _videoClips) {
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition >= accumulated && _playheadPosition <= clipEnd) {
        return clip;
      }
      accumulated = clipEnd;
    }
    return _videoClips.isNotEmpty ? _videoClips.first : null;
  }

  /// Returns active text overlay at current playhead position
  TextOverlay? get activeTextOverlay {
    for (final text in _textOverlays) {
      if (_playheadPosition >= text.startTimeInSeconds &&
          _playheadPosition <= (text.startTimeInSeconds + text.durationInSeconds)) {
        return text;
      }
    }
    return null;
  }

  // --- Initialization ---

  void _initializeProject() {
    _videoClips = MockMediaRepository.getInitialVideoClips();
    _audioTrack = MockMediaRepository.getInitialAudioTrack();
    _textOverlays = MockMediaRepository.getInitialTextOverlays();
    _selectedClipIndex = 0;
    _playheadPosition = 0.0;
    notifyListeners();
  }

  // --- History Management (Undo / Redo) ---

  void _saveSnapshot() {
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
      ),
    );
    _redoStack.clear();
    // Cap undo stack to 30 items
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
      ),
    );

    final snapshot = _undoStack.removeLast();
    _videoClips = List.from(snapshot.clips);
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
      ),
    );

    final snapshot = _redoStack.removeLast();
    _videoClips = List.from(snapshot.clips);
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    notifyListeners();
  }

  // --- Playback Controls ---

  void togglePlayPause() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (_videoClips.isEmpty) return;
    if (_playheadPosition >= totalDurationInSeconds) {
      _playheadPosition = 0.0;
    }

    _isPlaying = true;
    _playbackTimer?.cancel();

    // 33ms interval (~30 FPS playback simulation)
    const intervalMs = 33;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      final nextPos = _playheadPosition + (intervalMs / 1000.0);
      if (nextPos >= totalDurationInSeconds) {
        _playheadPosition = totalDurationInSeconds;
        pause();
      } else {
        _playheadPosition = nextPos;
        _autoSelectActiveClip();
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    notifyListeners();
  }

  void seekTo(double positionInSeconds) {
    _playheadPosition = positionInSeconds.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _autoSelectActiveClip();
    notifyListeners();
  }

  void seekBy(double deltaSeconds) {
    seekTo(_playheadPosition + deltaSeconds);
  }

  void _autoSelectActiveClip() {
    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clipEnd = accumulated + _videoClips[i].durationInSeconds;
      if (_playheadPosition >= accumulated && _playheadPosition < clipEnd) {
        if (_selectedClipIndex != i) {
          _selectedClipIndex = i;
        }
        return;
      }
      accumulated = clipEnd;
    }
  }

  // --- Clip Selection & Timeline Actions ---

  void selectClip(int index) {
    if (index >= 0 && index < _videoClips.length) {
      _selectedClipIndex = index;
      notifyListeners();
    }
  }

  void clearSelection() {
    _selectedClipIndex = null;
    notifyListeners();
  }

  /// Calculates the global start time (in seconds) of a clip at the given index
  double getClipStartTime(int clipIndex) {
    double start = 0.0;
    for (int i = 0; i < clipIndex && i < _videoClips.length; i++) {
      start += _videoClips[i].durationInSeconds;
    }
    return start;
  }

  // --- CapCut Core Action: SPLIT ---

  /// Splits the currently selected clip (or clip at playhead) into two distinct clips
  bool splitAtPlayhead() {
    if (_videoClips.isEmpty) return false;

    // Find the clip containing the playhead
    int targetIndex = -1;
    double clipGlobalStart = 0.0;
    double accumulated = 0.0;

    for (int i = 0; i < _videoClips.length; i++) {
      final clipDuration = _videoClips[i].durationInSeconds;
      final clipEnd = accumulated + clipDuration;
      if (_playheadPosition > accumulated && _playheadPosition < clipEnd) {
        targetIndex = i;
        clipGlobalStart = accumulated;
        break;
      }
      accumulated = clipEnd;
    }

    // If playhead is not strictly inside a clip, try selected clip
    if (targetIndex == -1 && _selectedClipIndex != null) {
      final selectedStart = getClipStartTime(_selectedClipIndex!);
      final selectedEnd = selectedStart + _videoClips[_selectedClipIndex!].durationInSeconds;
      if (_playheadPosition > selectedStart && _playheadPosition < selectedEnd) {
        targetIndex = _selectedClipIndex!;
        clipGlobalStart = selectedStart;
      }
    }

    if (targetIndex == -1) return false;

    final originalClip = _videoClips[targetIndex];
    final offsetInClipSeconds = _playheadPosition - clipGlobalStart;

    // Must be at least 0.2s from both edges
    if (offsetInClipSeconds < 0.2 || (originalClip.durationInSeconds - offsetInClipSeconds) < 0.2) {
      return false;
    }

    _saveSnapshot();

    final splitOffsetMs = (offsetInClipSeconds * originalClip.speed * 1000).round();
    final newSplitPoint = Duration(milliseconds: originalClip.trimStart.inMilliseconds + splitOffsetMs);

    final clipPartA = originalClip.copyWith(
      id: '${originalClip.id}_a_${DateTime.now().millisecondsSinceEpoch}',
      title: '${originalClip.title} (Part 1)',
      trimEnd: newSplitPoint,
    );

    final clipPartB = originalClip.copyWith(
      id: '${originalClip.id}_b_${DateTime.now().millisecondsSinceEpoch}',
      title: '${originalClip.title} (Part 2)',
      trimStart: newSplitPoint,
    );

    _videoClips.removeAt(targetIndex);
    _videoClips.insert(targetIndex, clipPartA);
    _videoClips.insert(targetIndex + 1, clipPartB);

    _selectedClipIndex = targetIndex + 1;
    notifyListeners();
    return true;
  }

  // --- CapCut Core Action: TRIM ---

  /// Trims the start of the selected clip to current playhead
  bool trimLeftToPlayhead() {
    if (_selectedClipIndex == null) return false;
    final clip = _videoClips[_selectedClipIndex!];
    final clipStart = getClipStartTime(_selectedClipIndex!);

    if (_playheadPosition <= clipStart || _playheadPosition >= clipStart + clip.durationInSeconds - 0.2) {
      return false;
    }

    _saveSnapshot();
    final deltaSec = _playheadPosition - clipStart;
    final deltaMs = (deltaSec * clip.speed * 1000).round();
    final newTrimStart = Duration(milliseconds: clip.trimStart.inMilliseconds + deltaMs);

    _videoClips[_selectedClipIndex!] = clip.copyWith(trimStart: newTrimStart);
    notifyListeners();
    return true;
  }

  /// Trims the end of the selected clip to current playhead
  bool trimRightToPlayhead() {
    if (_selectedClipIndex == null) return false;
    final clip = _videoClips[_selectedClipIndex!];
    final clipStart = getClipStartTime(_selectedClipIndex!);

    if (_playheadPosition <= clipStart + 0.2 || _playheadPosition >= clipStart + clip.durationInSeconds) {
      return false;
    }

    _saveSnapshot();
    final offsetSec = _playheadPosition - clipStart;
    final offsetMs = (offsetSec * clip.speed * 1000).round();
    final newTrimEnd = Duration(milliseconds: clip.trimStart.inMilliseconds + offsetMs);

    _videoClips[_selectedClipIndex!] = clip.copyWith(trimEnd: newTrimEnd);
    notifyListeners();
    return true;
  }

  /// Direct trim update from interactive drag handles
  void updateClipTrim(int index, Duration newTrimStart, Duration newTrimEnd) {
    if (index < 0 || index >= _videoClips.length) return;
    final clip = _videoClips[index];

    // Ensure minimum 0.3s duration
    if (newTrimEnd.inMilliseconds - newTrimStart.inMilliseconds < 300) return;

    _saveSnapshot();
    _videoClips[index] = clip.copyWith(
      trimStart: newTrimStart,
      trimEnd: newTrimEnd,
    );
    notifyListeners();
  }

  // --- Clip Operations: DELETE, DUPLICATE, ADD, REORDER ---

  void deleteSelectedClip() {
    if (_selectedClipIndex == null || _videoClips.isEmpty) return;
    _saveSnapshot();

    _videoClips.removeAt(_selectedClipIndex!);
    if (_videoClips.isEmpty) {
      _selectedClipIndex = null;
      _playheadPosition = 0.0;
    } else {
      _selectedClipIndex = math.min(_selectedClipIndex!, _videoClips.length - 1);
      _playheadPosition = _playheadPosition.clamp(0.0, totalDurationInSeconds);
    }
    notifyListeners();
  }

  void duplicateSelectedClip() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();

    final original = _videoClips[_selectedClipIndex!];
    final duplicated = original.copyWith(
      id: 'clip_dup_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (Copy)',
    );

    _videoClips.insert(_selectedClipIndex! + 1, duplicated);
    _selectedClipIndex = _selectedClipIndex! + 1;
    notifyListeners();
  }

  void addNewClip() {
    _saveSnapshot();
    final newClip = MockMediaRepository.createNewClip(_videoClips.length);
    _videoClips.add(newClip);
    _selectedClipIndex = _videoClips.length - 1;
    notifyListeners();
  }

  void reorderClips(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _videoClips.length) return;
    if (newIndex < 0 || newIndex > _videoClips.length) return;

    _saveSnapshot();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final clip = _videoClips.removeAt(oldIndex);
    _videoClips.insert(newIndex, clip);
    _selectedClipIndex = newIndex;
    notifyListeners();
  }

  // --- Speed & Volume Adjustments ---

  void setClipSpeed(double speed) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(speed: speed);
    notifyListeners();
  }

  void setClipVolume(double volume) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(volume: volume.clamp(0.0, 1.0));
    notifyListeners();
  }

  // --- Zoom, Aspect Ratio & Categories ---

  void setZoomScale(double pps) {
    _pixelsPerSecond = pps.clamp(AppDimensions.minPixelsPerSecond, AppDimensions.maxPixelsPerSecond);
    notifyListeners();
  }

  void setAspectRatio(AspectRatioPreset preset) {
    _aspectRatio = preset;
    notifyListeners();
  }

  void setActiveCategory(EditorCategory category) {
    _activeCategory = category;
    notifyListeners();
  }

  void updateExportSettings(ExportSettings settings) {
    _exportSettings = settings;
    notifyListeners();
  }

  // --- Export Workflow Simulation ---

  void startExportSimulation({required VoidCallback onComplete}) {
    if (_isExporting) return;
    _isExporting = true;
    _exportProgress = 0.0;
    pause();
    notifyListeners();

    _exportTimer?.cancel();
    _exportTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      _exportProgress += 0.02;
      if (_exportProgress >= 1.0) {
        _exportProgress = 1.0;
        _isExporting = false;
        _exportTimer?.cancel();
        _exportTimer = null;
        notifyListeners();
        onComplete();
      } else {
        notifyListeners();
      }
    });
  }

  void cancelExport() {
    _isExporting = false;
    _exportProgress = 0.0;
    _exportTimer?.cancel();
    _exportTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _exportTimer?.cancel();
    super.dispose();
  }
}
