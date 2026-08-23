import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/export_resolution.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/data/repositories/mock_media_repository.dart';

/// State representation for undo/redo history
class _EditorSnapshot {
  final List<VideoClip> clips;
  final List<OverlayClip> overlayClips;
  final List<StickerOverlay> stickerOverlays;
  final List<TextOverlay> textOverlays;
  final AudioTrack? audioTrack;
  final int? selectedIndex;
  final double playheadPosition;
  final EditorFilter activeFilter;
  final ColorAdjustments colorAdjustments;
  final VideoEffect activeEffect;

  _EditorSnapshot({
    required this.clips,
    required this.overlayClips,
    required this.stickerOverlays,
    required this.textOverlays,
    required this.audioTrack,
    required this.selectedIndex,
    required this.playheadPosition,
    required this.activeFilter,
    required this.colorAdjustments,
    required this.activeEffect,
  });
}

/// Comprehensive ViewModel managing the Mahmas Studio video editor state, timeline playback,
/// universal multi-track trimming and dragging, undo/redo history, and export.
class EditorViewModel extends ChangeNotifier {
  EditorViewModel() {
    _initializeProject();
  }

  // --- State Variables ---

  List<MediaAsset> _mediaLibrary = [];
  List<VideoClip> _videoClips = [];
  List<OverlayClip> _overlayClips = [];
  List<StickerOverlay> _stickerOverlays = [];
  AudioTrack? _audioTrack;
  List<TextOverlay> _textOverlays = [];

  int? _selectedClipIndex;
  int? _selectedOverlayIndex;
  String? _selectedTextId;
  String? _selectedStickerId;
  bool _isAudioSelected = false;

  double _playheadPosition = 0.0; // In seconds
  bool _isPlaying = false;
  bool _isLooping = true; // Auto-loop playback for video editors
  Timer? _playbackTimer;

  double _pixelsPerSecond = AppDimensions.defaultPixelsPerSecond;
  AspectRatioPreset _aspectRatio = AspectRatioPreset.ratio9x16;
  EditorCategory? _activeDrawer;
  ExportSettings _exportSettings = const ExportSettings();

  // Filters & Adjustments
  EditorFilter _activeFilter = EditorFilter.presets.first;
  ColorAdjustments _colorAdjustments = const ColorAdjustments();
  VideoEffect _activeEffect = VideoEffect.presets.first;

  // Canvas
  Color _canvasBackgroundColor = Colors.black;
  double _canvasBlurSigma = 0.0;

  // Undo / Redo Stacks
  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];

  // Export Progress State
  bool _isExporting = false;
  double _exportProgress = 0.0;
  Timer? _exportTimer;

  // --- Getters ---

  List<MediaAsset> get mediaLibrary => List.unmodifiable(_mediaLibrary);
  List<VideoClip> get videoClips => List.unmodifiable(_videoClips);
  List<OverlayClip> get overlayClips => List.unmodifiable(_overlayClips);
  List<StickerOverlay> get stickerOverlays => List.unmodifiable(_stickerOverlays);
  AudioTrack? get audioTrack => _audioTrack;
  List<TextOverlay> get textOverlays => List.unmodifiable(_textOverlays);

  int? get selectedClipIndex => _selectedClipIndex;
  int? get selectedOverlayIndex => _selectedOverlayIndex;
  String? get selectedTextId => _selectedTextId;
  String? get selectedStickerId => _selectedStickerId;
  bool get isAudioSelected => _isAudioSelected;

  VideoClip? get selectedClip =>
      (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length)
          ? _videoClips[_selectedClipIndex!]
          : null;

  OverlayClip? get selectedOverlay =>
      (_selectedOverlayIndex != null && _selectedOverlayIndex! >= 0 && _selectedOverlayIndex! < _overlayClips.length)
          ? _overlayClips[_selectedOverlayIndex!]
          : null;

  double get playheadPosition => _playheadPosition;
  bool get isPlaying => _isPlaying;
  bool get isLooping => _isLooping;
  double get pixelsPerSecond => _pixelsPerSecond;
  AspectRatioPreset get aspectRatio => _aspectRatio;
  EditorCategory? get activeDrawer => _activeDrawer;
  ExportSettings get exportSettings => _exportSettings;

  EditorFilter get activeFilter => _activeFilter;
  ColorAdjustments get colorAdjustments => _colorAdjustments;
  VideoEffect get activeEffect => _activeEffect;
  Color get canvasBackgroundColor => _canvasBackgroundColor;
  double get canvasBlurSigma => _canvasBlurSigma;

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

  /// Returns active overlay clips visible at current playhead
  List<OverlayClip> get activeOverlayClipsAtPlayhead {
    return _overlayClips.where((o) {
      return _playheadPosition >= o.startTimeInSeconds &&
          _playheadPosition <= (o.startTimeInSeconds + o.durationInSeconds);
    }).toList();
  }

  /// Returns active stickers visible at current playhead
  List<StickerOverlay> get activeStickersAtPlayhead {
    return _stickerOverlays.where((s) {
      return _playheadPosition >= s.startTimeInSeconds &&
          _playheadPosition <= (s.startTimeInSeconds + s.durationInSeconds);
    }).toList();
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
    _overlayClips = [];
    _stickerOverlays = [];
    _selectedClipIndex = 0;
    _playheadPosition = 0.0;
    notifyListeners();
  }

  // --- History Management (Undo / Redo) ---

  void _saveSnapshot() {
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: List.from(_textOverlays),
        audioTrack: _audioTrack,
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
        activeFilter: _activeFilter,
        colorAdjustments: _colorAdjustments,
        activeEffect: _activeEffect,
      ),
    );
    _redoStack.clear();
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: List.from(_textOverlays),
        audioTrack: _audioTrack,
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
        activeFilter: _activeFilter,
        colorAdjustments: _colorAdjustments,
        activeEffect: _activeEffect,
      ),
    );

    final snapshot = _undoStack.removeLast();
    _videoClips = List.from(snapshot.clips);
    _overlayClips = List.from(snapshot.overlayClips);
    _stickerOverlays = List.from(snapshot.stickerOverlays);
    _textOverlays = List.from(snapshot.textOverlays);
    _audioTrack = snapshot.audioTrack;
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _activeFilter = snapshot.activeFilter;
    _colorAdjustments = snapshot.colorAdjustments;
    _activeEffect = snapshot.activeEffect;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: List.from(_textOverlays),
        audioTrack: _audioTrack,
        selectedIndex: _selectedClipIndex,
        playheadPosition: _playheadPosition,
        activeFilter: _activeFilter,
        colorAdjustments: _colorAdjustments,
        activeEffect: _activeEffect,
      ),
    );

    final snapshot = _redoStack.removeLast();
    _videoClips = List.from(snapshot.clips);
    _overlayClips = List.from(snapshot.overlayClips);
    _stickerOverlays = List.from(snapshot.stickerOverlays);
    _textOverlays = List.from(snapshot.textOverlays);
    _audioTrack = snapshot.audioTrack;
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _activeFilter = snapshot.activeFilter;
    _colorAdjustments = snapshot.colorAdjustments;
    _activeEffect = snapshot.activeEffect;
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

  void setLooping(bool loop) {
    _isLooping = loop;
    notifyListeners();
  }

  void play() {
    if (_videoClips.isEmpty) return;
    if (_playheadPosition >= totalDurationInSeconds) {
      _playheadPosition = 0.0;
    }

    _isPlaying = true;
    _playbackTimer?.cancel();

    // 33ms interval (~30 FPS smooth playback loop)
    const intervalMs = 33;
    _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      final nextPos = _playheadPosition + (intervalMs / 1000.0);
      if (nextPos >= totalDurationInSeconds) {
        if (_isLooping && totalDurationInSeconds > 0.0) {
          _playheadPosition = 0.0;
          _autoSelectActiveClip();
          notifyListeners();
        } else {
          _playheadPosition = totalDurationInSeconds;
          pause();
        }
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

  void _autoSelectActiveClip() {
    if (_videoClips.isEmpty) return;
    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clip = _videoClips[i];
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition >= accumulated && _playheadPosition <= clipEnd) {
        if (_selectedClipIndex != i && _selectedOverlayIndex == null && !_isAudioSelected && _selectedTextId == null && _selectedStickerId == null) {
          _selectedClipIndex = i;
        }
        break;
      }
      accumulated = clipEnd;
    }
  }

  // --- Element Selection ---

  void selectClip(int index) {
    if (index >= 0 && index < _videoClips.length) {
      _selectedClipIndex = index;
      _selectedOverlayIndex = null;
      _isAudioSelected = false;
      _selectedTextId = null;
      _selectedStickerId = null;
      notifyListeners();
    }
  }

  void selectOverlay(int index) {
    if (index >= 0 && index < _overlayClips.length) {
      _selectedOverlayIndex = index;
      _selectedClipIndex = null;
      _isAudioSelected = false;
      _selectedTextId = null;
      _selectedStickerId = null;
      notifyListeners();
    }
  }

  void selectAudio() {
    _isAudioSelected = true;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _selectedTextId = null;
    _selectedStickerId = null;
    notifyListeners();
  }

  void selectText(String id) {
    _selectedTextId = id;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _isAudioSelected = false;
    _selectedStickerId = null;
    notifyListeners();
  }

  void selectSticker(String id) {
    _selectedStickerId = id;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _isAudioSelected = false;
    _selectedTextId = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _isAudioSelected = false;
    _selectedTextId = null;
    _selectedStickerId = null;
    notifyListeners();
  }

  double getClipStartTime(int targetIndex) {
    double start = 0.0;
    for (int i = 0; i < targetIndex && i < _videoClips.length; i++) {
      start += _videoClips[i].durationInSeconds;
    }
    return start;
  }

  // --- Drawer & Sub-Panel Navigation ---

  void openDrawer(EditorCategory category) {
    _activeDrawer = category;
    notifyListeners();
  }

  void closeDrawer() {
    _activeDrawer = null;
    notifyListeners();
  }

  // --- Universal Timeline Trimming & Dragging ---

  /// Trims or moves audio track timing
  void updateAudioTrackTiming(Duration newStart, Duration newDuration) {
    if (_audioTrack == null) return;
    if (newDuration.inMilliseconds < 400) return; // Minimum 0.4s
    _saveSnapshot();

    _audioTrack = _audioTrack!.copyWith(
      startTime: newStart,
      duration: newDuration,
    );
    notifyListeners();
  }

  /// Trims or moves text overlay timing
  void updateTextOverlayTiming(String id, Duration newStart, Duration newDuration) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    if (newDuration.inMilliseconds < 300) return; // Minimum 0.3s
    _saveSnapshot();

    _textOverlays[index] = _textOverlays[index].copyWith(
      startTime: newStart,
      duration: newDuration,
    );
    notifyListeners();
  }

  /// Trims or moves PIP overlay layer timing
  void updateOverlayClipTiming(String id, Duration newStart, Duration newDuration) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    if (newDuration.inMilliseconds < 400) return; // Minimum 0.4s
    _saveSnapshot();

    _overlayClips[index] = _overlayClips[index].copyWith(
      startTime: newStart,
      duration: newDuration,
    );
    notifyListeners();
  }

  /// Trims or moves sticker overlay timing
  void updateStickerTiming(String id, Duration newStart, Duration newDuration) {
    final index = _stickerOverlays.indexWhere((s) => s.id == id);
    if (index == -1) return;
    if (newDuration.inMilliseconds < 300) return; // Minimum 0.3s
    _saveSnapshot();

    _stickerOverlays[index] = _stickerOverlays[index].copyWith(
      startTime: newStart,
      duration: newDuration,
    );
    notifyListeners();
  }

  // --- CapCut Core Action: SPLIT ---

  bool splitClipAtPlayhead() {
    if (_videoClips.isEmpty) return false;

    int targetIndex = -1;
    double clipGlobalStart = 0.0;

    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clip = _videoClips[i];
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition > accumulated + 0.1 && _playheadPosition < clipEnd - 0.1) {
        targetIndex = i;
        clipGlobalStart = accumulated;
        break;
      }
      accumulated = clipEnd;
    }

    if (targetIndex == -1 && _selectedClipIndex != null) {
      final selectedStart = getClipStartTime(_selectedClipIndex!);
      final selectedClip = _videoClips[_selectedClipIndex!];
      final selectedEnd = selectedStart + selectedClip.durationInSeconds;

      if (_playheadPosition > selectedStart + 0.1 && _playheadPosition < selectedEnd - 0.1) {
        targetIndex = _selectedClipIndex!;
        clipGlobalStart = selectedStart;
      }
    }

    if (targetIndex == -1) return false;

    final originalClip = _videoClips[targetIndex];
    final offsetInClipSeconds = _playheadPosition - clipGlobalStart;

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

  void updateClipTrim(int index, Duration newTrimStart, Duration newTrimEnd) {
    if (index < 0 || index >= _videoClips.length) return;
    final clip = _videoClips[index];

    if (newTrimEnd.inMilliseconds - newTrimStart.inMilliseconds < 300) return;

    _saveSnapshot();
    _videoClips[index] = clip.copyWith(
      trimStart: newTrimStart,
      trimEnd: newTrimEnd,
    );
    notifyListeners();
  }

  // --- Clip Operations: DELETE, DUPLICATE (Track & Layer), ADD ---

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

  /// Duplicate on main timeline track
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

  /// Duplicate as secondary Overlay / Picture-in-Picture (PIP) Layer
  void duplicateSelectedClipAsOverlay() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();

    final original = _videoClips[_selectedClipIndex!];
    final clipStart = getClipStartTime(_selectedClipIndex!);

    final overlay = OverlayClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (PIP Layer)',
      startTime: Duration(milliseconds: (clipStart * 1000).round()),
      duration: original.activeDuration,
      previewGradient: original.previewGradient,
      previewIcon: original.previewIcon,
      position: const Offset(0.7, 0.25),
      scale: 0.45,
      opacity: original.opacity,
    );

    _overlayClips.add(overlay);
    _selectedOverlayIndex = _overlayClips.length - 1;
    _selectedClipIndex = null;
    notifyListeners();
  }

  // --- Centralized Media Library Operations ---

  /// Checks if a media asset already exists in the library by comparing localPath or URI
  bool containsMediaAsset(MediaAsset asset) {
    return _mediaLibrary.any((existing) {
      if (asset.localPath != null &&
          asset.localPath!.isNotEmpty &&
          existing.localPath != null &&
          existing.localPath!.isNotEmpty) {
        return existing.localPath == asset.localPath;
      }
      if (asset.uri != null &&
          asset.uri!.isNotEmpty &&
          existing.uri != null &&
          existing.uri!.isNotEmpty) {
        return existing.uri == asset.uri;
      }
      return false;
    });
  }

  /// Adds a media asset to the central media library
  void addMediaAsset(MediaAsset asset) {
    if (containsMediaAsset(asset)) return;
    _mediaLibrary.add(asset);
    notifyListeners();
  }

  /// Removes an asset from the media library
  void removeMediaAsset(String assetId) {
    _mediaLibrary.removeWhere((asset) => asset.id == assetId);
    notifyListeners();
  }

  /// Retrieves an asset by its unique identifier
  MediaAsset? getAssetById(String assetId) {
    try {
      return _mediaLibrary.firstWhere((asset) => asset.id == assetId);
    } catch (_) {
      return null;
    }
  }

  /// Clears all assets in the media library
  void clearMediaLibrary() {
    _mediaLibrary.clear();
    notifyListeners();
  }

  /// Imports a video or photo from device storage into the central Media Library
  Future<bool> importVideoAsset() async {
    final asset = await DeviceMediaService.pickMediaAsset(type: 'video');
    if (asset == null) return false;
    if (containsMediaAsset(asset)) return false;
    _mediaLibrary.add(asset);
    notifyListeners();
    return true;
  }

  /// Imports an audio track from device storage into the central Media Library
  Future<bool> importAudioAsset() async {
    final asset = await DeviceMediaService.pickAudioAsset();
    if (asset == null) return false;
    if (containsMediaAsset(asset)) return false;
    _mediaLibrary.add(asset);
    notifyListeners();
    return true;
  }

  /// Add a clip selected from Media Picker Sheet
  void addNewClipFromMedia({
    required String assetId,
    required String title,
    required Duration duration,
    required List<Color> gradient,
    IconData icon = Icons.videocam_rounded,
  }) {
    _saveSnapshot();
    final newClip = VideoClip(
      id: 'clip_custom_${DateTime.now().microsecondsSinceEpoch}_${_videoClips.length}',
      assetId: assetId,
      title: title,
      originalDuration: duration,
      trimStart: Duration.zero,
      trimEnd: duration,
      previewGradient: gradient,
      previewIcon: icon,
    );
    _videoClips.add(newClip);
    _selectedClipIndex = _videoClips.length - 1;
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

  // --- Overlay (PIP) Operations ---

  void addOverlayClip(OverlayClip overlay) {
    _saveSnapshot();
    _overlayClips.add(overlay);
    _selectedOverlayIndex = _overlayClips.length - 1;
    notifyListeners();
  }

  void removeOverlayClip(String id) {
    _saveSnapshot();
    _overlayClips.removeWhere((o) => o.id == id);
    _selectedOverlayIndex = null;
    notifyListeners();
  }

  void updateOverlayPosition(int index, Offset newPos) {
    if (index < 0 || index >= _overlayClips.length) return;
    _overlayClips[index] = _overlayClips[index].copyWith(position: newPos);
    notifyListeners();
  }

  void updateOverlayScale(int index, double scale) {
    if (index < 0 || index >= _overlayClips.length) return;
    _overlayClips[index] = _overlayClips[index].copyWith(scale: scale);
    notifyListeners();
  }

  // --- Edit Panel Transformations ---

  void rotateSelectedClip() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final nextRotation = (clip.rotationDegrees + 90) % 360;
    _videoClips[_selectedClipIndex!] = clip.copyWith(rotationDegrees: nextRotation);
    notifyListeners();
  }

  void flipSelectedClipHorizontal() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(flipHorizontal: !clip.flipHorizontal);
    notifyListeners();
  }

  void flipSelectedClipVertical() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(flipVertical: !clip.flipVertical);
    notifyListeners();
  }

  void setSelectedClipOpacity(double opacity) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(opacity: opacity.clamp(0.0, 1.0));
    notifyListeners();
  }

  void toggleSelectedClipReverse() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(isReversed: !clip.isReversed);
    notifyListeners();
  }

  void toggleSelectedClipFreeze() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(isFrozen: !clip.isFrozen);
    notifyListeners();
  }

  void replaceSelectedClip({
    required String assetId,
    required String title,
    required Duration duration,
    required List<Color> gradient,
    IconData icon = Icons.movie_creation_outlined,
  }) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final current = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = current.copyWith(
      assetId: assetId,
      title: title,
      originalDuration: duration,
      trimStart: Duration.zero,
      trimEnd: duration,
      previewGradient: gradient,
      previewIcon: icon,
    );
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
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(volume: volume.clamp(0.0, 1.0));
    notifyListeners();
  }

  // --- Audio Track Operations ---

  void addAudioTrack(AudioTrack track) {
    _saveSnapshot();
    _audioTrack = track;
    notifyListeners();
  }

  void removeAudioTrack() {
    _saveSnapshot();
    _audioTrack = null;
    _isAudioSelected = false;
    notifyListeners();
  }

  void setAudioTrackVolume(double volume) {
    if (_audioTrack == null) return;
    _saveSnapshot();
    _audioTrack = _audioTrack!.copyWith(volume: volume.clamp(0.0, 1.0));
    notifyListeners();
  }

  // --- Text Overlay Operations ---

  void addTextOverlay(TextOverlay overlay) {
    _saveSnapshot();
    _textOverlays.add(overlay);
    notifyListeners();
  }

  void removeTextOverlay(String id) {
    _saveSnapshot();
    _textOverlays.removeWhere((t) => t.id == id);
    if (_selectedTextId == id) _selectedTextId = null;
    notifyListeners();
  }

  void updateTextOverlay(TextOverlay overlay) {
    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == overlay.id);
    if (index != -1) {
      _textOverlays[index] = overlay;
      notifyListeners();
    }
  }

  // --- Sticker Operations ---

  void addSticker(StickerPreset preset, {Duration? duration}) {
    _saveSnapshot();
    final overlay = StickerOverlay(
      id: 'sticker_${DateTime.now().millisecondsSinceEpoch}',
      preset: preset,
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      duration: duration ?? const Duration(seconds: 4),
      position: const Offset(0.5, 0.4),
      scale: 1.0,
    );
    _stickerOverlays.add(overlay);
    notifyListeners();
  }

  void removeSticker(String id) {
    _saveSnapshot();
    _stickerOverlays.removeWhere((s) => s.id == id);
    if (_selectedStickerId == id) _selectedStickerId = null;
    notifyListeners();
  }

  // --- Effects, Filters & Color Adjustments ---

  void setFilter(EditorFilter filter) {
    _saveSnapshot();
    _activeFilter = filter;
    notifyListeners();
  }

  void setFilterIntensity(double intensity) {
    _activeFilter = _activeFilter.copyWith(intensity: intensity.clamp(0.0, 1.0));
    notifyListeners();
  }

  void setEffect(VideoEffect effect) {
    _saveSnapshot();
    _activeEffect = effect;
    notifyListeners();
  }

  void updateColorAdjustments(ColorAdjustments adjustments) {
    _colorAdjustments = adjustments;
    notifyListeners();
  }

  void resetColorAdjustments() {
    _colorAdjustments = const ColorAdjustments();
    notifyListeners();
  }

  // --- Canvas Settings ---

  void setCanvasBackgroundColor(Color color) {
    _canvasBackgroundColor = color;
    notifyListeners();
  }

  void setCanvasBlurSigma(double sigma) {
    _canvasBlurSigma = sigma;
    notifyListeners();
  }

  // --- Zoom, Aspect Ratio & Export ---

  void setZoomScale(double pps) {
    _pixelsPerSecond = pps.clamp(AppDimensions.minPixelsPerSecond, AppDimensions.maxPixelsPerSecond).toDouble();
    notifyListeners();
  }

  void setAspectRatio(AspectRatioPreset preset) {
    _aspectRatio = preset;
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
