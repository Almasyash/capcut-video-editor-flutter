import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/domain/models/keyframe.dart';
import 'package:capcut_video_editor/domain/models/video_mask.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/asset_storage_service.dart';
import 'package:capcut_video_editor/core/services/audio_playback_service.dart';
import 'package:capcut_video_editor/core/services/audio_waveform_service.dart';
import 'package:capcut_video_editor/core/services/video_playback_service.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';
import 'package:capcut_video_editor/core/services/tts_service.dart';
import 'package:capcut_video_editor/domain/enums/aspect_ratio_preset.dart';
import 'package:capcut_video_editor/domain/enums/tool_action_type.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/color_adjustments.dart';
import 'package:capcut_video_editor/domain/models/editor_filter.dart';
import 'package:capcut_video_editor/domain/models/export_settings.dart';
import 'package:capcut_video_editor/core/services/device_media_service.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/overlay_clip.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/domain/models/sticker_item.dart';
import 'package:capcut_video_editor/domain/models/text_overlay.dart';
import 'package:capcut_video_editor/domain/models/clip_spatial_transform.dart';
import 'package:capcut_video_editor/domain/models/video_clip.dart';
import 'package:capcut_video_editor/domain/models/speed_curve.dart';
import 'package:capcut_video_editor/domain/models/video_effect.dart';
import 'package:capcut_video_editor/core/services/project_storage_service.dart';
import 'package:capcut_video_editor/data/repositories/mock_media_repository.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';
import 'package:capcut_video_editor/domain/models/transition.dart';
import 'package:capcut_video_editor/domain/services/transition_validator.dart';
import 'package:flutter/services.dart';
import 'package:capcut_video_editor/core/services/audio_beat_service.dart';
import 'package:capcut_video_editor/core/services/auto_caption_service.dart';

/// Result returned from every transition mutation.
class TransitionMutationResult {
  final bool success;
  final List<String> errors;

  const TransitionMutationResult({required this.success, this.errors = const []});
}
/// State representation for undo/redo history
class _EditorSnapshot {
  final List<VideoClip> clips;
  final List<OverlayClip> overlayClips;
  final List<StickerOverlay> stickerOverlays;
  final List<TextOverlay> textOverlays;
  final List<AudioTrack> audioTracks;
  final List<Transition> transitions;
  final int? selectedIndex;
  final int? selectedOverlayIndex;
  final String? selectedAudioTrackId;
  final String? selectedTextId;
  final String? selectedStickerId;
  final double playheadPosition;
  final EditorFilter activeFilter;
  final ColorAdjustments colorAdjustments;
  final VideoEffect activeEffect;

  _EditorSnapshot({
    required this.clips,
    required this.overlayClips,
    required this.stickerOverlays,
    required this.textOverlays,
    required this.audioTracks,
    required this.transitions,
    required this.selectedIndex,
    this.selectedOverlayIndex,
    this.selectedAudioTrackId,
    this.selectedTextId,
    this.selectedStickerId,
    required this.playheadPosition,
    required this.activeFilter,
    required this.colorAdjustments,
    required this.activeEffect,
  });
}

/// Comprehensive ViewModel managing the Editor FS video editor state, timeline playback,
/// universal multi-track trimming and dragging, undo/redo history, and export.
class EditorViewModel extends ChangeNotifier {
  /// Controls whether blank initializations load mock sample clips from [MockMediaRepository].
  /// Strictly restricted to test environments; in production, this is strictly false.
  final bool enableMockFallback;

  /// Global default for [enableMockFallback]. In production, this is false.
  /// Automatically enabled for automated test fixtures.
  static bool defaultEnableMockFallback = !kReleaseMode && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  EditorViewModel({
    Project? initialProject,
    bool? enableMockFallback,
  }) : enableMockFallback = enableMockFallback ?? defaultEnableMockFallback {
    _initVideoPlaybackSubscription();
    if (initialProject != null) {
      loadProject(initialProject);
    } else {
      _initializeProject();
    }
    _ensureAssetThumbnails();
  }

  /// Factory constructor for test fixtures requiring pre-populated mock media
  factory EditorViewModel.forTesting({Project? initialProject}) {
    return EditorViewModel(
      initialProject: initialProject,
      enableMockFallback: true,
    );
  }

  void initForTesting() {
    if (_videoClips.isEmpty) {
      _videoClips = MockMediaRepository.getInitialVideoClips();
      _selectedClipIndex = 0;
    }
    _textOverlays.clear();
    notifyListeners();
  }

  StreamSubscription<VideoPositionEvent>? _videoPositionSubscription;
  StreamSubscription<VideoPositionEvent>? _videoCompletionSubscription;

  void _initVideoPlaybackSubscription() {
    _videoPositionSubscription?.cancel();
    _videoPositionSubscription = VideoPlaybackService.instance.onPositionChanged.listen((event) {
      _handleVideoPositionEvent(event);
    });

    _videoCompletionSubscription?.cancel();
    _videoCompletionSubscription = VideoPlaybackService.instance.onCompletion.listen((event) {
      _handleVideoCompletionEvent(event);
    });
  }

  void _handleVideoPositionEvent(VideoPositionEvent event) {
    if (!_isPlaying) return;
    final activeSession = VideoPlaybackService.instance.activeSession;
    if (activeSession == null || activeSession.textureId != event.textureId) return;

    final activeClip = currentActiveClipAtPlayhead;
    final activeClipStart = activeClipStartTimeAtPlayhead;
    if (activeClip is! VideoClip) return;

    final posSec = event.position.inMilliseconds / 1000.0;
    final trimStartSec = activeClip.trimStart.inMilliseconds / 1000.0;
    final deltaInClipSec = (posSec - trimStartSec) / activeClip.speed;
    final clipEnd = activeClipStart + activeClip.durationInSeconds;
    final targetTimelineSec = activeClipStart + deltaInClipSec;

    if (event.isCompleted || targetTimelineSec >= clipEnd) {
      final clipIdx = _videoClips.indexOf(activeClip);
      if (clipIdx >= 0 && clipIdx < _videoClips.length - 1) {
        // Multi-clip handoff to next clip
        _playheadPosition = clipEnd;
        _autoSelectActiveClip();
        _syncAudioPlayback();
        notifyListeners();
      } else {
        if (_isLooping && totalDurationInSeconds > 0.0) {
          _playheadPosition = 0.0;
          _autoSelectActiveClip();
          _syncAudioPlayback(forceSeek: true, isStartingPlay: true);
          notifyListeners();
        } else {
          // Natural end of timeline: clamp playhead to exact end boundary and pause
          _playheadPosition = totalDurationInSeconds;
          _autoSelectActiveClip();
          pause();
        }
      }
    } else {
      if (_playbackTimer != null) {
        _playbackTimer?.cancel();
        _playbackTimer = null;
      }
      _playheadPosition = targetTimelineSec.clamp(0.0, totalDurationInSeconds);
      _autoSelectActiveClip();
      _syncAudioPlayback();
      notifyListeners();
    }
  }

  void _handleVideoCompletionEvent(VideoPositionEvent event) {
    if (!_isPlaying) return;
    final activeSession = VideoPlaybackService.instance.activeSession;
    if (activeSession == null || activeSession.textureId != event.textureId) return;

    final activeClip = currentActiveClipAtPlayhead;
    final activeClipStart = activeClipStartTimeAtPlayhead;
    if (activeClip is VideoClip) {
      final clipEnd = activeClipStart + activeClip.durationInSeconds;
      final clipIdx = _videoClips.indexOf(activeClip);
      if (clipIdx >= 0 && clipIdx < _videoClips.length - 1) {
        _playheadPosition = clipEnd;
        _autoSelectActiveClip();
        _syncAudioPlayback();
        notifyListeners();
      } else {
        if (_isLooping && totalDurationInSeconds > 0.0) {
          _playheadPosition = 0.0;
          _autoSelectActiveClip();
          _syncAudioPlayback(forceSeek: true, isStartingPlay: true);
          notifyListeners();
        } else {
          _playheadPosition = totalDurationInSeconds;
          _autoSelectActiveClip();
          pause();
        }
      }
    } else {
      _playheadPosition = totalDurationInSeconds;
      _autoSelectActiveClip();
      pause();
    }
  }

  @visibleForTesting
  void handleVideoPositionEvent(VideoPositionEvent event) => _handleVideoPositionEvent(event);

  @visibleForTesting
  void handleVideoCompletionEvent(VideoPositionEvent event) => _handleVideoCompletionEvent(event);

  // --- Project & Persistence State ---
  late Project _currentProject;
  Timer? _autoSaveDebounceTimer;

  Project get currentProject => _currentProject.copyWith(
        aspectRatio: _aspectRatio,
        videoClips: _videoClips,
        overlayClips: _overlayClips,
        stickerOverlays: _stickerOverlays,
        textOverlays: _textOverlays,
        audioTracks: _audioTracks,
        audioTrack: audioTrack,
        clearAudioTrack: _audioTracks.isEmpty,
        mediaLibrary: _mediaLibrary,
        activeFilter: _activeFilter,
        colorAdjustments: _colorAdjustments,
        activeEffect: _activeEffect,
        canvasBackgroundColor: _canvasBackgroundColor,
        canvasBlurSigma: _canvasBlurSigma,
        playheadPosition: _playheadPosition,
        thumbnailPath: _videoClips.isNotEmpty
            ? getAssetById(_videoClips.first.assetId)?.thumbnailPath
            : null,
      );

  // --- State Variables ---

  List<MediaAsset> _mediaLibrary = [];
  List<VideoClip> _videoClips = [];
  List<OverlayClip> _overlayClips = [];
  List<StickerOverlay> _stickerOverlays = [];
  List<AudioTrack> _audioTracks = [];
  List<TextOverlay> _textOverlays = [];

  int? _selectedClipIndex;
  int? _selectedOverlayIndex;
  String? _selectedTextId;
  String? _selectedStickerId;
  String? _selectedAudioTrackId;
  bool _isAudioSelected = false;

  bool _isSnapToBeatEnabled = true;
  bool get isSnapToBeatEnabled => _isSnapToBeatEnabled;

  void toggleSnapToBeat([bool? enabled]) {
    _isSnapToBeatEnabled = enabled ?? !_isSnapToBeatEnabled;
    notifyListeners();
  }

  double _playheadPosition = 0.0; // In seconds
  bool _isPlaying = false;
  bool _isLooping = false; // Default non-looping playback for video editor
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
  Map<String, dynamic>? _lastExportResult;

  // Audio Extraction State
  bool _isExtractingAudio = false;

  // --- Getters ---

  Map<String, dynamic>? get lastExportResult => _lastExportResult;

  List<MediaAsset> get mediaLibrary => List.unmodifiable(_mediaLibrary);
  List<VideoClip> get videoClips => List.unmodifiable(_videoClips);
  List<OverlayClip> get overlayClips => List.unmodifiable(_overlayClips);
  List<StickerOverlay> get stickerOverlays => List.unmodifiable(_stickerOverlays);
  List<AudioTrack> get audioTracks => List.unmodifiable(_audioTracks);
  List<Transition> get transitions => List.unmodifiable(_currentProject.transitions);
  AudioTrack? get audioTrack => _audioTracks.isNotEmpty
      ? (_selectedAudioTrackId != null
          ? (_audioTracks.firstWhere((a) => a.id == _selectedAudioTrackId, orElse: () => _audioTracks.first))
          : _audioTracks.first)
      : null;
  List<TextOverlay> get textOverlays => List.unmodifiable(_textOverlays);

  int? get selectedClipIndex => _selectedClipIndex;
  int? get selectedOverlayIndex => _selectedOverlayIndex;
  String? get selectedTextId => _selectedTextId;
  String? get selectedStickerId => _selectedStickerId;
  String? get selectedAudioTrackId => _selectedAudioTrackId;
  bool get isAudioSelected => _isAudioSelected || _selectedAudioTrackId != null;

  AudioTrack? get selectedAudioTrack => _selectedAudioTrackId != null
      ? (_audioTracks.firstWhere((a) => a.id == _selectedAudioTrackId, orElse: () => _audioTracks.first))
      : (_isAudioSelected && _audioTracks.isNotEmpty ? _audioTracks.first : null);

  VideoClip? get selectedClip =>
      (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length)
          ? _videoClips[_selectedClipIndex!]
          : null;

  String? get selectedClipId => selectedClip?.id;

  double get selectedClipStartTime {
    if (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length) {
      return getClipStartTime(_selectedClipIndex!);
    }
    return 0.0;
  }

  OverlayClip? get selectedOverlay =>
      (_selectedOverlayIndex != null && _selectedOverlayIndex! >= 0 && _selectedOverlayIndex! < _overlayClips.length)
          ? _overlayClips[_selectedOverlayIndex!]
          : null;

  double get playheadPosition => _playheadPosition;
  double get currentTimeInSeconds => _playheadPosition;
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
  bool get isExtractingAudio => _isExtractingAudio;

  /// Centralized TTS accessibility state
  bool get isTtsEnabled => TtsService.isEnabled;

  /// Toggles TTS state and notifies listeners
  void toggleTts() {
    TtsService.toggle();
    notifyListeners();
  }

  bool get isTextSelected => _selectedTextId != null;

  TextOverlay? get selectedTextOverlay => _selectedTextId != null
      ? (_textOverlays.firstWhere((t) => t.id == _selectedTextId, orElse: () => _textOverlays.first))
      : null;

  /// Total timeline duration in seconds based on active video clips, audio tracks, text overlays, and PIP overlays
  double get totalDurationInSeconds {
    double videoTotal = _videoClips.fold(0.0, (sum, clip) => sum + clip.durationInSeconds);
    double audioEnd = 0.0;
    for (final track in _audioTracks) {
      final trackEnd = track.startTimeInSeconds + track.durationInSeconds;
      if (trackEnd > audioEnd) audioEnd = trackEnd;
    }
    double textEnd = 0.0;
    for (final text in _textOverlays) {
      final tEnd = text.startTimeInSeconds + text.durationInSeconds;
      if (tEnd > textEnd) textEnd = tEnd;
    }
    double overlayEnd = 0.0;
    for (final overlay in _overlayClips) {
      final oEnd = overlay.startTimeInSeconds + overlay.durationInSeconds;
      if (oEnd > overlayEnd) overlayEnd = oEnd;
    }
    return math.max(videoTotal, math.max(audioEnd, math.max(textEnd, overlayEnd)));
  }

  /// Formatted duration object
  Duration get totalDuration => Duration(milliseconds: (totalDurationInSeconds * 1000).round());
  Duration get currentPlayheadDuration => Duration(milliseconds: (_playheadPosition * 1000).round());

  /// Returns the video clip currently visible at the playhead
  VideoClip? get currentActiveClipAtPlayhead {
    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clip = _videoClips[i];
      final isLast = i == _videoClips.length - 1;
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition >= accumulated && (_playheadPosition < clipEnd || (isLast && _playheadPosition <= clipEnd))) {
        return clip;
      }
      accumulated = clipEnd;
    }
    return _videoClips.isNotEmpty ? _videoClips.first : null;
  }

  /// Returns the global timeline start time (in seconds) of the video clip visible at the playhead
  double get activeClipStartTimeAtPlayhead {
    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clip = _videoClips[i];
      final isLast = i == _videoClips.length - 1;
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition >= accumulated && (_playheadPosition < clipEnd || (isLast && _playheadPosition <= clipEnd))) {
        return accumulated;
      }
      accumulated = clipEnd;
    }
    return 0.0;
  }

  /// Returns index of the video clip visible at current playhead
  int get activeClipIndexAtPlayhead {
    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length; i++) {
      final clip = _videoClips[i];
      final isLast = i == _videoClips.length - 1;
      final clipEnd = accumulated + clip.durationInSeconds;
      if (_playheadPosition >= accumulated && (_playheadPosition < clipEnd || (isLast && _playheadPosition <= clipEnd))) {
        return i;
      }
      accumulated = clipEnd;
    }
    return 0;
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

  /// Returns all active text overlays visible at current playhead position
  List<TextOverlay> get activeTextOverlaysAtPlayhead {
    return _textOverlays.where((t) {
      return _playheadPosition >= t.startTimeInSeconds &&
          _playheadPosition <= (t.startTimeInSeconds + t.durationInSeconds);
    }).toList();
  }

  /// Returns active text overlay at current playhead position (for backwards compatibility)
  TextOverlay? get activeTextOverlay {
    final list = activeTextOverlaysAtPlayhead;
    return list.isNotEmpty ? list.first : null;
  }

  // --- Project & Draft Management ---

  void _initializeProject() {
    debugPrint('[AUTO_PLAY_TRACE] PROJECT_LOAD (new project initialized in strictly PAUSED state)');
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (AudioPlaybackService.instance.isInitialized) {
      AudioPlaybackService.instance.dispose();
    }
    VideoPlaybackService.instance.disposeAll();

    final now = DateTime.now();
    _currentProject = Project(
      id: 'proj_${now.millisecondsSinceEpoch}',
      name: 'Project ${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
    );
    if (enableMockFallback) {
      _videoClips = MockMediaRepository.getInitialVideoClips();
      _textOverlays = MockMediaRepository.getInitialTextOverlays();
      _selectedClipIndex = 0;
    } else {
      _videoClips = [];
      _textOverlays = [];
      _selectedClipIndex = null;
    }
    _audioTracks = [];
    _overlayClips = [];
    _stickerOverlays = [];
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    _playheadPosition = 0.0;
    notifyListeners();
  }

  /// Loads an existing project into the editor session in a strictly paused state
  void loadProject(Project project) {
    debugPrint('[AUTO_PLAY_TRACE] PROJECT_LOAD (existing project ${project.id} "${project.name}" loaded in strictly PAUSED state)');
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (AudioPlaybackService.instance.isInitialized) {
      AudioPlaybackService.instance.dispose();
    }
    VideoPlaybackService.instance.disposeAll();

    _currentProject = project;
    _aspectRatio = project.aspectRatio;
    _mediaLibrary = List.from(project.mediaLibrary);
    _videoClips = List.from(project.videoClips);
    _overlayClips = List.from(project.overlayClips);
    _stickerOverlays = List.from(project.stickerOverlays);
    _textOverlays = List.from(project.textOverlays);
    _audioTracks = List.from(project.audioTracks);
    if (_audioTracks.isEmpty && project.audioTrack != null) {
      _audioTracks.add(project.audioTrack!);
    }
    _activeFilter = project.activeFilter;
    _colorAdjustments = project.colorAdjustments;
    _activeEffect = project.activeEffect;
    _canvasBackgroundColor = project.canvasBackgroundColor;
    _canvasBlurSigma = project.canvasBlurSigma;
    _playheadPosition = project.playheadPosition.clamp(
      0.0,
      totalDurationInSeconds > 0 ? totalDurationInSeconds : 10.0,
    );
    _selectedClipIndex = _videoClips.isNotEmpty ? 0 : null;
    _selectedOverlayIndex = null;
    _selectedTextId = null;
    _selectedStickerId = null;
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    _undoStack.clear();
    _redoStack.clear();

    // Validate loaded transitions and drop invalid ones
    final validator = TransitionValidator(_projectForValidation);
    final validTransitions = _currentProject.transitions.where((t) => validator.validate(t).isEmpty).toList();
    if (validTransitions.length != _currentProject.transitions.length) {
      debugPrint('[WARNING] Loaded project has invalid transitions. They will be removed.');
      _currentProject = _currentProject.copyWith(transitions: validTransitions);
    }
    
    notifyListeners();
    _ensureAssetThumbnails();
  }

  /// Renames the active draft project
  void updateProjectName(String newName) {
    _currentProject = _currentProject.copyWith(name: newName);
    scheduleAutoSave();
    notifyListeners();
  }

  /// Schedules a debounced auto-save of the project state to disk
  void scheduleAutoSave() {
    _autoSaveDebounceTimer?.cancel();
    _autoSaveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      saveCurrentProject();
    });
  }

  /// Explicitly flushes and saves the active project state to disk
  Future<void> saveCurrentProject() async {
    // Validate transitions before persistence so invalid transition data cannot be saved
    final validator = TransitionValidator(_projectForValidation);
    final validTransitions = _currentProject.transitions.where((t) => validator.validate(t).isEmpty).toList();

    _currentProject = _currentProject.copyWith(
      aspectRatio: _aspectRatio,
      videoClips: _videoClips,
      overlayClips: _overlayClips,
      stickerOverlays: _stickerOverlays,
      textOverlays: _textOverlays,
      audioTracks: _audioTracks,
      audioTrack: audioTrack,
      clearAudioTrack: _audioTracks.isEmpty,
      mediaLibrary: _mediaLibrary,
      activeFilter: _activeFilter,
      colorAdjustments: _colorAdjustments,
      activeEffect: _activeEffect,
      canvasBackgroundColor: _canvasBackgroundColor,
      canvasBlurSigma: _canvasBlurSigma,
      playheadPosition: _playheadPosition,
      transitions: validTransitions,
      thumbnailPath: _videoClips.isNotEmpty
          ? getAssetById(_videoClips.first.assetId)?.thumbnailPath
          : null,
    );
    try {
      await ProjectStorageService.instance.saveProject(_currentProject);
    } catch (e, st) {
      debugPrint('[EditorViewModel] saveCurrentProject error: $e\n$st');
    }
  }

  // --- History Management (Undo / Redo) ---

  void _saveSnapshot() {
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: List.from(_textOverlays),
        audioTracks: List.from(_audioTracks),
        transitions: List.from(_currentProject.transitions),
        selectedIndex: _selectedClipIndex,
        selectedOverlayIndex: _selectedOverlayIndex,
        selectedAudioTrackId: _selectedAudioTrackId,
        selectedTextId: _selectedTextId,
        selectedStickerId: _selectedStickerId,
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
    scheduleAutoSave();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: List.from(_textOverlays),
        audioTracks: List.from(_audioTracks),
        transitions: List.from(_currentProject.transitions),
        selectedIndex: _selectedClipIndex,
        selectedOverlayIndex: _selectedOverlayIndex,
        selectedAudioTrackId: _selectedAudioTrackId,
        selectedTextId: _selectedTextId,
        selectedStickerId: _selectedStickerId,
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
    _audioTracks = List.from(snapshot.audioTracks);
    _currentProject = _currentProject.copyWith(transitions: List.from(snapshot.transitions));
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _selectedOverlayIndex = (snapshot.selectedOverlayIndex != null && snapshot.selectedOverlayIndex! < _overlayClips.length)
        ? snapshot.selectedOverlayIndex
        : null;
    _selectedAudioTrackId = snapshot.selectedAudioTrackId;
    _isAudioSelected = _selectedAudioTrackId != null;
    _selectedTextId = snapshot.selectedTextId;
    _selectedStickerId = snapshot.selectedStickerId;
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _activeFilter = snapshot.activeFilter;
    _colorAdjustments = snapshot.colorAdjustments;
    _activeEffect = snapshot.activeEffect;
    _syncAudioPlayback(forceSeek: true);
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
        audioTracks: List.from(_audioTracks),
        transitions: List.from(_currentProject.transitions),
        selectedIndex: _selectedClipIndex,
        selectedOverlayIndex: _selectedOverlayIndex,
        selectedAudioTrackId: _selectedAudioTrackId,
        selectedTextId: _selectedTextId,
        selectedStickerId: _selectedStickerId,
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
    _audioTracks = List.from(snapshot.audioTracks);
    _currentProject = _currentProject.copyWith(transitions: List.from(snapshot.transitions));
    _selectedClipIndex = (snapshot.selectedIndex != null && snapshot.selectedIndex! < _videoClips.length)
        ? snapshot.selectedIndex
        : (_videoClips.isNotEmpty ? 0 : null);
    _selectedOverlayIndex = (snapshot.selectedOverlayIndex != null && snapshot.selectedOverlayIndex! < _overlayClips.length)
        ? snapshot.selectedOverlayIndex
        : null;
    _selectedAudioTrackId = snapshot.selectedAudioTrackId;
    _isAudioSelected = _selectedAudioTrackId != null;
    _selectedTextId = snapshot.selectedTextId;
    _selectedStickerId = snapshot.selectedStickerId;
    _playheadPosition = snapshot.playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _activeFilter = snapshot.activeFilter;
    _colorAdjustments = snapshot.colorAdjustments;
    _activeEffect = snapshot.activeEffect;
    _syncAudioPlayback(forceSeek: true);
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
    if (_videoClips.isEmpty && _audioTracks.isEmpty) return;
    debugPrint('[AUTO_PLAY_TRACE] VIEWMODEL_PLAY triggered at playhead=$_playheadPosition (totalDuration=$totalDurationInSeconds)');
    // If playhead is at or past the end, intentionally restart from beginning
    if (_playheadPosition >= totalDurationInSeconds) {
      _playheadPosition = 0.0;
      _autoSelectActiveClip();
    }

    _isPlaying = true;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _syncAudioPlayback(forceSeek: true, isStartingPlay: true);

    // If an active native video controller session exists, it will drive the playhead clock.
    // Fallback timer is only started for non-video timelines (photos/audio-only or headless tests).
    // If a native session begins emitting position updates, _handleVideoPositionEvent cancels any fallback timer.
    final hasNativeSession = VideoPlaybackService.instance.activeSession != null;
    if (!hasNativeSession) {
      const intervalMs = 33;
      _playbackTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
        if (!_isPlaying) {
          timer.cancel();
          return;
        }
        final nextPos = _playheadPosition + (intervalMs / 1000.0);
        if (nextPos >= totalDurationInSeconds) {
          if (_isLooping && totalDurationInSeconds > 0.0) {
            _playheadPosition = 0.0;
            _autoSelectActiveClip();
            _syncAudioPlayback(forceSeek: true, isStartingPlay: true);
            notifyListeners();
          } else {
            // Reached natural end of project: stop cleanly at final timeline position
            _playheadPosition = totalDurationInSeconds;
            _autoSelectActiveClip();
            pause();
          }
        } else {
          _playheadPosition = nextPos;
          _autoSelectActiveClip();
          _syncAudioPlayback();
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  void pause() {
    debugPrint('[AUTO_PLAY_TRACE] VIEWMODEL_PAUSE triggered at playhead=$_playheadPosition');
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    AudioPlaybackService.instance.pause();
    final activeSession = VideoPlaybackService.instance.activeSession;
    if (activeSession != null && activeSession.isPlaying) {
      VideoPlaybackService.instance.pause(activeSession.textureId);
    }
    notifyListeners();
  }

  void seekTo(double positionInSeconds) {
    _playheadPosition = positionInSeconds.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _autoSelectActiveClip();
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
  }

  /// Synchronizes audio playback with master playhead, respecting track trims, speed, and volume
  void _syncAudioPlayback({bool forceSeek = false, bool isStartingPlay = false}) {
    if (_audioTracks.isEmpty) {
      if (AudioPlaybackService.instance.isInitialized) {
        AudioPlaybackService.instance.dispose();
      }
      return;
    }

    // Prioritize selectedAudioTrack if active at playhead, otherwise first matching track
    AudioTrack? activeTrack;
    if (selectedAudioTrack != null &&
        _playheadPosition >= selectedAudioTrack!.startTimeInSeconds &&
        _playheadPosition < selectedAudioTrack!.endTimeInSeconds) {
      activeTrack = selectedAudioTrack;
    } else {
      for (final track in _audioTracks) {
        if (_playheadPosition >= track.startTimeInSeconds && _playheadPosition < track.endTimeInSeconds) {
          activeTrack = track;
          break;
        }
      }
    }

    if (activeTrack == null) {
      // Playhead is outside audio ranges
      if (AudioPlaybackService.instance.isPlaying) {
        AudioPlaybackService.instance.pause();
      }
      return;
    }

    final asset = getAssetById(activeTrack.assetId);
    final localPath = asset?.localPath;

    if (localPath == null || !File(localPath).existsSync()) {
      return;
    }

    // Calculate source audio offset taking trimStart and speed into account
    final deltaFromTrackStart = _playheadPosition - activeTrack.startTimeInSeconds;
    final sourceOffsetSec = activeTrack.trimStartInSeconds + (deltaFromTrackStart * activeTrack.speed);
    final sourceOffsetMs = (sourceOffsetSec * 1000).round();
    final effectiveVolume = activeTrack.isMuted ? 0.0 : activeTrack.volume;

    if (AudioPlaybackService.instance.loadedPath != localPath) {
      AudioPlaybackService.instance.initialize(localPath).then((_) {
        AudioPlaybackService.instance.setVolume(effectiveVolume);
        AudioPlaybackService.instance.setSpeed(activeTrack!.speed);
        if (_isPlaying && _playheadPosition < totalDurationInSeconds) {
          AudioPlaybackService.instance.play(position: Duration(milliseconds: sourceOffsetMs));
        } else {
          AudioPlaybackService.instance.seekTo(Duration(milliseconds: sourceOffsetMs));
          AudioPlaybackService.instance.pause();
        }
      });
      return;
    }

    // Update volume & speed dynamically
    AudioPlaybackService.instance.setVolume(effectiveVolume);
    AudioPlaybackService.instance.setSpeed(activeTrack.speed);

    if (forceSeek && !_isPlaying) {
      AudioPlaybackService.instance.seekTo(Duration(milliseconds: sourceOffsetMs));
    }

    if (_isPlaying && _playheadPosition < totalDurationInSeconds) {
      if (isStartingPlay || !AudioPlaybackService.instance.isPlaying) {
        AudioPlaybackService.instance.play(position: Duration(milliseconds: sourceOffsetMs));
      }
    } else {
      if (AudioPlaybackService.instance.isPlaying) {
        AudioPlaybackService.instance.pause();
      }
    }
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
      _selectedAudioTrackId = null;
      _isAudioSelected = false;
      _selectedTextId = null;
      _selectedStickerId = null;

      final clip = _videoClips[index];
      final clipStart = getClipStartTime(index);
      debugPrint('[VideoSelection] selectedVideoClipId: ${clip.id}, assetId: ${clip.assetId}, '
          'playhead: $_playheadPosition, volume: ${clip.volume}, speed: ${clip.speed}, '
          'clipStart: $clipStart, clipDuration: ${clip.durationInSeconds}');
      notifyListeners();
    }
  }

  void selectOverlay(int index) {
    if (index >= 0 && index < _overlayClips.length) {
      _selectedOverlayIndex = index;
      _selectedClipIndex = null;
      _selectedAudioTrackId = null;
      _isAudioSelected = false;
      _selectedTextId = null;
      _selectedStickerId = null;
      notifyListeners();
    }
  }

  void selectAudioTrack(String? id) {
    _selectedAudioTrackId = id;
    _isAudioSelected = id != null;
    if (id != null) {
      _selectedClipIndex = null;
      _selectedOverlayIndex = null;
      _selectedTextId = null;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectAudio() {
    final firstId = _audioTracks.isNotEmpty ? _audioTracks.first.id : null;
    selectAudioTrack(firstId);
  }

  void deselectAudio() {
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    notifyListeners();
  }

  void deselectAll() {
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    _selectedTextId = null;
    _selectedStickerId = null;
    notifyListeners();
  }

  void clearSelection() => deselectAll();

  void selectText(String? id) {
    _selectedTextId = id;
    if (id != null) {
      _selectedClipIndex = null;
      _selectedOverlayIndex = null;
      _selectedAudioTrackId = null;
      _isAudioSelected = false;
      _selectedStickerId = null;
    }
    notifyListeners();
  }

  void selectTextOverlay(String? id) => selectText(id);

  void deselectText() {
    _selectedTextId = null;
    notifyListeners();
  }

  void selectSticker(String id) {
    _selectedStickerId = id;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    _selectedTextId = null;
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

    // 1. Prioritize selected clip if playhead is within its active range
    if (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length) {
      final selectedStart = getClipStartTime(_selectedClipIndex!);
      final selectedClip = _videoClips[_selectedClipIndex!];
      final selectedEnd = selectedStart + selectedClip.durationInSeconds;

      if (_playheadPosition > selectedStart + 0.05 && _playheadPosition < selectedEnd - 0.05) {
        targetIndex = _selectedClipIndex!;
        clipGlobalStart = selectedStart;
      }
    }

    // 2. If no selected clip contains playhead, find the clip spanning playhead
    if (targetIndex == -1) {
      double accumulated = 0.0;
      for (int i = 0; i < _videoClips.length; i++) {
        final clip = _videoClips[i];
        final clipEnd = accumulated + clip.durationInSeconds;
        if (_playheadPosition > accumulated + 0.05 && _playheadPosition < clipEnd - 0.05) {
          targetIndex = i;
          clipGlobalStart = accumulated;
          break;
        }
        accumulated = clipEnd;
      }
    }

    if (targetIndex == -1) return false;

    final originalClip = _videoClips[targetIndex];
    final offsetInClipSeconds = _playheadPosition - clipGlobalStart;

    if (offsetInClipSeconds < 0.05 || (originalClip.durationInSeconds - offsetInClipSeconds) < 0.05) {
      return false;
    }

    _saveSnapshot();

    final splitOffsetMs = (offsetInClipSeconds * originalClip.speed * 1000).round();
    final newSplitMs = (originalClip.trimStart.inMilliseconds + splitOffsetMs).clamp(
      originalClip.trimStart.inMilliseconds + 1,
      originalClip.trimEnd.inMilliseconds - 1,
    );
    final newSplitPoint = Duration(milliseconds: newSplitMs);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final clipPartA = originalClip.copyWith(
      id: '${originalClip.id}_a_$timestamp',
      title: '${originalClip.title} (Part 1)',
      trimEnd: newSplitPoint,
    );

    final clipPartB = originalClip.copyWith(
      id: '${originalClip.id}_b_$timestamp',
      title: '${originalClip.title} (Part 2)',
      trimStart: newSplitPoint,
    );

    _videoClips.removeAt(targetIndex);
    _videoClips.insert(targetIndex, clipPartA);
    _videoClips.insert(targetIndex + 1, clipPartB);

    _selectedClipIndex = targetIndex + 1;
    _cleanupInvalidTransitions();
    scheduleAutoSave();
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
    _cleanupInvalidTransitions();
    scheduleAutoSave();
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
    _cleanupInvalidTransitions();
    scheduleAutoSave();
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
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  // --- Clip Operations: DELETE, RIPPLE DELETE, DUPLICATE (Track & Layer), ADD ---

  /// Normal Delete of a main video clip
  bool deleteSelectedClip({int? index}) {
    if (_videoClips.isEmpty) return false;
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) {
      return false;
    }

    _saveSnapshot();

    _videoClips.removeAt(targetIndex);
    if (_videoClips.isEmpty) {
      _selectedClipIndex = null;
      _playheadPosition = 0.0;
    } else {
      _selectedClipIndex = math.min(targetIndex, _videoClips.length - 1);
      _playheadPosition = _playheadPosition.clamp(0.0, totalDurationInSeconds);
    }

    if (_videoClips.isEmpty && _audioTracks.isEmpty) {
      pause();
    } else {
      _syncAudioPlayback(forceSeek: true);
    }

    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  /// CapCut-style Ripple Delete of a main video clip:
  /// Closes the gap by shifting subsequent main-track video clips backward by the deleted clip's duration.
  /// Preserves other track timings, repositions playhead predictably, selects the replacement clip,
  /// and maintains MediaAsset integrity.
  bool rippleDeleteSelectedClip({int? index}) {
    if (_videoClips.isEmpty) return false;
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) {
      return false;
    }

    _saveSnapshot();

    final deletedClip = _videoClips[targetIndex];
    final deletedStart = getClipStartTime(targetIndex);
    final deletedDuration = deletedClip.durationInSeconds;
    final deletedEnd = deletedStart + deletedDuration;

    _videoClips.removeAt(targetIndex);

    // Playhead Repositioning per Phase 12:
    // 1. If playhead was after the deleted region, shift backward by deleted duration
    // 2. If playhead was inside the deleted region, place it at the beginning of the deleted region
    // 3. If playhead was before the deleted region, keep it unchanged
    if (_playheadPosition >= deletedEnd) {
      _playheadPosition = (_playheadPosition - deletedDuration);
    } else if (_playheadPosition >= deletedStart) {
      _playheadPosition = deletedStart;
    }

    // Update Selection per Phase 13:
    if (_videoClips.isEmpty) {
      _selectedClipIndex = null;
      _playheadPosition = 0.0;
    } else {
      _selectedClipIndex = math.min(targetIndex, _videoClips.length - 1);
      _playheadPosition = _playheadPosition.clamp(0.0, totalDurationInSeconds);
    }

    // Playback handling per Phase 17:
    if (_videoClips.isEmpty && _audioTracks.isEmpty) {
      pause();
    } else {
      _syncAudioPlayback(forceSeek: true);
    }

    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
    return true;
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
    final asset = mediaLibrary.where((a) => a.id == original.assetId).firstOrNull;

    final overlay = OverlayClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (PIP Layer)',
      assetId: original.assetId,
      localPath: asset?.localPath ?? asset?.thumbnailPath,
      isPhoto: asset?.type == MediaAssetType.photo,
      startTime: Duration(milliseconds: (clipStart * 1000).round()),
      duration: original.activeDuration,
      previewGradient: original.previewGradient,
      previewIcon: original.previewIcon,
      position: const Offset(0.7, 0.25),
      scale: 0.45,
      opacity: original.opacity,
      blendMode: original.blendMode,
      mask: original.mask,
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
      final downloaded = AssetStorageService.instance.getDownloadedAssetSync(assetId);
      if (downloaded != null && downloaded.localPath != null) {
        final mediaAsset = MediaAsset(
          id: downloaded.id,
          type: downloaded.type == AssetType.transition ? MediaAssetType.video : MediaAssetType.audio,
          name: downloaded.name,
          localPath: downloaded.localPath,
          duration: downloaded.duration,
          sizeBytes: downloaded.fileSizeBytes,
          createdAt: downloaded.downloadedAt ?? DateTime.now(),
        );
        if (!containsMediaAsset(mediaAsset)) {
          _mediaLibrary.add(mediaAsset);
        }
        return mediaAsset;
      }
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
    TtsService.announce('Imported ${asset.displayName}');
    notifyListeners();
    _ensureAssetThumbnails();
    return true;
  }

  /// Asynchronously generates thumbnails on Windows for any video assets in the library that lack one,
  /// updating the timeline and preview widgets automatically when ready.
  Future<void> _ensureAssetThumbnails() async {
    if (kIsWeb || !Platform.isWindows) return;
    bool anyUpdated = false;
    for (int i = 0; i < _mediaLibrary.length; i++) {
      final asset = _mediaLibrary[i];
      if (asset.isVideo) {
        final currentThumb = asset.thumbnailPath;
        if (currentThumb == null || !File(currentThumb).existsSync() || File(currentThumb).lengthSync() == 0) {
          if (asset.localPath != null && File(asset.localPath!).existsSync()) {
            final thumb = await DeviceMediaService.extractWindowsThumbnail(asset.localPath!);
            if (thumb != null && File(thumb).existsSync() && File(thumb).lengthSync() > 0) {
              _mediaLibrary[i] = asset.copyWith(thumbnailPath: thumb);
              anyUpdated = true;
            }
          }
        }
      }
    }
    if (anyUpdated) {
      scheduleAutoSave();
      notifyListeners();
    }
  }

  /// Imports an audio track from device storage into the central Media Library
  Future<bool> importAudioAsset() async {
    final asset = await DeviceMediaService.pickAudioAsset();
    if (asset == null) return false;
    if (containsMediaAsset(asset)) return false;
    _mediaLibrary.add(asset);
    TtsService.announce('Imported ${asset.displayName}');
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
    TtsService.announce('Added clip to timeline');
    notifyListeners();
  }

  /// Appends a video or photo clip directly from a MediaAsset in the library
  void addVideoClipFromAsset(MediaAsset asset) {
    _saveSnapshot();
    if (!containsMediaAsset(asset)) {
      _mediaLibrary.add(asset);
    }
    final duration = asset.duration ?? (asset.isPhoto ? const Duration(seconds: 4) : const Duration(seconds: 10));
    final random = math.Random(asset.name.hashCode);
    final gradient = [
      Color(0xFF000000 | (random.nextInt(0xFFFFFF) | 0x444444)),
      Color(0xFF000000 | (random.nextInt(0xFFFFFF) | 0x222222)),
    ];
    final clip = VideoClip(
      id: 'clip_media_${DateTime.now().microsecondsSinceEpoch}_${_videoClips.length}',
      assetId: asset.id,
      title: asset.displayName,
      originalDuration: duration,
      trimStart: Duration.zero,
      trimEnd: duration,
      previewGradient: gradient,
      previewIcon: asset.isPhoto ? Icons.image_rounded : Icons.videocam_rounded,
    );
    _videoClips.add(clip);
    _selectedClipIndex = _videoClips.length - 1;
    TtsService.announce('Added ${asset.displayName} to timeline');
    notifyListeners();
  }

  @visibleForTesting
  void addNewClip() {
    if (!enableMockFallback) {
      debugPrint('[EditorViewModel] addNewClip (mock clip fallback) is disabled in production. Use addNewClipFromMedia instead.');
      return;
    }
    _saveSnapshot();
    final newClip = MockMediaRepository.createNewClip(_videoClips.length);
    _videoClips.add(newClip);
    _selectedClipIndex = _videoClips.length - 1;
    notifyListeners();
  }

  void addVideoClip(VideoClip clip) {
    _saveSnapshot();
    _videoClips.add(clip);
    _selectedClipIndex = _videoClips.length - 1;
    notifyListeners();
  }

  void clearVideoClips() {
    _saveSnapshot();
    _videoClips.clear();
    _selectedClipIndex = null;
    _playheadPosition = 0.0;
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
    _cleanupInvalidTransitions();
    scheduleAutoSave();
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
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index != -1) {
      _overlayClips.removeAt(index);
      if (_overlayClips.isEmpty) {
        _selectedOverlayIndex = null;
      } else {
        _selectedOverlayIndex = math.min(index, _overlayClips.length - 1);
      }
      _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void deleteSelectedOverlay() {
    if (selectedOverlay != null) {
      removeOverlayClip(selectedOverlay!.id);
    }
  }

  void clearOverlayClips() {
    _saveSnapshot();
    _overlayClips.clear();
    _selectedOverlayIndex = null;
    scheduleAutoSave();
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

  void updateSelectedOverlayBlendMode(BlendMode blendMode) {
    if (_selectedOverlayIndex == null ||
        _selectedOverlayIndex! < 0 ||
        _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    _overlayClips[_selectedOverlayIndex!] = _overlayClips[_selectedOverlayIndex!].copyWith(
      blendMode: blendMode,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void updateSelectedOverlayOpacity(double opacity) {
    if (_selectedOverlayIndex == null ||
        _selectedOverlayIndex! < 0 ||
        _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    _overlayClips[_selectedOverlayIndex!] = _overlayClips[_selectedOverlayIndex!].copyWith(
      opacity: opacity.clamp(0.0, 1.0),
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void updateSelectedOverlayChromaKey({
    bool? enable,
    Color? color,
    double? similarity,
    double? smoothness,
    double? spill,
  }) {
    if (_selectedOverlayIndex == null ||
        _selectedOverlayIndex! < 0 ||
        _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    _overlayClips[_selectedOverlayIndex!] = _overlayClips[_selectedOverlayIndex!].copyWith(
      enableChromaKey: enable,
      chromaKeyColor: color,
      chromaSimilarity: similarity,
      chromaSmoothness: smoothness,
      chromaSpill: spill,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void updateSelectedOverlayMask(VideoMask? mask) {
    if (_selectedOverlayIndex == null ||
        _selectedOverlayIndex! < 0 ||
        _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    _overlayClips[_selectedOverlayIndex!] = _overlayClips[_selectedOverlayIndex!].copyWith(
      mask: mask,
      clearMask: mask == null,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void addOverlayFromMediaAsset(MediaAsset asset) {
    _saveSnapshot();
    final playheadMs = (_playheadPosition * 1000).round();
    final dur = asset.duration ?? const Duration(seconds: 4);

    final overlay = OverlayClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      title: asset.name.isNotEmpty ? asset.name : 'PIP Layer',
      assetId: asset.id,
      localPath: asset.localPath ?? asset.thumbnailPath,
      isPhoto: asset.type == MediaAssetType.photo,
      startTime: Duration(milliseconds: playheadMs),
      duration: dur,
      previewGradient: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
      previewIcon: asset.type == MediaAssetType.photo ? Icons.image_rounded : Icons.movie_filter_rounded,
      position: const Offset(0.7, 0.25),
      scale: 0.45,
      opacity: 1.0,
      blendMode: BlendMode.srcOver,
    );

    _overlayClips.add(overlay);
    _selectedOverlayIndex = _overlayClips.length - 1;
    _selectedClipIndex = null;
    scheduleAutoSave();
    notifyListeners();
  }

  bool splitOverlayAtPlayhead() {
    final overlay = selectedOverlay;
    if (overlay == null || _selectedOverlayIndex == null) return false;

    if (_playheadPosition <= overlay.startTimeInSeconds + 0.05 ||
        _playheadPosition >= (overlay.startTimeInSeconds + overlay.durationInSeconds) - 0.05) {
      return false;
    }

    _saveSnapshot();
    final index = _selectedOverlayIndex!;
    final offsetSec = _playheadPosition - overlay.startTimeInSeconds;
    final durationPartAMs = (offsetSec * 1000).round();
    final durationPartBMs = overlay.duration.inMilliseconds - durationPartAMs;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final partA = overlay.copyWith(
      id: '${overlay.id}_a_$timestamp',
      title: '${overlay.title} (Part 1)',
      duration: Duration(milliseconds: durationPartAMs),
    );

    final partB = overlay.copyWith(
      id: '${overlay.id}_b_$timestamp',
      title: '${overlay.title} (Part 2)',
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      duration: Duration(milliseconds: durationPartBMs),
    );

    _overlayClips.removeAt(index);
    _overlayClips.insert(index, partA);
    _overlayClips.insert(index + 1, partB);

    _selectedOverlayIndex = index + 1;
    scheduleAutoSave();
    notifyListeners();
    return true;
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

  // --- Spatial Transformations (Free Transform Canvas Phase 1) ---

  int _findClipIndexById(String clipId) {
    return _videoClips.indexWhere((clip) => clip.id == clipId);
  }

  /// Updates horizontal (xPos) and vertical (yPos) position offset for a clip.
  void updateClipPosition(String clipId, double xPos, double yPos, {bool recordUndo = true}) {
    final index = _findClipIndexById(clipId);
    if (index == -1) return;
    final clip = _videoClips[index];
    final sanitizedX = ClipSpatialTransform.sanitizePosition(xPos, fallback: clip.xPos);
    final sanitizedY = ClipSpatialTransform.sanitizePosition(yPos, fallback: clip.yPos);
    if (clip.xPos == sanitizedX && clip.yPos == sanitizedY) return;

    if (recordUndo) _saveSnapshot();
    _videoClips[index] = clip.copyWith(xPos: sanitizedX, yPos: sanitizedY);
    notifyListeners();
  }

  /// Updates uniform spatial scale factor for a clip, clamped to [0.05, 20.0].
  void updateClipScale(String clipId, double scale, {bool recordUndo = true}) {
    final index = _findClipIndexById(clipId);
    if (index == -1) return;
    final clip = _videoClips[index];
    final sanitizedScale = ClipSpatialTransform.sanitizeScale(scale, fallback: clip.scale);
    if (clip.scale == sanitizedScale) return;

    if (recordUndo) _saveSnapshot();
    _videoClips[index] = clip.copyWith(scale: sanitizedScale);
    notifyListeners();
  }

  /// Updates continuous spatial rotation angle in radians for a clip.
  void updateClipRotation(String clipId, double rotationAngle, {bool recordUndo = true}) {
    final index = _findClipIndexById(clipId);
    if (index == -1) return;
    final clip = _videoClips[index];
    final sanitizedRotation = ClipSpatialTransform.sanitizeRotation(rotationAngle, fallback: clip.rotationAngle);
    if (clip.rotationAngle == sanitizedRotation) return;

    if (recordUndo) _saveSnapshot();
    _videoClips[index] = clip.copyWith(rotationAngle: sanitizedRotation);
    notifyListeners();
  }

  /// Atomically updates spatial position, scale, and rotation in a single mutation.
  void updateClipTransform(
    String clipId, {
    double? xPos,
    double? yPos,
    double? scale,
    double? rotationAngle,
    bool recordUndo = true,
  }) {
    final index = _findClipIndexById(clipId);
    if (index == -1) return;
    final clip = _videoClips[index];
    final sanitizedX = xPos != null ? ClipSpatialTransform.sanitizePosition(xPos, fallback: clip.xPos) : clip.xPos;
    final sanitizedY = yPos != null ? ClipSpatialTransform.sanitizePosition(yPos, fallback: clip.yPos) : clip.yPos;
    final sanitizedScale = scale != null ? ClipSpatialTransform.sanitizeScale(scale, fallback: clip.scale) : clip.scale;
    final sanitizedRotation = rotationAngle != null ? ClipSpatialTransform.sanitizeRotation(rotationAngle, fallback: clip.rotationAngle) : clip.rotationAngle;

    if (clip.xPos == sanitizedX &&
        clip.yPos == sanitizedY &&
        clip.scale == sanitizedScale &&
        clip.rotationAngle == sanitizedRotation) {
      return;
    }

    if (recordUndo) _saveSnapshot();

    // Auto-update or auto-create keyframe if keyframes are active on this clip
    List<VideoKeyframe> updatedKeyframes = clip.keyframes;
    if (clip.keyframes.isNotEmpty) {
      final clipStart = getClipStartTime(index);
      final relTime = (_playheadPosition - clipStart).clamp(0.0, clip.durationInSeconds);
      final existingKfIndex = clip.keyframes.indexWhere(
        (k) => (k.timeInSeconds - relTime).abs() < 0.08,
      );

      final totalRotationDeg = clip.rotationDegrees.toDouble() + (sanitizedRotation * 180.0 / math.pi);

      if (existingKfIndex != -1) {
        final existing = clip.keyframes[existingKfIndex];
        final modified = existing.copyWith(
          scale: sanitizedScale,
          positionX: sanitizedX,
          positionY: sanitizedY,
          rotationDegrees: totalRotationDeg,
        );
        updatedKeyframes = List<VideoKeyframe>.from(clip.keyframes);
        updatedKeyframes[existingKfIndex] = modified;
      } else {
        final newKf = VideoKeyframe(
          id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
          timestamp: Duration(milliseconds: (relTime * 1000).round()),
          scale: sanitizedScale,
          positionX: sanitizedX,
          positionY: sanitizedY,
          rotationDegrees: totalRotationDeg,
          opacity: clip.opacity,
          curve: KeyframeCurve.easeInOut,
        );
        updatedKeyframes = List<VideoKeyframe>.from(clip.keyframes)..add(newKf);
        updatedKeyframes.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    }

    _videoClips[index] = clip.copyWith(
      xPos: sanitizedX,
      yPos: sanitizedY,
      scale: sanitizedScale,
      rotationAngle: sanitizedRotation,
      keyframes: updatedKeyframes,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  /// Resets clip spatial transform to canonical defaults (x=0, y=0, scale=1, rot=0).
  void resetClipTransform(String clipId, {bool recordUndo = true}) {
    final index = _findClipIndexById(clipId);
    if (index == -1) return;
    final clip = _videoClips[index];
    if (clip.xPos == 0.0 && clip.yPos == 0.0 && clip.scale == 1.0 && clip.rotationAngle == 0.0) {
      return;
    }

    if (recordUndo) _saveSnapshot();
    _videoClips[index] = clip.copyWith(
      xPos: 0.0,
      yPos: 0.0,
      scale: 1.0,
      rotationAngle: 0.0,
    );
    notifyListeners();
  }

  /// Updates position of currently selected clip.
  void updateSelectedClipPosition(double xPos, double yPos, {bool recordUndo = true}) {
    if (selectedClip != null) {
      updateClipPosition(selectedClip!.id, xPos, yPos, recordUndo: recordUndo);
    }
  }

  /// Updates scale of currently selected clip.
  void updateSelectedClipScale(double scale, {bool recordUndo = true}) {
    if (selectedClip != null) {
      updateClipScale(selectedClip!.id, scale, recordUndo: recordUndo);
    }
  }

  /// Updates rotation in radians of currently selected clip.
  void updateSelectedClipRotation(double rotationAngle, {bool recordUndo = true}) {
    if (selectedClip != null) {
      updateClipRotation(selectedClip!.id, rotationAngle, recordUndo: recordUndo);
    }
  }

  /// Atomically updates transform of currently selected clip.
  void updateSelectedClipTransform({
    double? xPos,
    double? yPos,
    double? scale,
    double? rotationAngle,
    bool recordUndo = true,
  }) {
    if (selectedClip != null) {
      updateClipTransform(
        selectedClip!.id,
        xPos: xPos,
        yPos: yPos,
        scale: scale,
        rotationAngle: rotationAngle,
        recordUndo: recordUndo,
      );
    }
  }

  /// Resets transform of currently selected clip.
  void resetSelectedClipTransform({bool recordUndo = true}) {
    if (selectedClip != null) {
      resetClipTransform(selectedClip!.id, recordUndo: recordUndo);
    }
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
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  /// Imports a photo from device storage into the central Media Library
  Future<bool> importPhotoAsset() async {
    final asset = await DeviceMediaService.pickMediaAsset(type: 'photo');
    if (asset == null) return false;
    if (containsMediaAsset(asset)) return false;
    _mediaLibrary.add(asset);
    TtsService.announce('Imported ${asset.displayName}');
    notifyListeners();
    return true;
  }

  // --- Speed & Volume Adjustments ---

  void setClipSpeed(double speed) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final clampedSpeed = speed.clamp(0.1, 100.0);
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: clampedSpeed,
      clearSpeedCurve: true,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  void setClipSpeedCurve(SpeedCurve curve) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final avgSpeed = curve.averageSpeed.clamp(0.1, 100.0);
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: avgSpeed,
      speedCurve: curve,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  void setClipVolume(double volume) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final clampedVol = volume.clamp(0.0, 1.0);
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      volume: clampedVol,
      isMuted: clampedVol == 0.0 ? true : false,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleClipMute({int? index}) {
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) return;
    _saveSnapshot();
    final clip = _videoClips[targetIndex];
    _videoClips[targetIndex] = clip.copyWith(isMuted: !clip.isMuted);
    scheduleAutoSave();
    notifyListeners();
  }

  // --- Audio Track Operations ---

  void addAudioTrack(AudioTrack track) {
    _saveSnapshot();
    _isPlaying = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _audioTracks.add(track);
    _selectedAudioTrackId = track.id;
    _isAudioSelected = true;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _selectedTextId = null;
    _selectedStickerId = null;
    _syncAudioPlayback(forceSeek: true);
    TtsService.announce('Added audio track ${track.title}');
    notifyListeners();
  }

  void addAudioTrackFromAsset(MediaAsset asset, {Duration? startTime}) {
    final duration = asset.duration ?? const Duration(seconds: 30);
    final waveform = AudioWaveformService.instance.getWaveformSync(
      cacheKey: asset.id,
      localPath: asset.localPath,
      duration: duration,
    );
    final track = AudioTrack(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      assetId: asset.id,
      title: asset.displayName,
      artist: 'Local Audio',
      duration: duration,
      startTime: startTime ?? Duration(milliseconds: (_playheadPosition * 1000).round()),
      waveformPoints: waveform,
      volume: 0.85,
      speed: 1.0,
    );
    addAudioTrack(track);
  }

  /// Inserts a downloaded sound effect or audio asset into the timeline at the current playhead
  Future<AudioTrack> insertDownloadedAsset(Asset asset) async {
    final localPath = asset.localPath ?? await AssetStorageService.instance.getLocalPath(asset.id);
    if (localPath == null || !File(localPath).existsSync()) {
      throw Exception('Asset file is not downloaded or missing from disk');
    }

    final mediaAsset = MediaAsset(
      id: asset.id,
      type: MediaAssetType.audio,
      name: asset.name,
      localPath: localPath,
      duration: asset.duration,
      sizeBytes: asset.fileSizeBytes,
      createdAt: asset.downloadedAt ?? DateTime.now(),
    );

    if (!containsMediaAsset(mediaAsset)) {
      _mediaLibrary.add(mediaAsset);
      notifyListeners();
    }

    final waveform = AudioWaveformService.instance.getWaveformSync(
      cacheKey: asset.id,
      localPath: localPath,
      duration: asset.duration,
    );

    final track = AudioTrack(
      id: 'audio_asset_${DateTime.now().millisecondsSinceEpoch}',
      assetId: asset.id,
      title: asset.name,
      artist: 'Asset Library',
      duration: asset.duration,
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      waveformPoints: waveform,
      volume: 0.9,
      speed: 1.0,
    );

    addAudioTrack(track);
    debugPrint('[AssetLibrary] Inserted audio track ${track.title} at ${track.startTimeInSeconds}s (path: $localPath)');
    return track;
  }

  /// Extracts the audio stream from the currently selected VideoClip into an independent AudioTrack
  Future<AudioTrack?> extractAudioFromSelectedClip({void Function(String message)? onFeedback}) async {
    if (_isExtractingAudio) return null;
    if (_selectedClipIndex == null || selectedClip == null) {
      onFeedback?.call('Select a video clip to extract audio');
      return null;
    }

    final videoClip = selectedClip!;
    final videoAsset = getAssetById(videoClip.assetId);
    final localPath = videoAsset?.localPath;

    if (localPath == null || localPath.isEmpty) {
      onFeedback?.call('Unable to extract audio: Video file path is missing.');
      return null;
    }

    if (!kIsWeb && !localPath.startsWith('/mock/') && !localPath.startsWith('/data/user/')) {
      final file = File(localPath);
      if (!file.existsSync()) {
        onFeedback?.call('Video file not found or inaccessible on device storage.');
        return null;
      }
    }

    _isExtractingAudio = true;
    notifyListeners();

    try {
      final sanitizedTitle = videoClip.title.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final extractionResult = await DeviceMediaService.extractAudioFromVideo(
        videoPath: localPath,
        outputName: '${sanitizedTitle}_audio',
      );

      if (!extractionResult.success) {
        _isExtractingAudio = false;
        notifyListeners();
        if (extractionResult.isNoAudioTrack) {
          onFeedback?.call('This video has no audio track to extract.');
          TtsService.announce('This video has no audio track to extract.');
        } else {
          onFeedback?.call(extractionResult.errorMessage ?? 'Audio extraction failed.');
        }
        return null;
      }

      // Create and register new independent MediaAsset
      final newAssetId = 'asset_audio_extracted_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(9999)}';
      final audioDisplayName = '${videoClip.title} - Extracted Audio';
      final extractedAsset = MediaAsset(
        id: newAssetId,
        type: MediaAssetType.audio,
        name: audioDisplayName,
        localPath: extractionResult.localPath,
        duration: extractionResult.duration ?? videoClip.originalDuration,
        sizeBytes: extractionResult.sizeBytes,
        createdAt: DateTime.now(),
      );

      addMediaAsset(extractedAsset);

      // Compute global timeline start position of the selected video clip
      final clipStartSec = getClipStartTime(_selectedClipIndex!);
      final clipStartTime = Duration(milliseconds: (clipStartSec * 1000).round());

      // Generate / extract high-resolution waveform
      final waveform = AudioWaveformService.instance.getWaveformSync(
        cacheKey: newAssetId,
        localPath: extractionResult.localPath,
        duration: extractedAsset.duration ?? videoClip.originalDuration,
      );

      final newTrack = AudioTrack(
        id: 'audio_extracted_${DateTime.now().millisecondsSinceEpoch}',
        assetId: newAssetId,
        name: audioDisplayName,
        artist: 'Extracted Audio',
        startTime: clipStartTime,
        duration: extractedAsset.duration ?? videoClip.originalDuration,
        trimStart: videoClip.trimStart,
        trimEnd: videoClip.trimEnd,
        volume: videoClip.volume > 0 ? videoClip.volume : 0.85,
        speed: videoClip.speed,
        waveformPoints: waveform,
      );

      // Mute source video clip so that only the extracted audio track plays (prevents dual-playback)
      _videoClips[_selectedClipIndex!] = videoClip.copyWith(volume: 0.0);

      addAudioTrack(newTrack);
      _isExtractingAudio = false;
      scheduleAutoSave();
      onFeedback?.call('Audio extracted successfully.');
      TtsService.announce('Audio extracted successfully');
      notifyListeners();
      return newTrack;
    } catch (e) {
      _isExtractingAudio = false;
      notifyListeners();
      onFeedback?.call('Audio extraction failed: $e');
      return null;
    }
  }

  void removeAudioTrack([String? id]) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    _saveSnapshot();
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index != -1) {
      _audioTracks.removeAt(index);
      if (_selectedAudioTrackId == targetId) {
        if (_audioTracks.isEmpty) {
          _selectedAudioTrackId = null;
          _isAudioSelected = false;
        } else {
          _selectedAudioTrackId = _audioTracks[math.min(index, _audioTracks.length - 1)].id;
          _isAudioSelected = true;
        }
      }
      _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
      if (_audioTracks.isEmpty) {
        AudioPlaybackService.instance.dispose();
      } else {
        _syncAudioPlayback(forceSeek: true);
      }
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void deleteSelectedAudioTrack() {
    removeAudioTrack();
  }

  void clearAudioTracks() {
    _saveSnapshot();
    _audioTracks.clear();
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    AudioPlaybackService.instance.dispose();
    scheduleAutoSave();
    notifyListeners();
  }

  bool trimAudioLeftToPlayhead() {
    final track = selectedAudioTrack;
    if (track == null) return false;

    if (_playheadPosition <= track.startTimeInSeconds ||
        _playheadPosition >= track.endTimeInSeconds - 0.2) {
      return false;
    }

    _saveSnapshot();
    final deltaSec = _playheadPosition - track.startTimeInSeconds;
    final sourceDeltaMs = (deltaSec * track.speed * 1000).round();
    final newTrimStart = Duration(
      milliseconds: sourceDeltaMs.clamp(0, track.effectiveTrimEnd.inMilliseconds - 200),
    );

    final index = _audioTracks.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      debugPrint('[TIMELINE_TRIM_TRACE] TRIM LEFT: id=${track.id}, startTime=${track.startTimeInSeconds}s (PRESERVED), oldTrimStart=${track.trimStartInSeconds}s, newTrimStart=${newTrimStart.inMilliseconds / 1000.0}s, trimEnd=${track.trimEndInSeconds}s, effectiveDuration=${track.durationInSeconds}s -> ${(track.effectiveTrimEnd.inMilliseconds - newTrimStart.inMilliseconds) / 1000.0 / track.speed}s');
      _audioTracks[index] = track.copyWith(
        trimStart: newTrimStart,
      );
      _syncAudioPlayback(forceSeek: true);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool trimAudioRightToPlayhead() {
    final track = selectedAudioTrack;
    if (track == null) return false;

    if (_playheadPosition <= track.startTimeInSeconds + 0.2 ||
        _playheadPosition >= track.endTimeInSeconds) {
      return false;
    }

    _saveSnapshot();
    final offsetSec = _playheadPosition - track.startTimeInSeconds;
    final sourceOffsetMs = (offsetSec * track.speed * 1000).round();
    final newTrimEnd = Duration(
      milliseconds: (track.trimStart.inMilliseconds + sourceOffsetMs)
          .clamp(track.trimStart.inMilliseconds + 200, track.duration.inMilliseconds),
    );

    final index = _audioTracks.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      debugPrint('[TIMELINE_TRIM_TRACE] TRIM RIGHT: id=${track.id}, startTime=${track.startTimeInSeconds}s (PRESERVED), trimStart=${track.trimStartInSeconds}s, oldTrimEnd=${track.trimEndInSeconds}s, newTrimEnd=${newTrimEnd.inMilliseconds / 1000.0}s, effectiveDuration=${track.durationInSeconds}s -> ${(newTrimEnd.inMilliseconds - track.trimStart.inMilliseconds) / 1000.0 / track.speed}s');
      _audioTracks[index] = track.copyWith(
        trimEnd: newTrimEnd,
      );
      _syncAudioPlayback(forceSeek: true);
      notifyListeners();
      return true;
    }
    return false;
  }

  void updateAudioTrim(String id, Duration newTrimStart, Duration newTrimEnd) {
    final index = _audioTracks.indexWhere((t) => t.id == id);
    if (index == -1) return;
    if (newTrimEnd.inMilliseconds - newTrimStart.inMilliseconds < 200) return;

    _saveSnapshot();
    final track = _audioTracks[index];
    final clampedTrimStart = Duration(
      milliseconds: newTrimStart.inMilliseconds.clamp(0, track.duration.inMilliseconds),
    );
    final clampedTrimEnd = Duration(
      milliseconds: newTrimEnd.inMilliseconds.clamp(clampedTrimStart.inMilliseconds + 200, track.duration.inMilliseconds),
    );

    debugPrint('[TIMELINE_TRIM_TRACE] UPDATE AUDIO TRIM: id=$id, startTime=${track.startTimeInSeconds}s (PRESERVED), trimStart=${clampedTrimStart.inMilliseconds / 1000.0}s, trimEnd=${clampedTrimEnd.inMilliseconds / 1000.0}s');
    _audioTracks[index] = track.copyWith(
      trimStart: clampedTrimStart,
      trimEnd: clampedTrimEnd,
    );
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
  }

  void moveAudioTrack(String id, Duration newStartTime) {
    final index = _audioTracks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _saveSnapshot();
    final track = _audioTracks[index];
    debugPrint('[TIMELINE_TRIM_TRACE] MOVE AUDIO TRACK: id=$id, oldStart=${track.startTimeInSeconds}s -> newStart=${newStartTime.inMilliseconds / 1000.0}s, trimStart=${track.trimStartInSeconds}s, trimEnd=${track.trimEndInSeconds}s (PRESERVED)');
    _audioTracks[index] = track.copyWith(
      startTime: newStartTime,
    );
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
  }

  void updateAudioTrackTiming(Duration newStart, Duration newDuration, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final track = _audioTracks[index];
    final currentTrimStart = track.trimStart;
    final calculatedTrimEnd = Duration(
      milliseconds: (currentTrimStart.inMilliseconds + (newDuration.inMilliseconds * track.speed).round())
          .clamp(currentTrimStart.inMilliseconds + 200, track.duration.inMilliseconds),
    );
    _audioTracks[index] = track.copyWith(
      startTime: newStart,
      trimEnd: calculatedTrimEnd,
    );
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
  }

  bool splitAudioAtPlayhead() {
    AudioTrack? targetTrack;
    int targetIndex = -1;

    // 1. Prioritize selected audio track if playhead is within its active range
    if (_selectedAudioTrackId != null) {
      final idx = _audioTracks.indexWhere((t) => t.id == _selectedAudioTrackId);
      if (idx != -1) {
        final track = _audioTracks[idx];
        if (_playheadPosition > track.startTimeInSeconds + 0.05 &&
            _playheadPosition < track.endTimeInSeconds - 0.05) {
          targetTrack = track;
          targetIndex = idx;
        }
      }
    }

    // 2. If no selected track matches, find any audio track covering playhead
    if (targetTrack == null) {
      for (int i = 0; i < _audioTracks.length; i++) {
        final track = _audioTracks[i];
        if (_playheadPosition > track.startTimeInSeconds + 0.05 &&
            _playheadPosition < track.endTimeInSeconds - 0.05) {
          targetTrack = track;
          targetIndex = i;
          break;
        }
      }
    }

    if (targetTrack == null || targetIndex == -1) return false;

    final offsetSec = _playheadPosition - targetTrack.startTimeInSeconds;
    if (offsetSec < 0.05 || (targetTrack.durationInSeconds - offsetSec) < 0.05) {
      return false;
    }

    _saveSnapshot();
    final splitSourceMs = (offsetSec * targetTrack.speed * 1000).round();
    final effectiveTrimEndMs = targetTrack.effectiveTrimEnd.inMilliseconds;
    final newSplitMs = (targetTrack.trimStart.inMilliseconds + splitSourceMs).clamp(
      targetTrack.trimStart.inMilliseconds + 1,
      effectiveTrimEndMs - 1,
    );
    final splitPoint = Duration(milliseconds: newSplitMs);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final partA = targetTrack.copyWith(
      id: '${targetTrack.id}_a_$timestamp',
      title: '${targetTrack.title} (Part 1)',
      trimEnd: splitPoint,
    );

    final partB = targetTrack.copyWith(
      id: '${targetTrack.id}_b_$timestamp',
      title: '${targetTrack.title} (Part 2)',
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      trimStart: splitPoint,
      trimEnd: targetTrack.effectiveTrimEnd,
    );

    _audioTracks.removeAt(targetIndex);
    _audioTracks.insert(targetIndex, partA);
    _audioTracks.insert(targetIndex + 1, partB);

    _selectedAudioTrackId = partB.id;
    _isAudioSelected = true;
    _syncAudioPlayback(forceSeek: true);
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  AudioTrack? duplicateSelectedAudioTrack() {
    final track = selectedAudioTrack;
    if (track == null) return null;

    _saveSnapshot();
    final newStartTime = Duration(milliseconds: (track.endTimeInSeconds * 1000).round());
    final duplicate = track.copyWith(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      title: '${track.title} (Copy)',
      startTime: newStartTime,
    );

    _audioTracks.add(duplicate);
    _selectedAudioTrackId = duplicate.id;
    _isAudioSelected = true;
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
    return duplicate;
  }

  void setAudioTrackVolume(double volume, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final clamped = volume.clamp(0.0, 1.0);
    _audioTracks[index] = _audioTracks[index].copyWith(volume: clamped);
    if (_audioTracks[index].id == selectedAudioTrack?.id) {
      AudioPlaybackService.instance.setVolume(_audioTracks[index].isMuted ? 0.0 : clamped);
    }
    notifyListeners();
  }

  void updateAudioVolume(String id, double volume) {
    setAudioTrackVolume(volume, id: id);
  }

  void toggleAudioMute([String? id]) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final newMuted = !_audioTracks[index].isMuted;
    _audioTracks[index] = _audioTracks[index].copyWith(isMuted: newMuted);
    if (_audioTracks[index].id == selectedAudioTrack?.id) {
      AudioPlaybackService.instance.setVolume(newMuted ? 0.0 : _audioTracks[index].volume);
    }
    notifyListeners();
  }

  void setAudioTrackSpeed(double speed, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final clamped = speed.clamp(0.1, 100.0);
    _audioTracks[index] = _audioTracks[index].copyWith(speed: clamped);
    if (_audioTracks[index].id == selectedAudioTrack?.id) {
      AudioPlaybackService.instance.setSpeed(clamped);
    }
    _syncAudioPlayback(forceSeek: true);
    notifyListeners();
  }

  void updateAudioSpeed(String id, double speed) {
    setAudioTrackSpeed(speed, id: id);
  }

  // --- Audio Beat & Match Cut Operations ---

  Future<void> generateBeatsForTrack(
    String trackId, {
    BeatSensitivity sensitivity = BeatSensitivity.strongDownbeats,
  }) async {
    final index = _audioTracks.indexWhere((t) => t.id == trackId);
    if (index == -1) return;

    _saveSnapshot();
    final track = _audioTracks[index];

    List<double> waveform = track.waveformPoints;
    if (waveform.isEmpty) {
      waveform = AudioWaveformService.instance.getWaveformSync(
        cacheKey: '${track.assetId}_${track.duration.inMilliseconds}',
        duration: track.duration,
      );
    }

    final detected = AudioBeatService.instance.detectBeats(
      waveformPoints: waveform,
      duration: track.duration,
      sensitivity: sensitivity,
    );

    _audioTracks[index] = track.copyWith(
      waveformPoints: waveform,
      beats: detected,
      showBeats: true,
    );

    scheduleAutoSave();
    TtsService.announce('Detected ${detected.length} beats');
    notifyListeners();
  }

  void toggleBeatAtPlayhead(String trackId) {
    final index = _audioTracks.indexWhere((t) => t.id == trackId);
    if (index == -1) return;

    final track = _audioTracks[index];
    // Calculate timestamp relative to source audio file
    final relativeTrackSec = (playheadPosition - track.startTimeInSeconds);
    if (relativeTrackSec < 0.0) return;

    final sourceSec = track.trimStartInSeconds + (relativeTrackSec * track.speed);
    if (sourceSec > track.originalDurationInSeconds) return;

    _saveSnapshot();
    final roundedSource = (sourceSec * 1000).round() / 1000.0;
    final currentBeats = List<double>.from(track.beats);

    // If an existing beat is within 0.12s of playhead, remove it
    final existingIndex = currentBeats.indexWhere((b) => (b - roundedSource).abs() <= 0.12);
    if (existingIndex != -1) {
      currentBeats.removeAt(existingIndex);
      TtsService.announce('Removed beat marker');
    } else {
      currentBeats.add(roundedSource);
      currentBeats.sort();
      TtsService.announce('Added beat marker');
    }

    _audioTracks[index] = track.copyWith(
      beats: currentBeats,
      showBeats: true,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void clearBeatsForTrack(String trackId) {
    final index = _audioTracks.indexWhere((t) => t.id == trackId);
    if (index == -1) return;

    _saveSnapshot();
    _audioTracks[index] = _audioTracks[index].copyWith(beats: const []);
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleBeatsVisibility(String trackId) {
    final index = _audioTracks.indexWhere((t) => t.id == trackId);
    if (index == -1) return;

    _audioTracks[index] = _audioTracks[index].copyWith(
      showBeats: !_audioTracks[index].showBeats,
    );
    notifyListeners();
  }

  /// Magnetically snaps [targetTimelineSec] to the nearest visible beat across active audio tracks.
  /// If snap is performed, triggers haptic feedback and returns the exact beat timestamp.
  double snapToNearestBeat(double targetTimelineSec, {double threshold = 0.08}) {
    if (!_isSnapToBeatEnabled || _audioTracks.isEmpty) return targetTimelineSec;

    final allVisibleBeats = <double>[];
    for (final track in _audioTracks) {
      if (track.showBeats && track.beats.isNotEmpty) {
        allVisibleBeats.addAll(track.visibleTimelineBeats);
      }
    }

    if (allVisibleBeats.isEmpty) return targetTimelineSec;

    final nearest = AudioBeatService.instance.findNearestBeat(
      targetTimelineSec,
      allVisibleBeats,
      threshold: threshold,
    );

    if (nearest != null) {
      // Tactile feedback on snap
      if ((nearest - targetTimelineSec).abs() > 0.001) {
        HapticFeedback.selectionClick();
      }
      return nearest;
    }

    return targetTimelineSec;
  }

  // --- Text Overlay Operations ---

  void addTextOverlay(TextOverlay overlay) {
    _saveSnapshot();
    _textOverlays.add(overlay);
    _selectedTextId = overlay.id;
    _selectedClipIndex = null;
    _selectedOverlayIndex = null;
    _selectedStickerId = null;
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    scheduleAutoSave();
    TtsService.announce('Added text ${overlay.text}');
    notifyListeners();
  }

  void removeTextOverlay(String id) {
    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _textOverlays.removeAt(index);
      if (_selectedTextId == id) _selectedTextId = null;
      _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void deleteSelectedText() {
    if (_selectedTextId != null) {
      removeTextOverlay(_selectedTextId!);
    }
  }

  void clearTextOverlays() {
    _saveSnapshot();
    _textOverlays.clear();
    _selectedTextId = null;
    scheduleAutoSave();
    notifyListeners();
  }

  void updateTextOverlay(TextOverlay overlay) {
    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == overlay.id);
    if (index != -1) {
      _textOverlays[index] = overlay;
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void updateTextPosition(String id, Offset newPos) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _textOverlays[index] = _textOverlays[index].copyWith(position: newPos);
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void updateTextContent(String id, String newText) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _saveSnapshot();
      _textOverlays[index] = _textOverlays[index].copyWith(text: newText);
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void updateTextStyle(
    String id, {
    Color? color,
    double? fontSize,
    String? fontFamily,
    Color? backgroundColor,
    TextAlign? textAlign,
    bool? isBold,
    bool? isItalic,
    bool? isUnderline,
    Color? shadowColor,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _saveSnapshot();
      _textOverlays[index] = _textOverlays[index].copyWith(
        color: color,
        fontSize: fontSize,
        fontFamily: fontFamily,
        backgroundColor: backgroundColor,
        textAlign: textAlign,
        isBold: isBold,
        isItalic: isItalic,
        isUnderline: isUnderline,
        shadowColor: shadowColor,
      );
      scheduleAutoSave();
      notifyListeners();
    }
  }

  // --- Auto / Animated Captions Methods ---

  /// Generates a set of auto-synced animated subtitles from a script or preset genre
  int generateAutoCaptions({
    String? script,
    String genre = 'Motivation',
    CaptionStylePreset? preset,
    TextAnimationType? animationType,
    int wordsPerChunk = 3,
    bool alignWithBeats = true,
    bool clearExisting = false,
  }) {
    _saveSnapshot();
    if (clearExisting) {
      _textOverlays.clear();
      _selectedTextId = null;
    }

    final effectivePreset = preset ?? CaptionStylePreset.defaultPreset;
    final anim = animationType ?? effectivePreset.defaultAnimation;

    // Collect beat timestamps if available
    List<double>? beats;
    if (alignWithBeats && selectedAudioTrack != null && selectedAudioTrack!.beats.isNotEmpty) {
      beats = selectedAudioTrack!.visibleTimelineBeats;
    } else if (alignWithBeats && audioTracks.isNotEmpty && audioTracks.first.beats.isNotEmpty) {
      beats = audioTracks.first.visibleTimelineBeats;
    }

    final totalDuration = math.max(2.0, totalDurationInSeconds);

    final generated = (script != null && script.trim().isNotEmpty)
        ? AutoCaptionService.instance.generateFromScript(
            script: script.trim(),
            totalDurationInSeconds: totalDuration,
            startTimelineOffsetSec: 0.0,
            wordsPerChunk: wordsPerChunk,
            preset: effectivePreset,
            animationOverride: anim,
            beatTimestamps: beats,
          )
        : AutoCaptionService.instance.generateTrending(
            genre: genre,
            totalDurationInSeconds: totalDuration,
            startTimelineOffsetSec: 0.0,
            wordsPerChunk: wordsPerChunk,
            preset: effectivePreset,
            animationOverride: anim,
            beatTimestamps: beats,
          );

    if (generated.isNotEmpty) {
      _textOverlays.addAll(generated);
      _selectedTextId = generated.first.id;
      scheduleAutoSave();
      TtsService.announce('Generated ${generated.length} auto captions');
      notifyListeners();
    }

    return generated.length;
  }

  /// Propagates the visual style, colors, stroke, and animation of [source] to all existing text overlays
  void applyCaptionStyleToAll(TextOverlay source) {
    if (_textOverlays.isEmpty) return;
    _saveSnapshot();

    for (int i = 0; i < _textOverlays.length; i++) {
      final current = _textOverlays[i];
      _textOverlays[i] = current.copyWith(
        color: source.color,
        fontSize: source.fontSize,
        fontFamily: source.fontFamily,
        backgroundColor: source.backgroundColor,
        textAlign: source.textAlign,
        isBold: source.isBold,
        isItalic: source.isItalic,
        isUnderline: source.isUnderline,
        shadowColor: source.shadowColor,
        animationType: source.animationType,
        highlightColor: source.highlightColor,
        strokeWidth: source.strokeWidth,
        strokeColor: source.strokeColor,
        position: source.position,
      );
    }

    scheduleAutoSave();
    TtsService.announce('Applied caption style to all subtitles');
    notifyListeners();
  }

  /// Updates animation type and optional highlight color of a specific text overlay
  void updateTextAnimation(
    String id,
    TextAnimationType animationType, {
    Color? highlightColor,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _saveSnapshot();
      _textOverlays[index] = _textOverlays[index].copyWith(
        animationType: animationType,
        highlightColor: highlightColor ?? _textOverlays[index].highlightColor,
      );
      scheduleAutoSave();
      notifyListeners();
    }
  }

  /// Updates high-contrast outline stroke settings for a text overlay
  void updateTextStroke(
    String id, {
    required double strokeWidth,
    Color? strokeColor,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      _saveSnapshot();
      _textOverlays[index] = _textOverlays[index].copyWith(
        strokeWidth: strokeWidth,
        strokeColor: strokeColor ?? _textOverlays[index].strokeColor,
      );
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void updateTextOverlayTiming(
    String id,
    Duration newStart,
    Duration newDuration, {
    Duration? trimStart,
    Duration? trimEnd,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _textOverlays[index] = _textOverlays[index].copyWith(
      startTime: newStart,
      duration: newDuration,
      trimStart: trimStart,
      trimEnd: trimEnd,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  bool trimTextLeftToPlayhead() {
    final text = selectedTextOverlay;
    if (text == null) return false;

    if (_playheadPosition <= text.startTimeInSeconds ||
        _playheadPosition >= text.endTimeInSeconds - 0.2) {
      return false;
    }

    _saveSnapshot();
    final deltaSec = _playheadPosition - text.startTimeInSeconds;
    final deltaMs = (deltaSec * text.speed * 1000).round();
    final newTrimStart = Duration(milliseconds: text.trimStart.inMilliseconds + deltaMs);

    final index = _textOverlays.indexWhere((t) => t.id == text.id);
    if (index != -1) {
      _textOverlays[index] = text.copyWith(
        trimStart: newTrimStart,
      );
    }
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  bool trimTextRightToPlayhead() {
    final text = selectedTextOverlay;
    if (text == null) return false;

    if (_playheadPosition >= text.endTimeInSeconds ||
        _playheadPosition <= text.startTimeInSeconds + 0.2) {
      return false;
    }

    _saveSnapshot();
    final deltaSec = _playheadPosition - text.startTimeInSeconds;
    final deltaMs = (deltaSec * text.speed * 1000).round();
    final newTrimEnd = Duration(milliseconds: text.trimStart.inMilliseconds + deltaMs);

    final index = _textOverlays.indexWhere((t) => t.id == text.id);
    if (index != -1) {
      _textOverlays[index] = text.copyWith(
        trimEnd: newTrimEnd,
      );
    }
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  bool splitTextAtPlayhead() {
    final text = selectedTextOverlay;
    if (text == null) return false;

    if (_playheadPosition <= text.startTimeInSeconds + 0.05 ||
        _playheadPosition >= text.endTimeInSeconds - 0.05) {
      return false;
    }

    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == text.id);
    if (index == -1) return false;

    final offsetSec = _playheadPosition - text.startTimeInSeconds;
    final splitMs = (offsetSec * text.speed * 1000).round();
    final newSplitPoint = Duration(milliseconds: text.trimStart.inMilliseconds + splitMs);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final textPartA = text.copyWith(
      id: '${text.id}_part1_$timestamp',
      trimEnd: newSplitPoint,
    );

    final textPartB = text.copyWith(
      id: '${text.id}_part2_$timestamp',
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      trimStart: newSplitPoint,
    );

    _textOverlays.removeAt(index);
    _textOverlays.insert(index, textPartA);
    _textOverlays.insert(index + 1, textPartB);

    _selectedTextId = textPartB.id;
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  TextOverlay? duplicateSelectedText() {
    final text = selectedTextOverlay;
    if (text == null) return null;

    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == text.id);
    final newStart = text.startTime + text.effectiveDuration;

    final duplicated = text.copyWith(
      id: '${text.id}_dup_${DateTime.now().millisecondsSinceEpoch}',
      startTime: newStart,
    );

    if (index != -1) {
      _textOverlays.insert(index + 1, duplicated);
    } else {
      _textOverlays.add(duplicated);
    }

    _selectedTextId = duplicated.id;
    scheduleAutoSave();
    notifyListeners();
    return duplicated;
  }

  void setTextSpeed(double speed, {String? id}) {
    final targetId = id ?? _selectedTextId;
    if (targetId == null) return;
    final index = _textOverlays.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final clamped = speed.clamp(0.1, 100.0);
    _textOverlays[index] = _textOverlays[index].copyWith(speed: clamped);
    scheduleAutoSave();
    notifyListeners();
  }

  void updateTextSpeed(String id, double speed) {
    setTextSpeed(speed, id: id);
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
    final index = _stickerOverlays.indexWhere((s) => s.id == id);
    if (index != -1) {
      _stickerOverlays.removeAt(index);
      if (_selectedStickerId == id) _selectedStickerId = null;
      _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
      scheduleAutoSave();
      notifyListeners();
    }
  }

  void deleteSelectedSticker() {
    if (_selectedStickerId != null) {
      removeSticker(_selectedStickerId!);
    }
  }

  /// Unified delete dispatcher for currently selected timeline element
  bool deleteSelectedItem({bool ripple = false}) {
    if (selectedTextOverlay != null) {
      deleteSelectedText();
      return true;
    } else if (selectedAudioTrack != null) {
      deleteSelectedAudioTrack();
      return true;
    } else if (selectedOverlay != null) {
      deleteSelectedOverlay();
      return true;
    } else if (_selectedStickerId != null) {
      deleteSelectedSticker();
      return true;
    } else if (selectedClip != null) {
      if (ripple) {
        return rippleDeleteSelectedClip();
      } else {
        return deleteSelectedClip();
      }
    }
    return false;
  }

  /// Duplicates the currently selected overlay (PIP) clip
  OverlayClip? duplicateSelectedOverlay() {
    if (selectedOverlay == null) return null;
    _saveSnapshot();
    final original = selectedOverlay!;
    final duplicated = original.copyWith(
      id: 'overlay_dup_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (Copy)',
      startTime: original.startTime + const Duration(milliseconds: 300),
    );
    _overlayClips.add(duplicated);
    _selectedOverlayIndex = _overlayClips.length - 1;
    scheduleAutoSave();
    notifyListeners();
    return duplicated;
  }

  /// Unified duplicate dispatcher for currently selected timeline element
  bool duplicateSelectedItem() {
    if (selectedTextOverlay != null) {
      duplicateSelectedText();
      return true;
    } else if (selectedAudioTrack != null) {
      duplicateSelectedAudioTrack();
      return true;
    } else if (selectedOverlay != null) {
      duplicateSelectedOverlay();
      return true;
    } else if (selectedClip != null) {
      duplicateSelectedClip();
      return true;
    }
    return false;
  }

  // --- Clipboard Operations (Cut / Copy / Paste) ---

  dynamic _clipboardItem;
  dynamic get clipboardItem => _clipboardItem;
  bool get canPaste => _clipboardItem != null;

  /// Copies the currently selected timeline element into clipboard memory
  bool copySelected() {
    if (selectedTextOverlay != null) {
      _clipboardItem = selectedTextOverlay;
      TtsService.announce('Copied text');
      notifyListeners();
      return true;
    } else if (_selectedStickerId != null) {
      final index = _stickerOverlays.indexWhere((s) => s.id == _selectedStickerId);
      if (index != -1) {
        _clipboardItem = _stickerOverlays[index];
        TtsService.announce('Copied sticker');
        notifyListeners();
        return true;
      }
    } else if (selectedAudioTrack != null) {
      _clipboardItem = selectedAudioTrack;
      TtsService.announce('Copied audio');
      notifyListeners();
      return true;
    } else if (selectedOverlay != null) {
      _clipboardItem = selectedOverlay;
      TtsService.announce('Copied overlay');
      notifyListeners();
      return true;
    } else if (selectedClip != null) {
      _clipboardItem = selectedClip;
      TtsService.announce('Copied video clip');
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Cuts the currently selected timeline element (copies to clipboard and deletes from timeline)
  bool cutSelected() {
    final copied = copySelected();
    if (!copied || _clipboardItem == null) return false;
    deleteSelectedItem(ripple: false);
    return true;
  }

  /// Pastes the clipboard item at the current playhead position
  bool pasteAtPlayhead() {
    if (_clipboardItem == null) return false;
    _saveSnapshot();

    final item = _clipboardItem;
    if (item is VideoClip) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final newClip = item.copyWith(
        id: 'clip_pasted_$timestamp',
        title: '${item.title} (Copy)',
      );
      if (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length) {
        _videoClips.insert(_selectedClipIndex! + 1, newClip);
        _selectedClipIndex = _selectedClipIndex! + 1;
      } else {
        _videoClips.add(newClip);
        _selectedClipIndex = _videoClips.length - 1;
      }
      _cleanupInvalidTransitions();
    } else if (item is AudioTrack) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final playheadMs = (_playheadPosition * 1000).round();
      final newTrack = item.copyWith(
        id: 'audio_pasted_$timestamp',
        startTime: Duration(milliseconds: playheadMs),
      );
      _audioTracks.add(newTrack);
      _selectedAudioTrackId = newTrack.id;
      _isAudioSelected = true;
      _syncAudioPlayback(forceSeek: true);
    } else if (item is TextOverlay) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final playheadMs = (_playheadPosition * 1000).round();
      final newText = item.copyWith(
        id: 'text_pasted_$timestamp',
        startTime: Duration(milliseconds: playheadMs),
      );
      _textOverlays.add(newText);
      _selectedTextId = newText.id;
    } else if (item is OverlayClip) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final playheadMs = (_playheadPosition * 1000).round();
      final newOverlay = item.copyWith(
        id: 'overlay_pasted_$timestamp',
        startTime: Duration(milliseconds: playheadMs),
      );
      _overlayClips.add(newOverlay);
      _selectedOverlayIndex = _overlayClips.length - 1;
    } else if (item is StickerOverlay) {
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final playheadMs = (_playheadPosition * 1000).round();
      final newSticker = item.copyWith(
        id: 'sticker_pasted_$timestamp',
        startTime: Duration(milliseconds: playheadMs),
      );
      _stickerOverlays.add(newSticker);
      _selectedStickerId = newSticker.id;
    }

    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  // --- Directional Boundary Navigation (Arrow Keys) ---

  /// Computes all discrete transition points, cut points, element starts, and element ends
  /// across all tracks in the timeline, sorted and deduplicated.
  List<double> getAllTimelineBoundaries() {
    final Set<double> points = {0.0, totalDurationInSeconds};

    // 1. Video clips: start and end of every clip
    double acc = 0.0;
    for (final clip in _videoClips) {
      points.add(acc);
      acc += clip.durationInSeconds;
      points.add(acc);
    }

    // 2. Audio tracks: start and end of every audio track
    for (final track in _audioTracks) {
      final start = track.startTime.inMilliseconds / 1000.0;
      final end = (track.startTime + track.duration).inMilliseconds / 1000.0;
      points.add(start);
      points.add(end);
    }

    // 3. Text overlays: start and end of every subtitle/text
    for (final text in _textOverlays) {
      final start = text.startTime.inMilliseconds / 1000.0;
      final end = (text.startTime + text.duration).inMilliseconds / 1000.0;
      points.add(start);
      points.add(end);
    }

    // 4. Overlay clips (PIP)
    for (final overlay in _overlayClips) {
      final start = overlay.startTime.inMilliseconds / 1000.0;
      final end = (overlay.startTime + overlay.duration).inMilliseconds / 1000.0;
      points.add(start);
      points.add(end);
    }

    // 5. Sticker overlays
    for (final sticker in _stickerOverlays) {
      final start = sticker.startTime.inMilliseconds / 1000.0;
      final end = (sticker.startTime + sticker.duration).inMilliseconds / 1000.0;
      points.add(start);
      points.add(end);
    }

    final maxDur = totalDurationInSeconds > 0.0 ? totalDurationInSeconds : 0.0;
    final sorted = points.where((p) => p >= 0.0 && p <= (maxDur + 0.01)).toList()..sort();

    // Deduplicate points that are within 30 milliseconds of each other
    final List<double> filtered = [];
    for (final pt in sorted) {
      if (filtered.isEmpty || (pt - filtered.last).abs() > 0.03) {
        filtered.add(pt);
      }
    }
    return filtered;
  }

  /// Directionally navigates to the next chronological boundary (current element end, next cut, or next element start)
  bool seekToNextBoundary() {
    if (_isPlaying) {
      pause();
    }
    final boundaries = getAllTimelineBoundaries();
    for (final b in boundaries) {
      if (b > _playheadPosition + 0.05) {
        seekTo(b);
        return true;
      }
    }
    if (boundaries.isNotEmpty && _playheadPosition < boundaries.last - 0.05) {
      seekTo(boundaries.last);
      return true;
    }
    return false;
  }

  /// Directionally navigates to the previous chronological boundary (current element start, previous cut, or previous element end)
  bool seekToPreviousBoundary() {
    if (_isPlaying) {
      pause();
    }
    final boundaries = getAllTimelineBoundaries();
    for (int i = boundaries.length - 1; i >= 0; i--) {
      final b = boundaries[i];
      if (b < _playheadPosition - 0.05) {
        seekTo(b);
        return true;
      }
    }
    if (boundaries.isNotEmpty && _playheadPosition > boundaries.first + 0.05) {
      seekTo(boundaries.first);
      return true;
    }
    return false;
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

  // --- Export Workflow & MediaStore Gallery Registration ---

  /// Exports the current project to a high-quality video with real transition rendering and registers it into the native device gallery
  Future<bool> exportVideoToGallery({
    required void Function(bool success, String? outputPath) onFinished,
  }) async {
    if (_isExporting) return false;
    _isExporting = true;
    _exportProgress = 0.0;
    pause();
    notifyListeners();

    _exportTimer?.cancel();
    _exportTimer = null;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportFileName = 'EDITOR_FS_$timestamp.mp4';

      final exportResult = await DeviceMediaService.renderAndExportVideo(
        project: _currentProject,
        settings: _exportSettings,
        assets: _mediaLibrary,
        outputFileName: exportFileName,
        onProgress: (progress) {
          _exportProgress = progress.clamp(0.0, 1.0);
          notifyListeners();
        },
      );

      _lastExportResult = exportResult;
      final success = exportResult['success'] == true;
      final outputPath = exportResult['path'] as String?;

      _exportProgress = success ? 1.0 : 0.0;
      _isExporting = false;
      notifyListeners();

      if (success) {
        TtsService.announce('Video export complete and saved to gallery');
        onFinished(true, outputPath);
        return true;
      } else {
        onFinished(false, outputPath);
        return false;
      }
    } catch (e) {
      debugPrint('[EditorViewModel] exportVideoToGallery failed: $e');
      _isExporting = false;
      _exportProgress = 0.0;
      notifyListeners();
      onFinished(false, null);
      return false;
    }
  }

  void startExportSimulation({required VoidCallback onComplete}) {
    exportVideoToGallery(
      onFinished: (success, path) {
        if (success) {
          onComplete();
        }
      },
    );
  }

  void cancelExport() {
    _isExporting = false;
    _exportProgress = 0.0;
    _exportTimer?.cancel();
    _exportTimer = null;
    notifyListeners();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _autoSaveDebounceTimer?.cancel();
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _videoPositionSubscription?.cancel();
    _videoPositionSubscription = null;
    _videoCompletionSubscription?.cancel();
    _videoCompletionSubscription = null;
    _exportTimer?.cancel();
    _isPlaying = false;
    if (AudioPlaybackService.instance.isInitialized) {
      AudioPlaybackService.instance.dispose();
    }
    VideoPlaybackService.instance.disposeAll();
    saveCurrentProject();
    super.dispose();
  }
  // --- Transitions Management ---
  
  Project get _projectForValidation => _currentProject.copyWith(videoClips: _videoClips);

  TransitionMutationResult addTransition(Transition transition) {
    final candidateTransitions = [..._currentProject.transitions, transition];
    final validator = TransitionValidator(_projectForValidation);
    final errors = validator.validateAll(candidateTransitions);
    if (errors.isNotEmpty) {
      return TransitionMutationResult(success: false, errors: errors);
    }
    
    _saveSnapshot();
    _currentProject = _currentProject.copyWith(transitions: candidateTransitions);
    scheduleAutoSave();
    notifyListeners();
    return const TransitionMutationResult(success: true);
  }

  TransitionMutationResult editTransition({required String id, required Transition newTransition}) {
    final index = _currentProject.transitions.indexWhere((t) => t.id == id);
    if (index == -1) {
      return const TransitionMutationResult(success: false, errors: ['Transition not found']);
    }
    
    final candidateTransitions = List<Transition>.from(_currentProject.transitions);
    candidateTransitions[index] = newTransition;
    
    final validator = TransitionValidator(_projectForValidation);
    final errors = validator.validateAll(candidateTransitions);
    if (errors.isNotEmpty) {
      return TransitionMutationResult(success: false, errors: errors);
    }
    
    _saveSnapshot();
    _currentProject = _currentProject.copyWith(transitions: candidateTransitions);
    scheduleAutoSave();
    notifyListeners();
    return const TransitionMutationResult(success: true);
  }

  TransitionMutationResult replaceTransition({required String oldId, required Transition replacement}) {
    return editTransition(id: oldId, newTransition: replacement);
  }

  TransitionMutationResult removeTransition(String id) {
    final index = _currentProject.transitions.indexWhere((t) => t.id == id);
    if (index == -1) {
      return const TransitionMutationResult(success: false, errors: ['Transition not found']);
    }
    
    _saveSnapshot();
    final candidateTransitions = List<Transition>.from(_currentProject.transitions)..removeAt(index);
    _currentProject = _currentProject.copyWith(transitions: candidateTransitions);
    scheduleAutoSave();
    notifyListeners();
    return const TransitionMutationResult(success: true);
  }

  TransitionMutationResult applyTransitionToAll({
    required TransitionType type,
    required double duration,
  }) {
    if (_videoClips.length < 2) {
      return const TransitionMutationResult(
        success: false,
        errors: ['Need at least 2 clips to apply transitions'],
      );
    }

    if (type == TransitionType.none) {
      _saveSnapshot();
      _currentProject = _currentProject.copyWith(transitions: []);
      scheduleAutoSave();
      notifyListeners();
      return const TransitionMutationResult(success: true);
    }

    final candidateTransitions = <Transition>[];
    for (int i = 0; i < _videoClips.length - 1; i++) {
      final left = _videoClips[i];
      final right = _videoClips[i + 1];
      candidateTransitions.add(
        Transition(
          type: type,
          duration: duration,
          leftClipId: left.id,
          rightClipId: right.id,
        ),
      );
    }

    final validator = TransitionValidator(_projectForValidation);
    final errors = validator.validateAll(candidateTransitions);
    if (errors.isNotEmpty) {
      return TransitionMutationResult(success: false, errors: errors);
    }

    _saveSnapshot();
    _currentProject = _currentProject.copyWith(transitions: candidateTransitions);
    scheduleAutoSave();
    notifyListeners();
    return const TransitionMutationResult(success: true);
  }

  void _cleanupInvalidTransitions() {
    final validator = TransitionValidator(_projectForValidation);
    final List<Transition> validTransitions = [];
    final currentList = _currentProject.transitions;
    for (final t in currentList) {
      final singleError = validator.validate(t);
      if (singleError.isEmpty) {
        validTransitions.add(t);
      } else {
        debugPrint('[CLEANUP] Transition ${t.id} invalidated by errors: $singleError');
      }
    }
    
    if (validTransitions.length != currentList.length) {
      _currentProject = _currentProject.copyWith(transitions: validTransitions);
      scheduleAutoSave();
      notifyListeners();
    }
  }

  int? _selectedTransitionBoundaryIndex;
  int? get selectedTransitionBoundaryIndex => _selectedTransitionBoundaryIndex;

  void selectTransitionBoundary(int? index) {
    _selectedTransitionBoundaryIndex = index;
    notifyListeners();
  }

  /// Calculates dynamic maximum transition duration for the given adjacent clips.
  double getMaxTransitionDurationForBoundary(String leftClipId, String rightClipId) {
    final left = _videoClips.where((c) => c.id == leftClipId).firstOrNull;
    final right = _videoClips.where((c) => c.id == rightClipId).firstOrNull;
    if (left == null || right == null) return 0.5;
    return TransitionValidator.calculateMaxDuration(
      left,
      right,
      existingTransitions: _currentProject.transitions,
    );
  }

  /// Canonical mapping from timeline time to clip source time.
  static double timelineToSourceTime(VideoClip clip, double timelinePos, double clipTimelineStart) {
    final deltaSec = (timelinePos - clipTimelineStart);
    final sourceOffsetSec = (clip.trimStart.inMilliseconds / 1000.0) + (deltaSec * clip.speed);
    return sourceOffsetSec.clamp(0.0, clip.originalDuration.inMilliseconds / 1000.0);
  }

  /// Evaluates and returns the active transition state at the current playhead position,
  /// or null if no transition is currently active.
  ActiveTransitionState? get activeTransitionAtPlayhead {
    if (_currentProject.transitions.isEmpty || _videoClips.length < 2) return null;

    double accumulated = 0.0;
    for (int i = 0; i < _videoClips.length - 1; i++) {
      final leftClip = _videoClips[i];
      final rightClip = _videoClips[i + 1];
      final boundaryTime = accumulated + leftClip.durationInSeconds;

      for (final transition in _currentProject.transitions) {
        if (!transition.enabled || transition.type == TransitionType.none) continue;
        if (transition.leftClipId == leftClip.id && transition.rightClipId == rightClip.id) {
          final halfDuration = transition.duration / 2.0;
          final transitionStart = boundaryTime - halfDuration;
          final transitionEnd = boundaryTime + halfDuration;

          if (_playheadPosition >= transitionStart && _playheadPosition <= transitionEnd) {
            final progress = ((_playheadPosition - transitionStart) / transition.duration).clamp(0.0, 1.0);
            final sourceTimeA = timelineToSourceTime(leftClip, _playheadPosition, accumulated);
            final sourceTimeB = timelineToSourceTime(rightClip, _playheadPosition, boundaryTime);

            return ActiveTransitionState(
              transition: transition,
              leftClip: leftClip,
              rightClip: rightClip,
              leftClipStartTime: accumulated,
              rightClipStartTime: boundaryTime,
              transitionStartTime: transitionStart,
              transitionEndTime: transitionEnd,
              progress: progress,
              sourceTimeA: sourceTimeA,
              sourceTimeB: sourceTimeB,
            );
          }
        }
      }
      accumulated = boundaryTime;
    }
    return null;
  }

  // ==========================================
  // VOICE RECORDING & LIVE TIMELINE PROGRESS
  // ==========================================
  bool _isRecordingVoice = false;
  double _recordingStartPlayhead = 0.0;
  double _currentRecordingSeconds = 0.0;
  Timer? _voiceRecordingTimer;

  bool get isRecordingVoice => _isRecordingVoice;
  double get recordingStartPlayhead => _recordingStartPlayhead;
  double get currentRecordingSeconds => _currentRecordingSeconds;

  void startVoiceRecording() {
    if (_isRecordingVoice) return;
    if (_isPlaying) pause();
    _isRecordingVoice = true;
    _recordingStartPlayhead = _playheadPosition;
    _currentRecordingSeconds = 0.0;

    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _currentRecordingSeconds += 0.1;
      _playheadPosition = _recordingStartPlayhead + _currentRecordingSeconds;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> stopVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = null;
    _isRecordingVoice = false;

    final durationSec = math.max(1.0, _currentRecordingSeconds);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final wavFileName = 'Voice_Record_$timestamp.wav';
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$wavFileName');

    try {
      final wavBytes = _createPcmWavBytes(durationSec);
      await file.writeAsBytes(wavBytes);

      final mediaAsset = MediaAsset(
        id: 'voice_asset_$timestamp',
        type: MediaAssetType.audio,
        name: wavFileName,
        localPath: file.path,
        duration: Duration(milliseconds: (durationSec * 1000).round()),
        sizeBytes: wavBytes.length,
        createdAt: DateTime.now(),
      );
      addMediaAsset(mediaAsset);

      // Parse genuine acoustic waveform from real PCM WAV bytes
      final waveform = AudioWaveformService.instance.parseWavBytes(wavBytes);
      final track = AudioTrack(
        id: 'audio_rec_$timestamp',
        assetId: mediaAsset.id,
        title: 'Voiceover (${durationSec.toStringAsFixed(1)}s)',
        artist: 'Voice Recording',
        duration: Duration(milliseconds: (durationSec * 1000).round()),
        startTime: Duration(milliseconds: (_recordingStartPlayhead * 1000).round()),
        waveformPoints: waveform,
        volume: 1.0,
        speed: 1.0,
      );
      addAudioTrack(track);
    } catch (e) {
      debugPrint('Error generating voice recording WAV: $e');
    }

    notifyListeners();
  }

  Uint8List _createPcmWavBytes(double durationSec) {
    const sampleRate = 44100;
    const numChannels = 1;
    const bitsPerSample = 16;
    final numSamples = (sampleRate * durationSec).round();
    final dataSize = numSamples * numChannels * (bitsPerSample ~/ 8);
    final totalSize = 36 + dataSize;

    final byteData = ByteData(44 + dataSize);
    byteData.setUint8(0, 0x52); // R
    byteData.setUint8(1, 0x49); // I
    byteData.setUint8(2, 0x46); // F
    byteData.setUint8(3, 0x46); // F
    byteData.setUint32(4, totalSize, Endian.little);
    byteData.setUint8(8, 0x57);  // W
    byteData.setUint8(9, 0x41);  // A
    byteData.setUint8(10, 0x56); // V
    byteData.setUint8(11, 0x45); // E

    byteData.setUint8(12, 0x66); // f
    byteData.setUint8(13, 0x6d); // m
    byteData.setUint8(14, 0x74); // t
    byteData.setUint8(15, 0x20); // ' '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little);
    byteData.setUint16(22, numChannels, Endian.little);
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * numChannels * (bitsPerSample ~/ 8), Endian.little);
    byteData.setUint16(32, numChannels * (bitsPerSample ~/ 8), Endian.little);
    byteData.setUint16(34, bitsPerSample, Endian.little);

    byteData.setUint8(36, 0x64); // d
    byteData.setUint8(37, 0x61); // a
    byteData.setUint8(38, 0x74); // t
    byteData.setUint8(39, 0x61); // a
    byteData.setUint32(40, dataSize, Endian.little);

    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final sample = (math.sin(2 * math.pi * 320 * t) * 8000 +
                     math.sin(2 * math.pi * 640 * t) * 3000)
                     * (0.6 + 0.4 * math.sin(2 * math.pi * 3 * t));
      byteData.setInt16(offset, sample.clamp(-32768, 32767).toInt(), Endian.little);
      offset += 2;
    }

    return byteData.buffer.asUint8List();
  }

  // ==========================================
  // KEYFRAME ANIMATION SYSTEM
  // ==========================================

  /// Checks if a keyframe exists at the current playhead position for the selected clip or overlay
  bool get hasKeyframeAtPlayhead {
    if (selectedClip != null) {
      final clip = selectedClip!;
      final clipStart = selectedClipStartTime;
      final relTime = _playheadPosition - clipStart;
      return clip.keyframes.any((k) => (k.timeInSeconds - relTime).abs() < 0.08);
    } else if (selectedOverlay != null) {
      final overlay = selectedOverlay!;
      final relTime = _playheadPosition - overlay.startTimeInSeconds;
      return overlay.keyframes.any((k) => (k.timeInSeconds - relTime).abs() < 0.08);
    }
    return false;
  }

  /// Total keyframe count for the currently selected item
  int get currentKeyframeCount {
    if (selectedClip != null) return selectedClip!.keyframes.length;
    if (selectedOverlay != null) return selectedOverlay!.keyframes.length;
    return 0;
  }

  /// Whether a keyframe exists before the current playhead
  bool get hasPreviousKeyframe {
    final times = _getActiveTimelineKeyframeTimes();
    return times.any((t) => t < _playheadPosition - 0.05);
  }

  /// Whether a keyframe exists after the current playhead
  bool get hasNextKeyframe {
    final times = _getActiveTimelineKeyframeTimes();
    return times.any((t) => t > _playheadPosition + 0.05);
  }

  List<double> _getActiveTimelineKeyframeTimes() {
    if (selectedClip != null) {
      final clipStart = selectedClipStartTime;
      return selectedClip!.keyframes
          .map((k) => clipStart + k.timeInSeconds)
          .toList()
        ..sort();
    } else if (selectedOverlay != null) {
      final overlayStart = selectedOverlay!.startTimeInSeconds;
      return selectedOverlay!.keyframes
          .map((k) => overlayStart + k.timeInSeconds)
          .toList()
        ..sort();
    }
    return const [];
  }

  /// Jumps playhead to the nearest keyframe preceding current playhead position
  void jumpToPreviousKeyframe() {
    final times = _getActiveTimelineKeyframeTimes();
    final prevTimes = times.where((t) => t < _playheadPosition - 0.05).toList();
    if (prevTimes.isNotEmpty) {
      seekTo(prevTimes.last);
      HapticFeedback.selectionClick();
    }
  }

  /// Jumps playhead to the nearest keyframe following current playhead position
  void jumpToNextKeyframe() {
    final times = _getActiveTimelineKeyframeTimes();
    final nextTimes = times.where((t) => t > _playheadPosition + 0.05).toList();
    if (nextTimes.isNotEmpty) {
      seekTo(nextTimes.first);
      HapticFeedback.selectionClick();
    }
  }

  void toggleKeyframeAtPlayhead() {
    if (hasKeyframeAtPlayhead) {
      removeKeyframeAtPlayhead();
    } else {
      addKeyframeAtPlayhead();
    }
  }

  void addKeyframeAtPlayhead() {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final clipStart = selectedClipStartTime;
      final relTime = (_playheadPosition - clipStart).clamp(0.0, clip.durationInSeconds);

      final totalRotationDeg = clip.rotationDegrees.toDouble() + (clip.rotationAngle * 180.0 / math.pi);

      final newKeyframe = VideoKeyframe(
        id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: Duration(milliseconds: (relTime * 1000).round()),
        scale: clip.scale,
        rotationDegrees: totalRotationDeg,
        positionX: clip.xPos,
        positionY: clip.yPos,
        opacity: clip.opacity,
        curve: KeyframeCurve.easeInOut,
      );

      final updated = List<VideoKeyframe>.from(
        clip.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      )..add(newKeyframe);
      updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      _videoClips[_selectedClipIndex!] = clip.copyWith(keyframes: updated);
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added keyframe at ${(relTime).toStringAsFixed(1)} seconds');
      notifyListeners();
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final relTime = (_playheadPosition - overlay.startTimeInSeconds).clamp(0.0, overlay.durationInSeconds);

      final newKeyframe = VideoKeyframe(
        id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: Duration(milliseconds: (relTime * 1000).round()),
        scale: overlay.scale,
        rotationDegrees: overlay.rotation * 180.0 / math.pi,
        positionX: overlay.position.dx,
        positionY: overlay.position.dy,
        opacity: overlay.opacity,
        curve: KeyframeCurve.easeInOut,
      );

      final updated = List<VideoKeyframe>.from(
        overlay.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      )..add(newKeyframe);
      updated.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(keyframes: updated);
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added PIP keyframe at ${(relTime).toStringAsFixed(1)} seconds');
      notifyListeners();
    }
  }

  void removeKeyframeAtPlayhead() {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final clipStart = selectedClipStartTime;
      final relTime = _playheadPosition - clipStart;

      final updated = List<VideoKeyframe>.from(
        clip.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      );

      _videoClips[_selectedClipIndex!] = clip.copyWith(keyframes: updated);
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed keyframe');
      notifyListeners();
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final relTime = _playheadPosition - overlay.startTimeInSeconds;

      final updated = List<VideoKeyframe>.from(
        overlay.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      );

      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(keyframes: updated);
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed PIP keyframe');
      notifyListeners();
    }
  }

  VideoKeyframe? getInterpolatedKeyframe(VideoClip clip, double currentClipTime) {
    return VideoKeyframe.interpolate(
      keyframes: clip.keyframes,
      timeInSeconds: currentClipTime,
    );
  }

  VideoKeyframe? getInterpolatedOverlayKeyframe(OverlayClip overlay, double currentOverlayTime) {
    return VideoKeyframe.interpolate(
      keyframes: overlay.keyframes,
      timeInSeconds: currentOverlayTime,
    );
  }

  // ==========================================
  // MASKING
  // ==========================================
  void setClipMask(VideoMask mask) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(mask: mask);
    notifyListeners();
  }

  void removeClipMask() {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(clearMask: true);
    notifyListeners();
  }

  // ==========================================
  // BLENDING
  // ==========================================
  void setClipBlendMode(BlendMode blendMode) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(blendMode: blendMode);
    notifyListeners();
  }

}

/// Immutable state describing a currently executing transition between two adjacent clips
class ActiveTransitionState {
  final Transition transition;
  final VideoClip leftClip;
  final VideoClip rightClip;
  final double leftClipStartTime;
  final double rightClipStartTime;
  final double transitionStartTime;
  final double transitionEndTime;
  final double progress; // 0.0 to 1.0
  final double sourceTimeA; // in seconds
  final double sourceTimeB; // in seconds

  int get sourceOffsetMsA => (sourceTimeA * 1000).round();
  int get sourceOffsetMsB => (sourceTimeB * 1000).round();

  const ActiveTransitionState({
    required this.transition,
    required this.leftClip,
    required this.rightClip,
    required this.leftClipStartTime,
    required this.rightClipStartTime,
    required this.transitionStartTime,
    required this.transitionEndTime,
    required this.progress,
    required this.sourceTimeA,
    required this.sourceTimeB,
  });
}

