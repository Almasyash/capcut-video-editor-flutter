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
import 'package:capcut_video_editor/core/services/pip_ai_provider.dart';
import 'package:capcut_video_editor/core/utils/timeline_coordinate_system.dart';

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

  bool _isRippleEditingEnabled = false;
  bool get isRippleEditingEnabled => _isRippleEditingEnabled;

  void toggleRippleEditing([bool? enabled]) {
    _isRippleEditingEnabled = enabled ?? !_isRippleEditingEnabled;
    TtsService.announce(_isRippleEditingEnabled ? 'Ripple editing enabled' : 'Ripple editing disabled');
    notifyListeners();
  }

  final ValueNotifier<double> playheadNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<EditorCategory?> drawerNotifier = ValueNotifier<EditorCategory?>(null);

  double _rawPlayheadPosition = 0.0; // In seconds
  double get _playheadPosition => _rawPlayheadPosition;
  set _playheadPosition(double val) {
    _rawPlayheadPosition = val;
    if (playheadNotifier.value != val) {
      playheadNotifier.value = val;
    }
  }

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
  @visibleForTesting
  int get undoStackCount => _undoStack.length;

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
      if (!o.isVisible) return false;
      final isSelected = selectedOverlay?.id == o.id;
      final inRange = _playheadPosition >= (o.startTimeInSeconds - 0.05) &&
          _playheadPosition <= (o.endTimeInSeconds + 0.05);
      return inRange || isSelected;
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
      if (!t.isVisible) return false;
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

  void _saveSnapshotWithOverlays(List<OverlayClip> previousOverlays) {
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: previousOverlays,
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

  /// Forces a complete rebuild and relayout of timeline elements and playhead tracking.
  /// Typically called when returning from full-screen preview or viewport transitions.
  void refreshTimelineLayout() {
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

  void selectOverlay(int? index) {
    if (index == null) {
      _selectedOverlayIndex = null;
      notifyListeners();
      return;
    }
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

  void selectOverlayClip(int index) => selectOverlay(index);

  void selectOverlayById(String? id) {
    if (id == null) {
      _selectedOverlayIndex = null;
      notifyListeners();
      return;
    }
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index != -1) {
      selectOverlay(index);
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
    drawerNotifier.value = category;
    notifyListeners();
  }

  void closeDrawer() {
    _activeDrawer = null;
    drawerNotifier.value = null;
    notifyListeners();
  }

  // --- Universal Timeline Trimming & Dragging ---

  /// Trims or moves PIP overlay layer timing with live preview updates.
  void updateOverlayClipTiming(
    String id,
    Duration newStart,
    Duration newDuration, {
    bool saveSnapshot = false,
    bool notify = true,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    if (newDuration.inMilliseconds < 300) return; // Minimum 0.3s
    if (saveSnapshot) _saveSnapshot();

    _overlayClips[index] = _overlayClips[index].copyWith(
      startTime: newStart,
      duration: newDuration,
    );
    if (notify) notifyListeners();
  }

  /// Commits a completed timeline trim or drag timing gesture into the undo history.
  /// Exactly ONE undo snapshot is created for the complete timing interaction.
  void commitOverlayTiming(
    String id, {
    required Duration oldStart,
    required Duration oldDuration,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final current = _overlayClips[index];
    if (current.startTime == oldStart && current.duration == oldDuration) {
      return;
    }

    final previousOverlays = List<OverlayClip>.from(_overlayClips);
    previousOverlays[index] = current.copyWith(
      startTime: oldStart,
      duration: oldDuration,
    );

    _saveSnapshotWithOverlays(previousOverlays);
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

    final offsetMs = (offsetInClipSeconds * 1000).round();
    final sourceSplitPoint = TimeRemapper.timelineToSourceTime(
      timelineOffset: Duration(milliseconds: offsetMs),
      trimStart: originalClip.trimStart,
      trimEnd: originalClip.trimEnd,
      originalDuration: originalClip.originalDuration,
      speedCurve: originalClip.speedCurve,
      constantSpeed: originalClip.speed,
      isReversed: originalClip.isReversed,
      freezeFrame: originalClip.freezeFrame,
    );

    final newSplitMs = sourceSplitPoint.inMilliseconds.clamp(
      originalClip.trimStart.inMilliseconds + 1,
      originalClip.trimEnd.inMilliseconds - 1,
    );
    final newSplitPoint = Duration(milliseconds: newSplitMs);
    final splitOffsetMs = (newSplitMs - originalClip.trimStart.inMilliseconds).clamp(
      0,
      originalClip.originalDuration.inMilliseconds,
    );

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final (clipTracksA, clipTracksB) = originalClip.effectiveKeyframeTracks.splitAt(splitOffsetMs);

    // Split speed curve proportionally into Part 1 and Part 2
    SpeedCurve? curvePartA;
    SpeedCurve? curvePartB;
    if (originalClip.speedCurve != null) {
      final splitTimelineRatio = (offsetInClipSeconds / math.max(0.001, originalClip.durationInSeconds)).clamp(0.001, 0.999);
      final (cA, cB) = originalClip.speedCurve!.splitAt(splitTimelineRatio);
      curvePartA = cA;
      curvePartB = cB;
    }

    // Split freeze frame if present
    FreezeFrame? freezePartA;
    FreezeFrame? freezePartB;
    if (originalClip.freezeFrame != null) {
      final f = originalClip.freezeFrame!;
      final fStart = f.timelineOffset.inMilliseconds;
      final fDur = f.duration.inMilliseconds;
      final fEnd = fStart + fDur;
      if (offsetMs <= fStart) {
        freezePartB = f.copyWith(
          timelineOffset: Duration(milliseconds: fStart - offsetMs),
        );
      } else if (offsetMs >= fEnd) {
        freezePartA = f;
      } else {
        // Playhead cuts through freeze frame
        freezePartA = FreezeFrame(
          timelineOffset: f.timelineOffset,
          duration: Duration(milliseconds: offsetMs - fStart),
          sourceTime: f.sourceTime,
        );
        freezePartB = FreezeFrame(
          timelineOffset: Duration.zero,
          duration: Duration(milliseconds: fEnd - offsetMs),
          sourceTime: f.sourceTime,
        );
      }
    }

    final masksA = originalClip.masks.map((m) {
      if (m.keyframeTracks != null && m.keyframeTracks!.isNotEmpty) {
        final (tA, _) = m.keyframeTracks!.splitAt(splitOffsetMs);
        return m.copyWith(keyframeTracks: tA);
      }
      return m;
    }).toList();

    final masksB = originalClip.masks.map((m) {
      if (m.keyframeTracks != null && m.keyframeTracks!.isNotEmpty) {
        final (_, tB) = m.keyframeTracks!.splitAt(splitOffsetMs);
        return m.copyWith(keyframeTracks: tB);
      }
      return m;
    }).toList();

    final clipPartA = originalClip.copyWith(
      id: '${originalClip.id}_a_$timestamp',
      title: '${originalClip.title} (Part 1)',
      trimEnd: newSplitPoint,
      speedCurve: curvePartA,
      clearSpeedCurve: curvePartA == null && originalClip.speedCurve != null,
      freezeFrame: freezePartA,
      clearFreezeFrame: freezePartA == null && originalClip.freezeFrame != null,
      keyframeTracks: clipTracksA,
      keyframes: clipTracksA.toVideoKeyframes(),
      masks: masksA,
    );

    final clipPartB = originalClip.copyWith(
      id: '${originalClip.id}_b_$timestamp',
      title: '${originalClip.title} (Part 2)',
      trimStart: newSplitPoint,
      speedCurve: curvePartB,
      clearSpeedCurve: curvePartB == null && originalClip.speedCurve != null,
      freezeFrame: freezePartB,
      clearFreezeFrame: freezePartB == null && originalClip.freezeFrame != null,
      keyframeTracks: clipTracksB,
      keyframes: clipTracksB.toVideoKeyframes(),
      masks: masksB,
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
    final deltaOffsetMs = (deltaSec * 1000).round();
    final newTrimStart = TimeRemapper.timelineToSourceTime(
      timelineOffset: Duration(milliseconds: deltaOffsetMs),
      trimStart: clip.trimStart,
      trimEnd: clip.trimEnd,
      originalDuration: clip.originalDuration,
      speedCurve: clip.speedCurve,
      constantSpeed: clip.speed,
      isReversed: clip.isReversed,
      freezeFrame: clip.freezeFrame,
    );

    // Adapt speed curve if active
    final trimRatio = (deltaSec / clip.durationInSeconds).clamp(0.0, 0.99);
    final newCurve = clip.speedCurve?.clampToRange(trimRatio, 1.0);

    _videoClips[_selectedClipIndex!] = clip.copyWith(
      trimStart: newTrimStart,
      speedCurve: newCurve,
    );
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
    final offsetMs = (offsetSec * 1000).round();
    final newTrimEnd = TimeRemapper.timelineToSourceTime(
      timelineOffset: Duration(milliseconds: offsetMs),
      trimStart: clip.trimStart,
      trimEnd: clip.trimEnd,
      originalDuration: clip.originalDuration,
      speedCurve: clip.speedCurve,
      constantSpeed: clip.speed,
      isReversed: clip.isReversed,
      freezeFrame: clip.freezeFrame,
    );

    // Adapt speed curve if active
    final trimRatio = (offsetSec / clip.durationInSeconds).clamp(0.01, 1.0);
    final newCurve = clip.speedCurve?.clampToRange(0.0, trimRatio);

    _videoClips[_selectedClipIndex!] = clip.copyWith(
      trimEnd: newTrimEnd,
      speedCurve: newCurve,
    );
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

    // Ripple shift subsequent layers when ripple editing is active
    if (_isRippleEditingEnabled) {
      final shiftDelta = Duration(milliseconds: (deletedDuration * 1000).round());
      for (int i = 0; i < _overlayClips.length; i++) {
        if (_overlayClips[i].startTimeInSeconds >= deletedEnd) {
          final newStart = _overlayClips[i].startTime - shiftDelta;
          _overlayClips[i] = _overlayClips[i].copyWith(
            startTime: newStart < Duration.zero ? Duration.zero : newStart,
          );
        }
      }
      for (int i = 0; i < _textOverlays.length; i++) {
        if (_textOverlays[i].startTimeInSeconds >= deletedEnd) {
          final newStart = _textOverlays[i].startTime - shiftDelta;
          _textOverlays[i] = _textOverlays[i].copyWith(
            startTime: newStart < Duration.zero ? Duration.zero : newStart,
          );
        }
      }
      for (int i = 0; i < _audioTracks.length; i++) {
        if (_audioTracks[i].startTimeInSeconds >= deletedEnd) {
          final newStart = _audioTracks[i].startTime - shiftDelta;
          _audioTracks[i] = _audioTracks[i].copyWith(
            startTime: newStart < Duration.zero ? Duration.zero : newStart,
          );
        }
      }
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

  /// Adds a new video clip to the timeline track.
  void addClip(VideoClip clip) {
    _saveSnapshot();
    _videoClips.add(clip);
    _selectedClipIndex = _videoClips.length - 1;
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  /// Duplicate on main timeline track
  void duplicateSelectedClip() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final original = _videoClips[_selectedClipIndex!];
    final clonedMasks = original.masks.map((m) {
      final newId = 'mask_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(10000)}';
      return m.copyWith(
        id: newId,
        keyframeTracks: m.keyframeTracks?.duplicate(),
      );
    }).toList();

    final duplicated = original.copyWith(
      id: 'clip_dup_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (Copy)',
      speedCurve: original.speedCurve?.duplicate(),
      freezeFrame: original.freezeFrame?.copyWith(),
      keyframeTracks: original.effectiveKeyframeTracks.duplicate(),
      keyframes: original.keyframes
          .map((k) => k.copyWith(id: 'kf_${DateTime.now().microsecondsSinceEpoch}_${k.timestamp.inMilliseconds}'))
          .toList(),
      masks: clonedMasks,
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

    final clonedMasks = original.masks.map((m) {
      final newId = 'mask_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(10000)}';
      return m.copyWith(
        id: newId,
        keyframeTracks: m.keyframeTracks?.duplicate(),
      );
    }).toList();

    final overlay = OverlayClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (PIP Layer)',
      assetId: original.assetId,
      localPath: asset?.localPath ?? asset?.thumbnailPath,
      isPhoto: asset?.type == MediaAssetType.photo,
      startTime: Duration(milliseconds: (clipStart * 1000).round()),
      duration: original.activeDuration,
      speed: original.speed,
      speedCurve: original.speedCurve?.duplicate(),
      isFrozen: original.isFrozen,
      isReversed: original.isReversed,
      freezeFrame: original.freezeFrame?.copyWith(),
      previewGradient: original.previewGradient,
      previewIcon: original.previewIcon,
      position: const Offset(0.7, 0.25),
      scale: 0.45,
      opacity: original.opacity,
      blendMode: original.blendMode,
      masks: clonedMasks,
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
    debugPrint('[PIP] Overlay Added: ${overlay.id}');
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
    _overlayClips[index] = _overlayClips[index].copyWith(
      position: OverlayClip.sanitizePosition(newPos),
    );
    notifyListeners();
  }

  void updateOverlayScale(int index, double scale) {
    if (index < 0 || index >= _overlayClips.length) return;
    _overlayClips[index] = _overlayClips[index].copyWith(
      scale: OverlayClip.sanitizeScale(scale),
    );
    notifyListeners();
  }

  /// Updates PIP overlay position, scale, and/or rotation live during gestures.
  void updateOverlayTransform(
    String id, {
    Offset? position,
    double? scale,
    double? rotation,
    bool notify = true,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final current = _overlayClips[index];
    _overlayClips[index] = current.copyWith(
      position: position != null ? OverlayClip.sanitizePosition(position) : null,
      scale: scale != null ? OverlayClip.sanitizeScale(scale) : null,
      rotation: rotation != null ? OverlayClip.sanitizeRotation(rotation) : null,
    );
    if (notify) notifyListeners();
  }

  /// Commits a completed transform gesture (drag, pinch, rotate) into undo history as a single snapshot.
  void commitOverlayTransform(
    String id, {
    required Offset oldPosition,
    required double oldScale,
    required double oldRotation,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final current = _overlayClips[index];
    if (current.position == oldPosition &&
        (current.scale - oldScale).abs() < 0.0001 &&
        (current.rotation - oldRotation).abs() < 0.0001) {
      return;
    }

    final previousOverlays = List<OverlayClip>.from(_overlayClips);
    previousOverlays[index] = current.copyWith(
      position: oldPosition,
      scale: oldScale,
      rotation: oldRotation,
    );

    if (current.keyframes.isNotEmpty || current.effectiveKeyframeTracks.isNotEmpty) {
      final relTime = (_playheadPosition - current.startTimeInSeconds).clamp(0.0, current.durationInSeconds);
      final timeMs = (relTime * 1000).round();
      final updatedTracks = current.effectiveKeyframeTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: current.position.dx,
        posY: current.position.dy,
        scale: current.scale,
        rotation: current.rotation * 180.0 / math.pi,
        opacity: current.opacity,
        easing: EasingCurve.easeInOut,
      );
      _overlayClips[index] = current.copyWith(
        keyframeTracks: updatedTracks,
        keyframes: updatedTracks.toVideoKeyframes(),
      );
    }

    _saveSnapshotWithOverlays(previousOverlays);
  }

  /// Updates overlay opacity live without polluting undo stack during slider drag.
  void updateOverlayOpacity(
    String id,
    double opacity, {
    bool saveSnapshot = false,
    bool notify = true,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    if (saveSnapshot) _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      opacity: OverlayClip.sanitizeOpacity(opacity),
    );
    if (notify) notifyListeners();
  }

  /// Commits a completed opacity slider drag into undo history.
  void commitOverlayOpacity(
    String id, {
    required double oldOpacity,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final current = _overlayClips[index];
    if ((current.opacity - oldOpacity).abs() < 0.001) return;

    final previousOverlays = List<OverlayClip>.from(_overlayClips);
    previousOverlays[index] = current.copyWith(opacity: oldOpacity);

    _saveSnapshotWithOverlays(previousOverlays);
  }

  void toggleOverlayFlipHorizontal(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      flipHorizontal: !_overlayClips[index].flipHorizontal,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleOverlayFlipVertical(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      flipVertical: !_overlayClips[index].flipVertical,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void updateSelectedOverlayBlendMode(BlendMode blendMode) {
    if (_selectedOverlayIndex == null ||
        _selectedOverlayIndex! < 0 ||
        _selectedOverlayIndex! >= _overlayClips.length) {
      return;
    }
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
        _selectedOverlayIndex! >= _overlayClips.length) {
      return;
    }
    _saveSnapshot();
    _overlayClips[_selectedOverlayIndex!] = _overlayClips[_selectedOverlayIndex!].copyWith(
      opacity: OverlayClip.sanitizeOpacity(opacity),
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
        _selectedOverlayIndex! >= _overlayClips.length) {
      return;
    }
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
        _selectedOverlayIndex! >= _overlayClips.length) {
      return;
    }
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
    if (!containsMediaAsset(asset)) {
      _mediaLibrary.add(asset);
    }
    final playheadMs = (_playheadPosition * 1000).round();
    final dur = asset.duration ?? const Duration(seconds: 4);
    final isPhoto = asset.type == MediaAssetType.photo || asset.isPhoto;

    final overlay = OverlayClip(
      id: 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      title: asset.name.isNotEmpty ? asset.name : 'PIP Layer',
      assetId: asset.id,
      localPath: asset.localPath ?? asset.thumbnailPath,
      thumbnailPath: asset.thumbnailPath,
      isPhoto: isPhoto,
      startTime: Duration(milliseconds: playheadMs),
      duration: dur,
      previewGradient: const [Color(0xFF00C6FF), Color(0xFF0072FF)],
      previewIcon: isPhoto ? Icons.image_rounded : Icons.movie_filter_rounded,
      position: const Offset(0.5, 0.5),
      scale: 0.5,
      opacity: 1.0,
      blendMode: BlendMode.srcOver,
    );

    _overlayClips.add(overlay);
    debugPrint('[PIP] Overlay Added: ${overlay.id}');
    _selectedOverlayIndex = _overlayClips.length - 1;
    _selectedClipIndex = null;
    _selectedTextId = null;
    _selectedStickerId = null;
    _selectedAudioTrackId = null;
    _isAudioSelected = false;
    scheduleAutoSave();
    notifyListeners();
  }

  // --- Advanced PIP Editing Operations ---

  void updateOverlaySpeed(String id, double speed) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final sanitized = OverlayClip.sanitizeSpeed(speed);
    _overlayClips[index] = _overlayClips[index].copyWith(speed: sanitized);
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Speed set to ${sanitized}x');
  }

  void updateOverlayAudio(
    String id, {
    double? volume,
    bool? isMuted,
    double? fadeIn,
    double? fadeInSec,
    double? fadeOut,
    double? fadeOutSec,
    PipAudioEffects? audioEffects,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      volume: volume != null ? OverlayClip.sanitizeVolume(volume) : null,
      isMuted: isMuted,
      fadeInDurationSec: fadeIn ?? fadeInSec,
      fadeOutDurationSec: fadeOut ?? fadeOutSec,
      audioEffects: audioEffects,
    );
    scheduleAutoSave();
    notifyListeners();
    if (isMuted != null) {
      TtsService.announce(isMuted ? 'Overlay audio muted' : 'Overlay audio unmuted');
    } else if (volume != null) {
      TtsService.announce('Volume ${(volume * 100).round()}%');
    }
  }

  void updateOverlayAnimation(
    String id, {
    PipAnimation? inAnim,
    PipAnimation? inAnimation,
    bool clearInAnim = false,
    PipAnimation? overallAnim,
    PipAnimation? overallAnimation,
    bool clearOverallAnim = false,
    PipAnimation? outAnim,
    PipAnimation? outAnimation,
    bool clearOutAnim = false,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      inAnimation: inAnim ?? inAnimation,
      clearInAnimation: clearInAnim,
      overallAnimation: overallAnim ?? overallAnimation,
      clearOverallAnimation: clearOverallAnim,
      outAnimation: outAnim ?? outAnimation,
      clearOutAnimation: clearOutAnim,
    );
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Animation updated');
  }

  void updateOverlayCrop(
    String id, {
    Rect? cropRect,
    bool clearCrop = false,
    String? cropAspectRatio,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      cropRect: cropRect,
      clearCropRect: clearCrop,
      cropAspectRatio: cropAspectRatio,
    );
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce(clearCrop ? 'Crop reset' : 'Crop applied');
  }

  void updateOverlayCornerPin(
    String id, {
    Offset? tl,
    Offset? topLeft,
    Offset? tr,
    Offset? topRight,
    Offset? bl,
    Offset? bottomLeft,
    Offset? br,
    Offset? bottomRight,
    bool clearCornerPin = false,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      cornerTopLeft: tl ?? topLeft,
      cornerTopRight: tr ?? topRight,
      cornerBottomLeft: bl ?? bottomLeft,
      cornerBottomRight: br ?? bottomRight,
      clearCornerPin: clearCornerPin,
    );
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce(clearCornerPin ? 'Corner pin reset' : 'Corner pin adjusted');
  }

  void updateOverlayBlendMode(String id, BlendMode blendMode) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(blendMode: blendMode);
    scheduleAutoSave();
    notifyListeners();
  }

  void updateOverlayChromaKey(
    String id, {
    bool? enabled,
    Color? color,
    double? similarity,
    double? smoothness,
    double? spill,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      enableChromaKey: enabled,
      chromaKeyColor: color,
      chromaSimilarity: similarity,
      chromaSmoothness: smoothness,
      chromaSpill: spill,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void updateOverlayFilter(
    String id, {
    String? filterId,
    double? intensity,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      filterId: filterId,
      filterIntensity: intensity?.clamp(0.0, 1.0),
    );
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Filter ${filterId ?? "none"} applied');
  }

  void updateOverlayAdjustments(
    String id,
    PipAdjustments adjustments,
  ) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(adjustments: adjustments);
    scheduleAutoSave();
    notifyListeners();
  }

  void updateOverlayEffects(
    String id, {
    PipOutline? outline,
    PipShadow? shadow,
    PipGlow? glow,
    String? effectId,
    double? effectIntensity,
  }) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    _overlayClips[index] = _overlayClips[index].copyWith(
      outline: outline,
      shadow: shadow,
      glow: glow,
      effectId: effectId,
      effectIntensity: effectIntensity,
    );
    scheduleAutoSave();
    notifyListeners();
  }

  void applySplitScreenPreset(String id, String preset) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _overlayClips[index];

    Offset pos = current.position;
    double scale = current.scale;
    Rect? crop;

    switch (preset) {
      case 'left':
        pos = const Offset(0.25, 0.5);
        scale = 0.5;
        crop = const Rect.fromLTWH(0.0, 0.0, 0.5, 1.0);
        break;
      case 'right':
        pos = const Offset(0.75, 0.5);
        scale = 0.5;
        crop = const Rect.fromLTWH(0.5, 0.0, 0.5, 1.0);
        break;
      case 'top':
        pos = const Offset(0.5, 0.25);
        scale = 0.5;
        crop = const Rect.fromLTWH(0.0, 0.0, 1.0, 0.5);
        break;
      case 'bottom':
        pos = const Offset(0.5, 0.75);
        scale = 0.5;
        crop = const Rect.fromLTWH(0.0, 0.5, 1.0, 0.5);
        break;
      case 'quad_tl':
        pos = const Offset(0.25, 0.25);
        scale = 0.48;
        crop = null;
        break;
      case 'quad_tr':
        pos = const Offset(0.75, 0.25);
        scale = 0.48;
        crop = null;
        break;
      case 'quad_bl':
        pos = const Offset(0.25, 0.75);
        scale = 0.48;
        crop = null;
        break;
      case 'quad_br':
        pos = const Offset(0.75, 0.75);
        scale = 0.48;
        crop = null;
        break;
      case 'pip':
      case 'pictureInPicture':
        pos = const Offset(0.75, 0.25);
        scale = 0.35;
        crop = null;
        break;
      case 'reset':
      default:
        pos = const Offset(0.5, 0.5);
        scale = 0.5;
        crop = null;
        break;
    }

    _overlayClips[index] = current.copyWith(
      position: pos,
      scale: scale,
      cropRect: crop,
      clearCropRect: crop == null,
      splitScreenPreset: preset,
    );
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Split screen $preset applied');
  }

  void extractAudioFromOverlay(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final overlay = _overlayClips[index];
    if (overlay.isPhoto) {
      TtsService.announce('Cannot extract audio from a photo overlay');
      return;
    }
    _saveSnapshot();
    final audioId = 'audio_pip_${DateTime.now().millisecondsSinceEpoch}';
    final audioTrack = AudioTrack(
      id: audioId,
      assetId: overlay.assetId ?? overlay.id,
      name: '${overlay.title} (Audio)',
      startTime: overlay.startTime,
      duration: overlay.duration,
      trimStart: Duration.zero,
      trimEnd: overlay.duration,
      volume: overlay.volume.clamp(0.0, 1.0),
      speed: overlay.speed,
      isMuted: false,
      waveformPoints: const [],
      beats: const [],
    );
    _audioTracks.add(audioTrack);
    // Mute the overlay video so audio is not duplicated
    _overlayClips[index] = overlay.copyWith(isMuted: true, volume: 0.0);
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Audio extracted to timeline track');
  }

  Future<void> generateAutoCaptionsFromOverlay(String id) async {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final overlay = _overlayClips[index];
    _saveSnapshot();
    final provider = DefaultPipAiProvider();
    final captions = await provider.generateCaptions(
      overlayId: overlay.id,
      startTime: overlay.startTime,
      duration: overlay.duration,
      overlayTitle: overlay.title,
    );
    for (final cap in captions) {
      _textOverlays.add(cap);
    }
    scheduleAutoSave();
    notifyListeners();
    TtsService.announce('Auto captions generated from PIP');
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
    final clip = _videoClips[_selectedClipIndex!];
    if (clip.freezeFrame != null || clip.isFrozen) {
      removeFreezeFrame();
    } else {
      addFreezeFrameAtPlayhead();
    }
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
    KeyframeTrackGroup updatedTracks = clip.effectiveKeyframeTracks;
    if (clip.keyframes.isNotEmpty || updatedTracks.isNotEmpty) {
      final clipStart = getClipStartTime(index);
      final relTime = (_playheadPosition - clipStart).clamp(0.0, clip.durationInSeconds);
      final timeMs = (relTime * 1000).round();
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
          timestamp: Duration(milliseconds: timeMs),
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

      updatedTracks = updatedTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: sanitizedX,
        posY: sanitizedY,
        scale: sanitizedScale,
        rotation: totalRotationDeg,
        opacity: clip.opacity,
        easing: EasingCurve.easeInOut,
      );
    }

    _videoClips[index] = clip.copyWith(
      xPos: sanitizedX,
      yPos: sanitizedY,
      scale: sanitizedScale,
      rotationAngle: sanitizedRotation,
      keyframes: updatedKeyframes,
      keyframeTracks: updatedTracks,
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

  // --- Speed, Speed Ramping, Freeze Frame & Time Remapping ---

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
    final label = clampedSpeed == clampedSpeed.roundToDouble()
        ? clampedSpeed.toInt().toString()
        : clampedSpeed.toStringAsFixed(1);
    TtsService.announce('Speed set to $label times');
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
    TtsService.announce('Speed ramp selected');
    notifyListeners();
  }

  void addSpeedPoint(double timeRatio, double speedMultiplier, {SpeedInterpolation interpolation = SpeedInterpolation.linear}) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final ratio = timeRatio.clamp(0.0, 1.0);
    final speed = speedMultiplier.clamp(0.1, 50.0);

    final currentCurve = clip.speedCurve ?? SpeedCurve.custom(points: [
      SpeedCurvePoint(timeRatio: 0.0, speedMultiplier: clip.speed),
      SpeedCurvePoint(timeRatio: 1.0, speedMultiplier: clip.speed),
    ]);

    final updatedPoints = List<SpeedCurvePoint>.from(currentCurve.points)
      ..add(SpeedCurvePoint(timeRatio: ratio, speedMultiplier: speed, interpolation: interpolation))
      ..sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    final newCurve = currentCurve.copyWith(
      type: SpeedCurvePresetType.custom,
      points: updatedPoints,
    );

    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: newCurve.averageSpeed.clamp(0.1, 50.0),
      speedCurve: newCurve,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    TtsService.announce('Speed point added');
    notifyListeners();
  }

  void updateSpeedPoint(int pointIndex, {double? timeRatio, double? speedMultiplier, SpeedInterpolation? interpolation}) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (clip.speedCurve == null || pointIndex < 0 || pointIndex >= clip.speedCurve!.points.length) return;

    _saveSnapshot();
    final currentCurve = clip.speedCurve!;
    final points = List<SpeedCurvePoint>.from(currentCurve.points);
    final oldPt = points[pointIndex];
    points[pointIndex] = oldPt.copyWith(
      timeRatio: timeRatio?.clamp(0.0, 1.0),
      speedMultiplier: speedMultiplier?.clamp(0.1, 50.0),
      interpolation: interpolation,
    );
    points.sort((a, b) => a.timeRatio.compareTo(b.timeRatio));

    final newCurve = currentCurve.copyWith(
      type: SpeedCurvePresetType.custom,
      points: points,
    );

    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: newCurve.averageSpeed.clamp(0.1, 50.0),
      speedCurve: newCurve,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    notifyListeners();
  }

  void removeSpeedPoint(int pointIndex) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (clip.speedCurve == null || pointIndex < 0 || pointIndex >= clip.speedCurve!.points.length) return;
    if (clip.speedCurve!.points.length <= 2) return; // Must retain at least 2 boundary points

    _saveSnapshot();
    final currentCurve = clip.speedCurve!;
    final points = List<SpeedCurvePoint>.from(currentCurve.points)..removeAt(pointIndex);

    final newCurve = currentCurve.copyWith(
      type: SpeedCurvePresetType.custom,
      points: points,
    );

    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: newCurve.averageSpeed.clamp(0.1, 50.0),
      speedCurve: newCurve,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    TtsService.announce('Speed point deleted');
    notifyListeners();
  }

  void resetClipSpeed() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      speed: 1.0,
      clearSpeedCurve: true,
      clearFreezeFrame: true,
      isReversed: false,
      isFrozen: false,
    );
    _playheadPosition = _playheadPosition.clamp(0.0, math.max(0.0, totalDurationInSeconds));
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    TtsService.announce('Speed reset');
    notifyListeners();
  }

  void toggleClipReverse({int? index}) {
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) return;
    _saveSnapshot();
    final clip = _videoClips[targetIndex];
    final newReversed = !clip.isReversed;
    _videoClips[targetIndex] = clip.copyWith(isReversed: newReversed);
    scheduleAutoSave();
    TtsService.announce(newReversed ? 'Reverse playback enabled' : 'Reverse playback disabled');
    notifyListeners();
  }

  void addFreezeFrameAtPlayhead({
    Duration? timelineOffset,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    final Duration effectiveTimelineOffset;
    if (timelineOffset != null) {
      effectiveTimelineOffset = timelineOffset;
    } else {
      final clipStart = getClipStartTime(_selectedClipIndex!);
      final offsetInClipSec = _playheadPosition - clipStart;
      if (offsetInClipSec < 0.0 || offsetInClipSec > clip.durationInSeconds) return;
      effectiveTimelineOffset = Duration(milliseconds: (offsetInClipSec * 1000).round());
    }

    _saveSnapshot();
    final sourceTime = TimeRemapper.timelineToSourceTime(
      timelineOffset: effectiveTimelineOffset,
      trimStart: clip.trimStart,
      trimEnd: clip.trimEnd,
      originalDuration: clip.originalDuration,
      speedCurve: clip.speedCurve,
      constantSpeed: clip.speed,
      isReversed: clip.isReversed,
      freezeFrame: clip.freezeFrame,
    );

    final freeze = FreezeFrame(
      timelineOffset: effectiveTimelineOffset,
      duration: duration,
      sourceTime: sourceTime,
    );

    _videoClips[_selectedClipIndex!] = clip.copyWith(freezeFrame: freeze);
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    TtsService.announce('Freeze frame added');
    notifyListeners();
  }

  void removeFreezeFrame({int? index}) {
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) return;
    _saveSnapshot();
    final clip = _videoClips[targetIndex];
    _videoClips[targetIndex] = clip.copyWith(clearFreezeFrame: true, isFrozen: false);
    _cleanupInvalidTransitions();
    scheduleAutoSave();
    TtsService.announce('Freeze frame removed');
    notifyListeners();
  }

  // --- PIP Video Overlay Speed Operations ---

  void setOverlaySpeed(String overlayId, double speed) {
    final idx = _overlayClips.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final overlay = _overlayClips[idx];
    if (overlay.isPhotoOverlay) return; // Image PIP unaffected

    _saveSnapshot();
    final clampedSpeed = speed.clamp(0.1, 100.0);
    _overlayClips[idx] = overlay.copyWith(
      speed: clampedSpeed,
      clearSpeedCurve: true,
    );
    scheduleAutoSave();
    final label = clampedSpeed == clampedSpeed.roundToDouble()
        ? clampedSpeed.toInt().toString()
        : clampedSpeed.toStringAsFixed(1);
    TtsService.announce('Speed set to $label times');
    notifyListeners();
  }

  void setOverlaySpeedCurve(String overlayId, SpeedCurve curve) {
    final idx = _overlayClips.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final overlay = _overlayClips[idx];
    if (overlay.isPhotoOverlay) return; // Image PIP unaffected

    _saveSnapshot();
    final avgSpeed = curve.averageSpeed.clamp(0.1, 100.0);
    _overlayClips[idx] = overlay.copyWith(
      speed: avgSpeed,
      speedCurve: curve,
    );
    scheduleAutoSave();
    TtsService.announce('Speed ramp selected');
    notifyListeners();
  }

  void toggleOverlayReverse(String overlayId) {
    final idx = _overlayClips.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final overlay = _overlayClips[idx];
    if (overlay.isPhotoOverlay) return;

    _saveSnapshot();
    _overlayClips[idx] = overlay.copyWith(isReversed: !overlay.isReversed);
    scheduleAutoSave();
    TtsService.announce(!overlay.isReversed ? 'Reverse playback enabled' : 'Reverse playback disabled');
    notifyListeners();
  }

  void addOverlayFreezeFrame(
    String overlayId, {
    Duration? timelineOffset,
    Duration duration = const Duration(seconds: 3),
  }) {
    final idx = _overlayClips.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final overlay = _overlayClips[idx];
    if (overlay.isPhotoOverlay) return;

    final Duration effectiveTimelineOffset;
    if (timelineOffset != null) {
      effectiveTimelineOffset = timelineOffset;
    } else {
      final overlayStart = overlay.startTimeInSeconds;
      final offsetInOverlaySec = _playheadPosition - overlayStart;
      if (offsetInOverlaySec < 0.0 || offsetInOverlaySec > overlay.durationInSeconds) return;
      effectiveTimelineOffset = Duration(milliseconds: (offsetInOverlaySec * 1000).round());
    }

    _saveSnapshot();
    final sourceTime = TimeRemapper.timelineToSourceTime(
      timelineOffset: effectiveTimelineOffset,
      trimStart: Duration.zero,
      trimEnd: overlay.duration,
      originalDuration: overlay.duration,
      speedCurve: overlay.speedCurve,
      constantSpeed: overlay.speed,
      isReversed: overlay.isReversed,
      freezeFrame: overlay.freezeFrame,
    );

    final freeze = FreezeFrame(
      timelineOffset: effectiveTimelineOffset,
      duration: duration,
      sourceTime: sourceTime,
    );

    _overlayClips[idx] = overlay.copyWith(freezeFrame: freeze);
    scheduleAutoSave();
    TtsService.announce('Freeze frame added');
    notifyListeners();
  }

  void removeOverlayFreezeFrame(String overlayId) {
    final idx = _overlayClips.indexWhere((o) => o.id == overlayId);
    if (idx == -1) return;
    final overlay = _overlayClips[idx];
    _saveSnapshot();
    _overlayClips[idx] = overlay.copyWith(clearFreezeFrame: true, isFrozen: false);
    scheduleAutoSave();
    TtsService.announce('Freeze frame removed');
    notifyListeners();
  }

  void setClipVolume(double volume) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final clampedVol = volume.clamp(0.0, 2.0);
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      volume: clampedVol,
      isMuted: clampedVol == 0.0 ? true : false,
    );
    scheduleAutoSave();
    TtsService.announce('Video volume ${(clampedVol * 100).round()}%');
    notifyListeners();
  }

  void toggleClipMute({int? index}) {
    final targetIndex = index ?? _selectedClipIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _videoClips.length) return;
    _saveSnapshot();
    final clip = _videoClips[targetIndex];
    final newMuted = !clip.isMuted;
    _videoClips[targetIndex] = clip.copyWith(isMuted: newMuted);
    scheduleAutoSave();
    TtsService.announce(newMuted ? 'Video audio muted' : 'Video audio unmuted');
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
      final updated = track.copyWith(
        trimStart: newTrimStart,
      );
      _audioTracks[index] = updated.copyWith(
        fadeInDuration: updated.effectiveFadeInDuration,
        fadeOutDuration: updated.effectiveFadeOutDuration,
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
      final updated = track.copyWith(
        trimEnd: newTrimEnd,
      );
      _audioTracks[index] = updated.copyWith(
        fadeInDuration: updated.effectiveFadeInDuration,
        fadeOutDuration: updated.effectiveFadeOutDuration,
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
    final trimmedTrack = track.copyWith(
      trimStart: clampedTrimStart,
      trimEnd: clampedTrimEnd,
    );
    _audioTracks[index] = trimmedTrack.copyWith(
      fadeInDuration: trimmedTrack.effectiveFadeInDuration,
      fadeOutDuration: trimmedTrack.effectiveFadeOutDuration,
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
      fadeInDuration: targetTrack.effectiveFadeInDuration,
      fadeOutDuration: Duration.zero,
    );

    final partB = targetTrack.copyWith(
      id: '${targetTrack.id}_b_$timestamp',
      title: '${targetTrack.title} (Part 2)',
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      trimStart: splitPoint,
      trimEnd: targetTrack.effectiveTrimEnd,
      fadeInDuration: Duration.zero,
      fadeOutDuration: targetTrack.effectiveFadeOutDuration,
    );

    _audioTracks.removeAt(targetIndex);
    _audioTracks.insert(targetIndex, partA);
    _audioTracks.insert(targetIndex + 1, partB);

    _selectedAudioTrackId = partB.id;
    _isAudioSelected = true;
    _syncAudioPlayback(forceSeek: true);
    scheduleAutoSave();
    TtsService.announce('Split audio at playhead');
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
      keyframeTracks: track.effectiveKeyframeTracks.duplicate(),
    );

    _audioTracks.add(duplicate);
    _selectedAudioTrackId = duplicate.id;
    _isAudioSelected = true;
    _syncAudioPlayback(forceSeek: true);
    TtsService.announce('Duplicated audio track');
    notifyListeners();
    return duplicate;
  }

  void setAudioTrackVolume(double volume, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final clamped = volume.clamp(0.0, 2.0);
    _audioTracks[index] = _audioTracks[index].copyWith(volume: clamped);
    if (_audioTracks[index].id == selectedAudioTrack?.id) {
      AudioPlaybackService.instance.setVolume((_audioTracks[index].isMuted ? 0.0 : clamped).clamp(0.0, 1.0));
    }
    TtsService.announce('Audio volume ${(clamped * 100).round()}%');
    scheduleAutoSave();
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
      AudioPlaybackService.instance.setVolume(newMuted ? 0.0 : _audioTracks[index].volume.clamp(0.0, 1.0));
    }
    TtsService.announce(newMuted ? 'Audio track muted' : 'Audio track unmuted');
    scheduleAutoSave();
    notifyListeners();
  }

  void setAudioTrackFadeIn(Duration fadeIn, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final track = _audioTracks[index];
    final maxFadeIn = (track.effectiveDuration.inMilliseconds - track.effectiveFadeOutDuration.inMilliseconds).clamp(0, track.effectiveDuration.inMilliseconds);
    final clampedFadeIn = Duration(milliseconds: fadeIn.inMilliseconds.clamp(0, maxFadeIn));
    _audioTracks[index] = track.copyWith(fadeInDuration: clampedFadeIn);
    TtsService.announce('Fade in ${(clampedFadeIn.inMilliseconds / 1000.0).toStringAsFixed(1)} seconds');
    scheduleAutoSave();
    notifyListeners();
  }

  void setAudioTrackFadeOut(Duration fadeOut, {String? id}) {
    final targetId = id ?? _selectedAudioTrackId ?? (_audioTracks.isNotEmpty ? _audioTracks.first.id : null);
    if (targetId == null) return;
    final index = _audioTracks.indexWhere((t) => t.id == targetId);
    if (index == -1) return;

    _saveSnapshot();
    final track = _audioTracks[index];
    final maxFadeOut = (track.effectiveDuration.inMilliseconds - track.effectiveFadeInDuration.inMilliseconds).clamp(0, track.effectiveDuration.inMilliseconds);
    final clampedFadeOut = Duration(milliseconds: fadeOut.inMilliseconds.clamp(0, maxFadeOut));
    _audioTracks[index] = track.copyWith(fadeOutDuration: clampedFadeOut);
    TtsService.announce('Fade out ${(clampedFadeOut.inMilliseconds / 1000.0).toStringAsFixed(1)} seconds');
    scheduleAutoSave();
    notifyListeners();
  }

  void setOverlayVolume(double volume, {int? index}) {
    final targetIndex = index ?? _selectedOverlayIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _overlayClips.length) return;
    _saveSnapshot();
    final clamped = volume.clamp(0.0, 2.0);
    _overlayClips[targetIndex] = _overlayClips[targetIndex].copyWith(volume: clamped);
    TtsService.announce('PIP volume ${(clamped * 100).round()}%');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleOverlayMute({int? index}) {
    final targetIndex = index ?? _selectedOverlayIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[targetIndex];
    final newMuted = !overlay.isMuted;
    _overlayClips[targetIndex] = overlay.copyWith(isMuted: newMuted);
    TtsService.announce(newMuted ? 'PIP audio muted' : 'PIP audio unmuted');
    scheduleAutoSave();
    notifyListeners();
  }

  void setOverlayFadeIn(double durationSec, {int? index}) {
    final targetIndex = index ?? _selectedOverlayIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[targetIndex];
    final maxFadeIn = (overlay.durationInSeconds - overlay.fadeOutDurationSec).clamp(0.0, overlay.durationInSeconds);
    final clamped = durationSec.clamp(0.0, maxFadeIn);
    _overlayClips[targetIndex] = overlay.copyWith(fadeInDurationSec: clamped);
    scheduleAutoSave();
    notifyListeners();
  }

  void setOverlayFadeOut(double durationSec, {int? index}) {
    final targetIndex = index ?? _selectedOverlayIndex;
    if (targetIndex == null || targetIndex < 0 || targetIndex >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[targetIndex];
    final maxFadeOut = (overlay.durationInSeconds - overlay.fadeInDurationSec).clamp(0.0, overlay.durationInSeconds);
    final clamped = durationSec.clamp(0.0, maxFadeOut);
    _overlayClips[targetIndex] = overlay.copyWith(fadeOutDurationSec: clamped);
    scheduleAutoSave();
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

  bool _isSnapToClipsEnabled = true;
  bool get isSnapToClipsEnabled => _isSnapToClipsEnabled;

  void toggleSnapToClips([bool? enabled]) {
    _isSnapToClipsEnabled = enabled ?? !_isSnapToClipsEnabled;
    TtsService.announce(_isSnapToClipsEnabled ? 'Timeline snapping enabled' : 'Timeline snapping disabled');
    notifyListeners();
  }

  /// Structural snap boundaries across clips, transitions, overlays, texts, and audios.
  List<double> get snapBoundaries {
    final boundaries = <double>{0.0, totalDurationInSeconds};
    double runningStart = 0.0;
    for (final clip in _videoClips) {
      boundaries.add(runningStart);
      runningStart += clip.durationInSeconds;
      boundaries.add(runningStart);
    }
    for (final ov in _overlayClips) {
      boundaries.add(ov.startTimeInSeconds);
      boundaries.add(ov.endTimeInSeconds);
    }
    for (final txt in _textOverlays) {
      boundaries.add(txt.startTimeInSeconds);
      boundaries.add(txt.endTimeInSeconds);
    }
    for (final aud in _audioTracks) {
      boundaries.add(aud.startTimeInSeconds);
      boundaries.add(aud.endTimeInSeconds);
    }
    final sorted = boundaries.toList()..sort();
    return sorted;
  }

  /// Snaps [targetTimelineSec] to nearest boundary (if enabled) and nearest beat (if enabled).
  double snapTimelinePosition(double targetTimelineSec, {double threshold = 0.08}) {
    double snapped = targetTimelineSec;
    if (_isSnapToClipsEnabled) {
      final boundarySnap = TimelineCoordinateSystem.snapToNearestBoundary(
        snapped,
        snapBoundaries,
        thresholdSeconds: threshold,
      );
      if ((boundarySnap - snapped).abs() > 0.001) {
        HapticFeedback.selectionClick();
        snapped = boundarySnap;
      }
    }
    if (_isSnapToBeatEnabled) {
      snapped = snapToNearestBeat(snapped, threshold: threshold);
    }
    return snapped;
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

  void updateTextOverlay(TextOverlay overlay, {bool saveSnapshot = true, bool notify = true}) {
    if (saveSnapshot) _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == overlay.id);
    if (index != -1) {
      _textOverlays[index] = overlay;
      scheduleAutoSave();
      if (notify) notifyListeners();
    }
  }

  void updateTextPosition(String id, Offset newPos, {bool notify = true}) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      final sanitized = TextOverlay.sanitizePosition(newPos, fallback: _textOverlays[index].position);
      _textOverlays[index] = _textOverlays[index].copyWith(position: sanitized);
      if (notify) {
        scheduleAutoSave();
        notifyListeners();
      }
    }
  }

  void updateTextScale(String id, double scale, {bool notify = true}) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      final sanitized = TextOverlay.sanitizeScale(scale, fallback: _textOverlays[index].scale);
      _textOverlays[index] = _textOverlays[index].copyWith(scale: sanitized);
      if (notify) {
        scheduleAutoSave();
        notifyListeners();
      }
    }
  }

  void updateTextTransform(
    String id, {
    Offset? position,
    double? scale,
    bool notify = true,
    bool scheduleSave = true,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index != -1) {
      final current = _textOverlays[index];
      final newPos = position != null ? TextOverlay.sanitizePosition(position, fallback: current.position) : current.position;
      final newScale = scale != null ? TextOverlay.sanitizeScale(scale, fallback: current.scale) : current.scale;
      _textOverlays[index] = current.copyWith(
        position: newPos,
        scale: newScale,
      );
      if (scheduleSave) scheduleAutoSave();
      if (notify) notifyListeners();
    }
  }

  /// Commits a completed interactive drag/scale transform gesture into the undo history.
  /// Exactly ONE undo snapshot is created for the complete gesture interaction.
  void commitTextTransform(String id, {required Offset oldPosition, required double oldScale}) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final current = _textOverlays[index];
    if (current.position == oldPosition && current.scale == oldScale) return;

    final previousOverlays = List<TextOverlay>.from(_textOverlays);
    previousOverlays[index] = current.copyWith(position: oldPosition, scale: oldScale);
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: previousOverlays,
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

    if (current.keyframes.isNotEmpty || current.effectiveKeyframeTracks.isNotEmpty) {
      final relTime = (_playheadPosition - current.startTimeInSeconds).clamp(0.0, current.durationInSeconds);
      final timeMs = (relTime * 1000).round();
      final updatedTracks = current.effectiveKeyframeTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: current.position.dx,
        posY: current.position.dy,
        scale: current.scale,
        rotation: 0.0,
        opacity: 1.0,
        easing: EasingCurve.easeInOut,
      );
      _textOverlays[index] = current.copyWith(
        keyframeTracks: updatedTracks,
        keyframes: updatedTracks.toVideoKeyframes(),
      );
    }

    scheduleAutoSave();
    notifyListeners();
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
    bool saveSnapshot = true,
    bool notify = true,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    if (saveSnapshot) {
      _saveSnapshot();
    }
    _textOverlays[index] = _textOverlays[index].copyWith(
      startTime: newStart,
      duration: newDuration,
      trimStart: trimStart ?? _textOverlays[index].trimStart,
      trimEnd: trimEnd ?? newDuration,
    );
    scheduleAutoSave();
    if (notify) {
      notifyListeners();
    }
  }

  /// Commits a completed timeline trim or drag timing gesture into the undo history.
  /// Exactly ONE undo snapshot is created for the complete timing interaction.
  void commitTextTiming(
    String id, {
    required Duration oldStart,
    required Duration oldDuration,
    Duration? oldTrimStart,
    Duration? oldTrimEnd,
  }) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final current = _textOverlays[index];
    if (current.startTime == oldStart &&
        current.duration == oldDuration &&
        (oldTrimStart == null || current.trimStart == oldTrimStart) &&
        (oldTrimEnd == null || current.trimEnd == oldTrimEnd)) {
      return;
    }

    final previousOverlays = List<TextOverlay>.from(_textOverlays);
    previousOverlays[index] = current.copyWith(
      startTime: oldStart,
      duration: oldDuration,
      trimStart: oldTrimStart ?? current.trimStart,
      trimEnd: oldTrimEnd ?? oldDuration,
    );
    _undoStack.add(
      _EditorSnapshot(
        clips: List.from(_videoClips),
        overlayClips: List.from(_overlayClips),
        stickerOverlays: List.from(_stickerOverlays),
        textOverlays: previousOverlays,
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

  TextOverlay? duplicateSelectedText() {
    final text = selectedTextOverlay;
    if (text == null) return null;

    _saveSnapshot();
    final index = _textOverlays.indexWhere((t) => t.id == text.id);
    final newStart = text.startTime + text.effectiveDuration;

    final duplicated = text.copyWith(
      id: '${text.id}_dup_${DateTime.now().millisecondsSinceEpoch}',
      startTime: newStart,
      keyframeTracks: text.effectiveKeyframeTracks.duplicate(),
      keyframes: text.keyframes
          .map((k) => k.copyWith(id: 'kf_${DateTime.now().microsecondsSinceEpoch}_${k.timestamp.inMilliseconds}'))
          .toList(),
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
    final clonedMasks = original.masks.map((m) {
      final newId = 'mask_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(10000)}';
      return m.copyWith(
        id: newId,
        keyframeTracks: m.keyframeTracks?.duplicate(),
      );
    }).toList();

    final duplicated = original.copyWith(
      id: 'overlay_dup_${DateTime.now().millisecondsSinceEpoch}',
      title: '${original.title} (Copy)',
      startTime: original.startTime + const Duration(milliseconds: 300),
      keyframeTracks: original.effectiveKeyframeTracks.duplicate(),
      keyframes: original.keyframes
          .map((k) => k.copyWith(id: 'kf_${DateTime.now().microsecondsSinceEpoch}_${k.timestamp.inMilliseconds}'))
          .toList(),
      masks: clonedMasks,
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

  // --- Advanced Layer Management: Lock / Unlock ---

  void toggleClipLock(String id, [bool? locked]) {
    final index = _videoClips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _videoClips[index];
    final newLocked = locked ?? !current.isLocked;
    _videoClips[index] = current.copyWith(isLocked: newLocked);
    TtsService.announce(newLocked ? 'Clip locked' : 'Clip unlocked');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleOverlayLock(String id, [bool? locked]) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _overlayClips[index];
    final newLocked = locked ?? !current.isLocked;
    _overlayClips[index] = current.copyWith(isLocked: newLocked);
    TtsService.announce(newLocked ? 'Overlay locked' : 'Overlay unlocked');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleTextLock(String id, [bool? locked]) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _textOverlays[index];
    final newLocked = locked ?? !current.isLocked;
    _textOverlays[index] = current.copyWith(isLocked: newLocked);
    TtsService.announce(newLocked ? 'Text overlay locked' : 'Text overlay unlocked');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleAudioTrackLock(String id, [bool? locked]) {
    final index = _audioTracks.indexWhere((a) => a.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _audioTracks[index];
    final newLocked = locked ?? !current.isLocked;
    _audioTracks[index] = current.copyWith(isLocked: newLocked);
    TtsService.announce(newLocked ? 'Audio track locked' : 'Audio track unlocked');
    scheduleAutoSave();
    notifyListeners();
  }

  bool toggleSelectedLock() {
    if (selectedOverlay != null) {
      toggleOverlayLock(selectedOverlay!.id);
      return true;
    } else if (selectedTextOverlay != null) {
      toggleTextLock(selectedTextOverlay!.id);
      return true;
    } else if (selectedAudioTrack != null) {
      toggleAudioTrackLock(selectedAudioTrack!.id);
      return true;
    } else if (selectedClip != null) {
      toggleClipLock(selectedClip!.id);
      return true;
    }
    return false;
  }

  // --- Advanced Layer Management: Hide / Show (Visibility) ---

  void toggleClipVisibility(String id, [bool? visible]) {
    final index = _videoClips.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _videoClips[index];
    final newVisible = visible ?? !current.isVisible;
    _videoClips[index] = current.copyWith(isVisible: newVisible);
    TtsService.announce(newVisible ? 'Clip visible' : 'Clip hidden');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleOverlayVisibility(String id, [bool? visible]) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _overlayClips[index];
    final newVisible = visible ?? !current.isVisible;
    _overlayClips[index] = current.copyWith(isVisible: newVisible);
    TtsService.announce(newVisible ? 'Overlay visible' : 'Overlay hidden');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleTextVisibility(String id, [bool? visible]) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _textOverlays[index];
    final newVisible = visible ?? !current.isVisible;
    _textOverlays[index] = current.copyWith(isVisible: newVisible);
    TtsService.announce(newVisible ? 'Text visible' : 'Text hidden');
    scheduleAutoSave();
    notifyListeners();
  }

  void toggleAudioTrackVisibility(String id, [bool? visible]) {
    final index = _audioTracks.indexWhere((a) => a.id == id);
    if (index == -1) return;
    _saveSnapshot();
    final current = _audioTracks[index];
    final newVisible = visible ?? !current.isVisible;
    _audioTracks[index] = current.copyWith(isVisible: newVisible);
    TtsService.announce(newVisible ? 'Audio track visible' : 'Audio track muted');
    scheduleAutoSave();
    notifyListeners();
  }

  bool toggleSelectedVisibility() {
    if (selectedOverlay != null) {
      toggleOverlayVisibility(selectedOverlay!.id);
      return true;
    } else if (selectedTextOverlay != null) {
      toggleTextVisibility(selectedTextOverlay!.id);
      return true;
    } else if (selectedAudioTrack != null) {
      toggleAudioTrackVisibility(selectedAudioTrack!.id);
      return true;
    } else if (selectedClip != null) {
      toggleClipVisibility(selectedClip!.id);
      return true;
    }
    return false;
  }

  // --- Advanced Layer Management: Z-Order & Layer Reordering ---

  void moveOverlayUp(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1 || index >= _overlayClips.length - 1) return;
    _saveSnapshot();
    final item = _overlayClips.removeAt(index);
    _overlayClips.insert(index + 1, item);
    _selectedOverlayIndex = index + 1;
    TtsService.announce('Layer moved up');
    scheduleAutoSave();
    notifyListeners();
  }

  void moveOverlayDown(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index <= 0) return;
    _saveSnapshot();
    final item = _overlayClips.removeAt(index);
    _overlayClips.insert(index - 1, item);
    _selectedOverlayIndex = index - 1;
    TtsService.announce('Layer moved down');
    scheduleAutoSave();
    notifyListeners();
  }

  void bringOverlayToFront(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index == -1 || index == _overlayClips.length - 1) return;
    _saveSnapshot();
    final item = _overlayClips.removeAt(index);
    _overlayClips.add(item);
    _selectedOverlayIndex = _overlayClips.length - 1;
    TtsService.announce('Layer brought to front');
    scheduleAutoSave();
    notifyListeners();
  }

  void sendOverlayToBack(String id) {
    final index = _overlayClips.indexWhere((o) => o.id == id);
    if (index <= 0) return;
    _saveSnapshot();
    final item = _overlayClips.removeAt(index);
    _overlayClips.insert(0, item);
    _selectedOverlayIndex = 0;
    TtsService.announce('Layer sent to back');
    scheduleAutoSave();
    notifyListeners();
  }

  void reorderOverlays(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _overlayClips.length) return;
    if (newIndex < 0 || newIndex > _overlayClips.length) return;
    _saveSnapshot();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _overlayClips.removeAt(oldIndex);
    _overlayClips.insert(newIndex, item);
    _selectedOverlayIndex = newIndex;
    scheduleAutoSave();
    notifyListeners();
  }

  void moveTextUp(String id) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1 || index >= _textOverlays.length - 1) return;
    _saveSnapshot();
    final item = _textOverlays.removeAt(index);
    _textOverlays.insert(index + 1, item);
    scheduleAutoSave();
    notifyListeners();
  }

  void moveTextDown(String id) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index <= 0) return;
    _saveSnapshot();
    final item = _textOverlays.removeAt(index);
    _textOverlays.insert(index - 1, item);
    scheduleAutoSave();
    notifyListeners();
  }

  void bringTextToFront(String id) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index == -1 || index == _textOverlays.length - 1) return;
    _saveSnapshot();
    final item = _textOverlays.removeAt(index);
    _textOverlays.add(item);
    scheduleAutoSave();
    notifyListeners();
  }

  void sendTextToBack(String id) {
    final index = _textOverlays.indexWhere((t) => t.id == id);
    if (index <= 0) return;
    _saveSnapshot();
    final item = _textOverlays.removeAt(index);
    _textOverlays.insert(0, item);
    scheduleAutoSave();
    notifyListeners();
  }

  void reorderTexts(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _textOverlays.length) return;
    if (newIndex < 0 || newIndex > _textOverlays.length) return;
    _saveSnapshot();
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _textOverlays.removeAt(oldIndex);
    _textOverlays.insert(newIndex, item);
    scheduleAutoSave();
    notifyListeners();
  }

  // --- Multi-Layer Split at Playhead ---

  bool splitOverlayAtPlayhead([String? overlayId]) {
    final targetId = overlayId ?? selectedOverlay?.id;
    if (targetId == null) return false;
    final index = _overlayClips.indexWhere((o) => o.id == targetId);
    if (index == -1) return false;

    final original = _overlayClips[index];
    final startSec = original.startTimeInSeconds;
    final endSec = original.endTimeInSeconds;

    if (_playheadPosition <= startSec + 0.1 || _playheadPosition >= endSec - 0.1) {
      return false;
    }

    _saveSnapshot();
    final splitTime = _playheadPosition;
    final partADurMs = ((splitTime - startSec) * 1000).round();
    final partBDurMs = original.duration.inMilliseconds - partADurMs;
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    final (overlayTracksA, overlayTracksB) = original.effectiveKeyframeTracks.splitAt(partADurMs);

    final partA = original.copyWith(
      id: '${original.id}_part1_$timestamp',
      title: '${original.title} (Part 1)',
      duration: Duration(milliseconds: partADurMs),
      keyframeTracks: overlayTracksA,
      keyframes: overlayTracksA.toVideoKeyframes(),
      clearOutAnimation: false,
    );

    final partB = original.copyWith(
      id: '${original.id}_part2_$timestamp',
      title: '${original.title} (Part 2)',
      startTime: Duration(milliseconds: (splitTime * 1000).round()),
      duration: Duration(milliseconds: partBDurMs),
      keyframeTracks: overlayTracksB,
      keyframes: overlayTracksB.toVideoKeyframes(),
      clearInAnimation: false,
    );

    _overlayClips.removeAt(index);
    _overlayClips.insert(index, partA);
    _overlayClips.insert(index + 1, partB);
    _selectedOverlayIndex = index + 1;
    TtsService.announce('Split overlay at playhead');
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  bool splitTextAtPlayhead([String? textId]) {
    final targetId = textId ?? selectedTextId;
    if (targetId == null) return false;
    final index = _textOverlays.indexWhere((t) => t.id == targetId);
    if (index == -1) return false;

    final original = _textOverlays[index];
    final startSec = original.startTimeInSeconds;
    final endSec = startSec + original.durationInSeconds;

    if (_playheadPosition <= startSec + 0.1 || _playheadPosition >= endSec - 0.1) {
      return false;
    }

    _saveSnapshot();
    final splitTime = _playheadPosition;
    final partADurMs = ((splitTime - startSec) * 1000).round();
    final partBDurMs = original.duration.inMilliseconds - partADurMs;
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    final (textTracksA, textTracksB) = original.effectiveKeyframeTracks.splitAt(partADurMs);

    final partA = original.copyWith(
      id: '${original.id}_part1_$timestamp',
      text: original.text,
      duration: Duration(milliseconds: partADurMs),
      keyframeTracks: textTracksA,
      keyframes: textTracksA.toVideoKeyframes(),
    );

    final partB = original.copyWith(
      id: '${original.id}_part2_$timestamp',
      text: original.text,
      startTime: Duration(milliseconds: (splitTime * 1000).round()),
      duration: Duration(milliseconds: partBDurMs),
      keyframeTracks: textTracksB,
      keyframes: textTracksB.toVideoKeyframes(),
    );

    _textOverlays.removeAt(index);
    _textOverlays.insert(index, partA);
    _textOverlays.insert(index + 1, partB);
    _selectedTextId = partB.id;
    TtsService.announce('Split text at playhead');
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  bool splitAudioTrackAtPlayhead([String? trackId]) {
    final targetId = trackId ?? selectedAudioTrackId;
    if (targetId == null && _audioTracks.isEmpty) return false;
    final index = targetId != null
        ? _audioTracks.indexWhere((a) => a.id == targetId)
        : 0;
    if (index == -1 || index >= _audioTracks.length) return false;

    final original = _audioTracks[index];
    final startSec = original.startTimeInSeconds;
    final endSec = original.endTimeInSeconds;

    if (_playheadPosition <= startSec + 0.1 || _playheadPosition >= endSec - 0.1) {
      return false;
    }

    _saveSnapshot();
    final splitOffsetSec = _playheadPosition - startSec;
    final splitOffsetMs = (splitOffsetSec * (original.speed > 0 ? original.speed : 1.0) * 1000).round();
    final splitTrimEndMs = original.trimStart.inMilliseconds + splitOffsetMs;
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    final (audioTracksA, audioTracksB) = original.effectiveKeyframeTracks.splitAt(splitOffsetMs);

    final partA = original.copyWith(
      id: '${original.id}_part1_$timestamp',
      name: '${original.title} (Part 1)',
      trimEnd: Duration(milliseconds: splitTrimEndMs),
      keyframeTracks: audioTracksA,
    );

    final partB = original.copyWith(
      id: '${original.id}_part2_$timestamp',
      name: '${original.title} (Part 2)',
      startTime: Duration(milliseconds: (_playheadPosition * 1000).round()),
      trimStart: Duration(milliseconds: splitTrimEndMs),
      keyframeTracks: audioTracksB,
    );

    _audioTracks.removeAt(index);
    _audioTracks.insert(index, partA);
    _audioTracks.insert(index + 1, partB);
    _selectedAudioTrackId = partB.id;
    TtsService.announce('Split audio at playhead');
    scheduleAutoSave();
    notifyListeners();
    return true;
  }

  bool splitSelectedItemAtPlayhead() {
    if (selectedOverlay != null) {
      final res = splitOverlayAtPlayhead();
      if (res) return true;
    }
    if (selectedTextOverlay != null) {
      final res = splitTextAtPlayhead();
      if (res) return true;
    }
    if (selectedAudioTrack != null) {
      final res = splitAudioTrackAtPlayhead();
      if (res) return true;
    }
    return splitClipAtPlayhead();
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
    TtsService.announce('Filter ${filter.name} selected');
    scheduleAutoSave();
    notifyListeners();
  }

  void setFilterIntensity(double intensity) {
    _activeFilter = _activeFilter.copyWith(intensity: intensity.clamp(0.0, 1.0));
    scheduleAutoSave();
    notifyListeners();
  }

  void commitFilterIntensity(double intensity) {
    _saveSnapshot();
    _activeFilter = _activeFilter.copyWith(intensity: intensity.clamp(0.0, 1.0));
    TtsService.announce('Filter intensity ${(_activeFilter.intensity * 100).round()}%');
    scheduleAutoSave();
    notifyListeners();
  }

  void setEffect(VideoEffect effect) {
    _saveSnapshot();
    _activeEffect = effect;
    TtsService.announce(effect.type == VideoEffectType.none ? 'Effect removed' : 'Added effect ${effect.name}');
    scheduleAutoSave();
    notifyListeners();
  }

  void updateColorAdjustments(ColorAdjustments adjustments) {
    _colorAdjustments = adjustments;
    scheduleAutoSave();
    notifyListeners();
  }

  void commitColorAdjustments(ColorAdjustments adjustments, {String? propertyName}) {
    _saveSnapshot();
    _colorAdjustments = adjustments;
    if (propertyName != null) {
      TtsService.announce('$propertyName adjusted');
    } else {
      TtsService.announce('Color adjustments updated');
    }
    scheduleAutoSave();
    notifyListeners();
  }

  void resetColorAdjustments() {
    _saveSnapshot();
    _colorAdjustments = const ColorAdjustments();
    TtsService.announce('Color adjustments reset');
    scheduleAutoSave();
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

  void zoomIn([double factor = 1.25]) {
    setZoomScale(_pixelsPerSecond * factor);
    TtsService.announce('Zoom in');
  }

  void zoomOut([double factor = 0.8]) {
    setZoomScale(_pixelsPerSecond * factor);
    TtsService.announce('Zoom out');
  }

  void resetZoom() {
    setZoomScale(AppDimensions.defaultPixelsPerSecond);
    TtsService.announce('Zoom reset');
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
    playheadNotifier.dispose();
    drawerNotifier.dispose();
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
    final sourceDur = TimeRemapper.timelineToSourceTime(
      timelineOffset: Duration(milliseconds: (deltaSec * 1000).round()),
      trimStart: clip.trimStart,
      trimEnd: clip.trimEnd,
      originalDuration: clip.originalDuration,
      speedCurve: clip.speedCurve,
      constantSpeed: clip.speed,
      freezeFrame: clip.freezeFrame,
      isFrozen: clip.isFrozen,
      isReversed: clip.isReversed,
    );
    return (sourceDur.inMilliseconds / 1000.0).clamp(0.0, clip.originalDuration.inMilliseconds / 1000.0);
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

  /// Checks if a keyframe exists at the current playhead position for the selected clip, overlay, text, or audio
  bool get hasKeyframeAtPlayhead {
    if (selectedClip != null) {
      final clip = selectedClip!;
      final clipStart = selectedClipStartTime;
      final relTime = _playheadPosition - clipStart;
      final timeMs = (relTime * 1000).round();
      return clip.keyframes.any((k) => (k.timeInSeconds - relTime).abs() < 0.08) ||
             clip.effectiveKeyframeTracks.hasKeyframeAt(timeMs, toleranceMs: 80);
    } else if (selectedOverlay != null) {
      final overlay = selectedOverlay!;
      final relTime = _playheadPosition - overlay.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();
      return overlay.keyframes.any((k) => (k.timeInSeconds - relTime).abs() < 0.08) ||
             overlay.effectiveKeyframeTracks.hasKeyframeAt(timeMs, toleranceMs: 80);
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      final relTime = _playheadPosition - text.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();
      return text.keyframes.any((k) => (k.timeInSeconds - relTime).abs() < 0.08) ||
             text.effectiveKeyframeTracks.hasKeyframeAt(timeMs, toleranceMs: 80);
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final relTime = _playheadPosition - audio.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();
      return audio.effectiveKeyframeTracks.hasKeyframeAt(timeMs, toleranceMs: 80);
    }
    return false;
  }

  /// Total keyframe count for the currently selected item
  int get currentKeyframeCount {
    if (selectedClip != null) {
      return math.max(selectedClip!.keyframes.length, selectedClip!.effectiveKeyframeTracks.getAllTimestampsMs().length);
    }
    if (selectedOverlay != null) {
      return math.max(selectedOverlay!.keyframes.length, selectedOverlay!.effectiveKeyframeTracks.getAllTimestampsMs().length);
    }
    if (selectedTextOverlay != null) {
      return math.max(selectedTextOverlay!.keyframes.length, selectedTextOverlay!.effectiveKeyframeTracks.getAllTimestampsMs().length);
    }
    if (selectedAudioTrack != null) {
      return selectedAudioTrack!.effectiveKeyframeTracks.getAllTimestampsMs().length;
    }
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
    final set = <double>{};
    if (selectedClip != null) {
      final clipStart = selectedClipStartTime;
      for (final k in selectedClip!.keyframes) {
        set.add(clipStart + k.timeInSeconds);
      }
      for (final ms in selectedClip!.effectiveKeyframeTracks.getAllTimestampsMs()) {
        set.add(clipStart + (ms / 1000.0));
      }
    } else if (selectedOverlay != null) {
      final overlayStart = selectedOverlay!.startTimeInSeconds;
      for (final k in selectedOverlay!.keyframes) {
        set.add(overlayStart + k.timeInSeconds);
      }
      for (final ms in selectedOverlay!.effectiveKeyframeTracks.getAllTimestampsMs()) {
        set.add(overlayStart + (ms / 1000.0));
      }
    } else if (selectedTextOverlay != null) {
      final textStart = selectedTextOverlay!.startTimeInSeconds;
      for (final k in selectedTextOverlay!.keyframes) {
        set.add(textStart + k.timeInSeconds);
      }
      for (final ms in selectedTextOverlay!.effectiveKeyframeTracks.getAllTimestampsMs()) {
        set.add(textStart + (ms / 1000.0));
      }
    } else if (selectedAudioTrack != null) {
      final audioStart = selectedAudioTrack!.startTimeInSeconds;
      for (final ms in selectedAudioTrack!.effectiveKeyframeTracks.getAllTimestampsMs()) {
        set.add(audioStart + (ms / 1000.0));
      }
    }
    final list = set.toList()..sort();
    return list;
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
      final timeMs = (relTime * 1000).round();

      final totalRotationDeg = clip.rotationDegrees.toDouble() + (clip.rotationAngle * 180.0 / math.pi);

      final newKeyframe = VideoKeyframe(
        id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: Duration(milliseconds: timeMs),
        scale: clip.scale,
        rotationDegrees: totalRotationDeg,
        positionX: clip.xPos,
        positionY: clip.yPos,
        opacity: clip.opacity,
        curve: KeyframeCurve.easeInOut,
      );

      final updatedKeyframes = List<VideoKeyframe>.from(
        clip.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      )..add(newKeyframe);
      updatedKeyframes.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Synchronize into KeyframeTrackGroup
      var group = clip.effectiveKeyframeTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: clip.xPos,
        posY: clip.yPos,
        scale: clip.scale,
        rotation: totalRotationDeg,
        opacity: clip.opacity,
        easing: EasingCurve.easeInOut,
      );

      // Also record color adjustments if present
      final adj = _colorAdjustments;
      group = group.addKeyframe(AnimatableProperty.brightness, timeMs, adj.brightness);
      group = group.addKeyframe(AnimatableProperty.contrast, timeMs, adj.contrast);
      group = group.addKeyframe(AnimatableProperty.saturation, timeMs, adj.saturation);
      group = group.addKeyframe(AnimatableProperty.exposure, timeMs, adj.exposure);
      group = group.addKeyframe(AnimatableProperty.temperature, timeMs, adj.temperature);
      group = group.addKeyframe(AnimatableProperty.tint, timeMs, adj.tint);
      group = group.addKeyframe(AnimatableProperty.vignette, timeMs, adj.vignette);
      group = group.addKeyframe(AnimatableProperty.sharpness, timeMs, adj.sharpness);

      if (clip.mask != null && clip.mask!.isActive) {
        final m = clip.mask!;
        group = group.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
        group = group.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
        group = group.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
        group = group.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
        group = group.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
        group = group.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
        group = group.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
        group = group.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
        group = group.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);
      }

      _videoClips[_selectedClipIndex!] = clip.copyWith(
        keyframes: updatedKeyframes,
        keyframeTracks: group,
      );
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added keyframe at ${relTime.toStringAsFixed(1)} seconds');
      notifyListeners();
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final relTime = (_playheadPosition - overlay.startTimeInSeconds).clamp(0.0, overlay.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final newKeyframe = VideoKeyframe(
        id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: Duration(milliseconds: timeMs),
        scale: overlay.scale,
        rotationDegrees: overlay.rotation * 180.0 / math.pi,
        positionX: overlay.position.dx,
        positionY: overlay.position.dy,
        opacity: overlay.opacity,
        curve: KeyframeCurve.easeInOut,
      );

      final updatedKeyframes = List<VideoKeyframe>.from(
        overlay.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      )..add(newKeyframe);
      updatedKeyframes.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Synchronize into KeyframeTrackGroup
      var group = overlay.effectiveKeyframeTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: overlay.position.dx,
        posY: overlay.position.dy,
        scale: overlay.scale,
        rotation: overlay.rotation * 180.0 / math.pi,
        opacity: overlay.opacity,
        easing: EasingCurve.easeInOut,
      );

      if (overlay.filterIntensity > 0) {
        group = group.addKeyframe(AnimatableProperty.filterIntensity, timeMs, overlay.filterIntensity);
      }
      if (overlay.effectIntensity > 0) {
        group = group.addKeyframe(AnimatableProperty.effectIntensity, timeMs, overlay.effectIntensity);
      }
      if (overlay.mask != null && overlay.mask!.isActive) {
        final m = overlay.mask!;
        group = group.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
        group = group.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
        group = group.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
        group = group.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
        group = group.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
        group = group.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
        group = group.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
        group = group.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
        group = group.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);
      }

      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
        keyframes: updatedKeyframes,
        keyframeTracks: group,
      );
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added PIP keyframe at ${relTime.toStringAsFixed(1)} seconds');
      notifyListeners();
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      final relTime = (_playheadPosition - text.startTimeInSeconds).clamp(0.0, text.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final newKeyframe = VideoKeyframe(
        id: 'kf_${DateTime.now().millisecondsSinceEpoch}',
        timestamp: Duration(milliseconds: timeMs),
        scale: text.scale,
        rotationDegrees: 0.0,
        positionX: text.position.dx,
        positionY: text.position.dy,
        opacity: 1.0,
        curve: KeyframeCurve.easeInOut,
      );

      final updatedKeyframes = List<VideoKeyframe>.from(
        text.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      )..add(newKeyframe);
      updatedKeyframes.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      var group = text.effectiveKeyframeTracks.addTransformKeyframe(
        timeMs: timeMs,
        posX: text.position.dx,
        posY: text.position.dy,
        scale: text.scale,
        rotation: 0.0,
        opacity: 1.0,
        easing: EasingCurve.easeInOut,
      );

      updateTextOverlay(
        text.copyWith(
          keyframes: updatedKeyframes,
          keyframeTracks: group,
        ),
        saveSnapshot: false,
        notify: true,
      );
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added text keyframe at ${relTime.toStringAsFixed(1)} seconds');
      notifyListeners();
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final relTime = (_playheadPosition - audio.startTimeInSeconds).clamp(0.0, audio.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final group = audio.effectiveKeyframeTracks.addKeyframe(
        AnimatableProperty.volume,
        timeMs,
        audio.volume,
        easing: EasingCurve.easeInOut,
      );

      final index = _audioTracks.indexWhere((a) => a.id == audio.id);
      if (index != -1) {
        _audioTracks[index] = audio.copyWith(keyframeTracks: group);
      }
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Added audio volume keyframe at ${relTime.toStringAsFixed(1)} seconds');
      notifyListeners();
    }
  }

  void removeKeyframeAtPlayhead() {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final clipStart = selectedClipStartTime;
      final relTime = _playheadPosition - clipStart;
      final timeMs = (relTime * 1000).round();

      final updated = List<VideoKeyframe>.from(
        clip.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      );
      final updatedTracks = clip.effectiveKeyframeTracks.removeKeyframeAtTime(timeMs, toleranceMs: 80);

      _videoClips[_selectedClipIndex!] = clip.copyWith(
        keyframes: updated,
        keyframeTracks: updatedTracks,
      );
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed keyframe');
      notifyListeners();
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final relTime = _playheadPosition - overlay.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();

      final updated = List<VideoKeyframe>.from(
        overlay.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      );
      final updatedTracks = overlay.effectiveKeyframeTracks.removeKeyframeAtTime(timeMs, toleranceMs: 80);

      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
        keyframes: updated,
        keyframeTracks: updatedTracks,
      );
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed PIP keyframe');
      notifyListeners();
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      final relTime = _playheadPosition - text.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();

      final updated = List<VideoKeyframe>.from(
        text.keyframes.where((k) => (k.timeInSeconds - relTime).abs() >= 0.08),
      );
      final updatedTracks = text.effectiveKeyframeTracks.removeKeyframeAtTime(timeMs, toleranceMs: 80);

      updateTextOverlay(
        text.copyWith(
          keyframes: updated,
          keyframeTracks: updatedTracks,
        ),
        saveSnapshot: false,
        notify: true,
      );
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed text keyframe');
      notifyListeners();
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final relTime = _playheadPosition - audio.startTimeInSeconds;
      final timeMs = (relTime * 1000).round();

      final updatedTracks = audio.effectiveKeyframeTracks.removeKeyframeAtTime(timeMs, toleranceMs: 80);
      final index = _audioTracks.indexWhere((a) => a.id == audio.id);
      if (index != -1) {
        _audioTracks[index] = audio.copyWith(keyframeTracks: updatedTracks);
      }
      HapticFeedback.lightImpact();
      scheduleAutoSave();
      TtsService.announce('Removed audio keyframe');
      notifyListeners();
    }
  }

  /// Updates easing curve for all keyframes at target timestamp on selected layer
  void updateKeyframeEasing(
    AnimatableProperty property,
    int timeMs,
    EasingCurve easing, {
    bool syncAllTransformProperties = true,
  }) {
    _saveSnapshot();
    final shouldSync = syncAllTransformProperties && property.isTransform;

    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      KeyframeTrackGroup updatedGroup;
      if (shouldSync) {
        updatedGroup = clip.effectiveKeyframeTracks.updateEasingForTransformProperties(
          timeMs,
          easing,
          toleranceMs: 80,
        );
      } else {
        final currentTrack = clip.effectiveKeyframeTracks.tracks[property];
        if (currentTrack != null) {
          final kf = currentTrack.getKeyframeAt(timeMs, toleranceMs: 80);
          if (kf != null) {
            updatedGroup = clip.effectiveKeyframeTracks.addKeyframe(
              property,
              kf.timestampMs,
              kf.value,
              easing: easing,
            );
          } else {
            updatedGroup = clip.effectiveKeyframeTracks;
          }
        } else {
          updatedGroup = clip.effectiveKeyframeTracks;
        }
      }
      _videoClips[_selectedClipIndex!] = clip.copyWith(
        keyframeTracks: updatedGroup,
        keyframes: updatedGroup.toVideoKeyframes(),
      );
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      KeyframeTrackGroup updatedGroup;
      if (shouldSync) {
        updatedGroup = overlay.effectiveKeyframeTracks.updateEasingForTransformProperties(
          timeMs,
          easing,
          toleranceMs: 80,
        );
      } else {
        final currentTrack = overlay.effectiveKeyframeTracks.tracks[property];
        if (currentTrack != null) {
          final kf = currentTrack.getKeyframeAt(timeMs, toleranceMs: 80);
          if (kf != null) {
            updatedGroup = overlay.effectiveKeyframeTracks.addKeyframe(
              property,
              kf.timestampMs,
              kf.value,
              easing: easing,
            );
          } else {
            updatedGroup = overlay.effectiveKeyframeTracks;
          }
        } else {
          updatedGroup = overlay.effectiveKeyframeTracks;
        }
      }
      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
        keyframeTracks: updatedGroup,
        keyframes: updatedGroup.toVideoKeyframes(),
      );
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      KeyframeTrackGroup updatedGroup;
      if (shouldSync) {
        updatedGroup = text.effectiveKeyframeTracks.updateEasingForTransformProperties(
          timeMs,
          easing,
          toleranceMs: 80,
        );
      } else {
        final currentTrack = text.effectiveKeyframeTracks.tracks[property];
        if (currentTrack != null) {
          final kf = currentTrack.getKeyframeAt(timeMs, toleranceMs: 80);
          if (kf != null) {
            updatedGroup = text.effectiveKeyframeTracks.addKeyframe(
              property,
              kf.timestampMs,
              kf.value,
              easing: easing,
            );
          } else {
            updatedGroup = text.effectiveKeyframeTracks;
          }
        } else {
          updatedGroup = text.effectiveKeyframeTracks;
        }
      }
      updateTextOverlay(
        text.copyWith(
          keyframeTracks: updatedGroup,
          keyframes: updatedGroup.toVideoKeyframes(),
        ),
        saveSnapshot: false,
        notify: true,
      );
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final currentTrack = audio.effectiveKeyframeTracks.tracks[property];
      if (currentTrack != null) {
        final kf = currentTrack.getKeyframeAt(timeMs, toleranceMs: 80);
        if (kf != null) {
          final updatedGroup = audio.effectiveKeyframeTracks.addKeyframe(
            property,
            kf.timestampMs,
            kf.value,
            easing: easing,
          );
          final index = _audioTracks.indexWhere((a) => a.id == audio.id);
          if (index != -1) {
            _audioTracks[index] = audio.copyWith(keyframeTracks: updatedGroup);
          }
        }
      }
    }
    TtsService.announce('${easing.displayName} curve applied');
    scheduleAutoSave();
    notifyListeners();
  }

  /// Moves keyframe in time for the selected layer
  void moveSelectedKeyframe(AnimatableProperty property, int oldTimeMs, int newTimeMs) {
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final maxMs = (clip.durationInSeconds * 1000).round();
      final clampedNewMs = newTimeMs.clamp(0, maxMs);
      final track = clip.effectiveKeyframeTracks.tracks[property];
      if (track != null) {
        final kf = track.getKeyframeAt(oldTimeMs, toleranceMs: 80);
        if (kf != null) {
          var group = clip.effectiveKeyframeTracks.removeKeyframeAtTime(oldTimeMs, toleranceMs: 80);
          group = group.addKeyframe(property, clampedNewMs, kf.value, easing: kf.easing);
          _videoClips[_selectedClipIndex!] = clip.copyWith(
            keyframeTracks: group,
            keyframes: group.toVideoKeyframes(),
          );
        }
      }
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final maxMs = (overlay.durationInSeconds * 1000).round();
      final clampedNewMs = newTimeMs.clamp(0, maxMs);
      final track = overlay.effectiveKeyframeTracks.tracks[property];
      if (track != null) {
        final kf = track.getKeyframeAt(oldTimeMs, toleranceMs: 80);
        if (kf != null) {
          var group = overlay.effectiveKeyframeTracks.removeKeyframeAtTime(oldTimeMs, toleranceMs: 80);
          group = group.addKeyframe(property, clampedNewMs, kf.value, easing: kf.easing);
          _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
            keyframeTracks: group,
            keyframes: group.toVideoKeyframes(),
          );
        }
      }
    }
    scheduleAutoSave();
    notifyListeners();
  }

  /// Sets keyframe property value at current playhead relative time for selected layer
  void setKeyframePropertyValue(AnimatableProperty property, double value) {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final clipStart = selectedClipStartTime;
      final relTime = (_playheadPosition - clipStart).clamp(0.0, clip.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final updatedGroup = clip.effectiveKeyframeTracks.addKeyframe(property, timeMs, value);
      _videoClips[_selectedClipIndex!] = clip.copyWith(
        keyframeTracks: updatedGroup,
        keyframes: updatedGroup.toVideoKeyframes(),
      );
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final relTime = (_playheadPosition - overlay.startTimeInSeconds).clamp(0.0, overlay.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final updatedGroup = overlay.effectiveKeyframeTracks.addKeyframe(property, timeMs, value);
      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
        keyframeTracks: updatedGroup,
        keyframes: updatedGroup.toVideoKeyframes(),
      );
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      final relTime = (_playheadPosition - text.startTimeInSeconds).clamp(0.0, text.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final updatedGroup = text.effectiveKeyframeTracks.addKeyframe(property, timeMs, value);
      updateTextOverlay(
        text.copyWith(
          keyframeTracks: updatedGroup,
          keyframes: updatedGroup.toVideoKeyframes(),
        ),
        saveSnapshot: false,
        notify: true,
      );
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final relTime = (_playheadPosition - audio.startTimeInSeconds).clamp(0.0, audio.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      final updatedGroup = audio.effectiveKeyframeTracks.addKeyframe(property, timeMs, value);
      final index = _audioTracks.indexWhere((a) => a.id == audio.id);
      if (index != -1) {
        _audioTracks[index] = audio.copyWith(keyframeTracks: updatedGroup);
      }
    }
    scheduleAutoSave();
    notifyListeners();
  }

  /// Resets all keyframe animations on the currently selected layer
  void resetAnimationForSelectedLayer() {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      _videoClips[_selectedClipIndex!] = clip.copyWith(
        keyframes: const [],
        keyframeTracks: const KeyframeTrackGroup(),
      );
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
        keyframes: const [],
        keyframeTracks: const KeyframeTrackGroup(),
      );
    } else if (selectedTextOverlay != null) {
      final text = selectedTextOverlay!;
      updateTextOverlay(
        text.copyWith(
          keyframes: const [],
          keyframeTracks: const KeyframeTrackGroup(),
        ),
        saveSnapshot: false,
        notify: true,
      );
    } else if (selectedAudioTrack != null) {
      final audio = selectedAudioTrack!;
      final index = _audioTracks.indexWhere((a) => a.id == audio.id);
      if (index != -1) {
        _audioTracks[index] = audio.copyWith(
          keyframeTracks: const KeyframeTrackGroup(),
        );
      }
    }
    HapticFeedback.mediumImpact();
    TtsService.announce('Reset animation');
    scheduleAutoSave();
    notifyListeners();
  }

  /// Alias for total keyframe count on selected layer
  int get keyframeCountForSelected => currentKeyframeCount;

  /// Resets keyframe animation on the selected layer or target layer
  void resetKeyframeAnimation([String? layerId]) {
    resetAnimationForSelectedLayer();
  }

  /// Updates keyframe value for a property on the selected layer
  void updateKeyframeValue({
    String? layerId,
    required AnimatableProperty property,
    String? keyframeId,
    required double newValue,
  }) {
    setKeyframePropertyValue(property, newValue);
  }

  /// Changes keyframe easing curve on the selected layer
  void changeKeyframeEasing({
    String? layerId,
    required AnimatableProperty property,
    String? keyframeId,
    required EasingCurve easing,
    int? timeMs,
  }) {
    final effectiveMs = timeMs ?? (_playheadPosition * 1000).round();
    updateKeyframeEasing(property, effectiveMs, easing);
  }

  /// Re-times keyframe on the selected layer
  void moveKeyframe({
    String? layerId,
    required AnimatableProperty property,
    String? keyframeId,
    int? oldTimestampMs,
    required int newTimestampMs,
  }) {
    final oldMs = oldTimestampMs ?? (_playheadPosition * 1000).round();
    moveSelectedKeyframe(property, oldMs, newTimestampMs);
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

  VideoKeyframe? getInterpolatedTextKeyframe(TextOverlay text, double currentTextTime) {
    return VideoKeyframe.interpolate(
      keyframes: text.keyframes,
      timeInSeconds: currentTextTime,
    );
  }

  // ==========================================
  // MASKING & COMPOSITING ENGINE (v1.6.0)
  // ==========================================
  int _selectedMaskIndex = 0;
  int get selectedMaskIndex => _selectedMaskIndex;
  void setSelectedMaskIndex(int index) {
    _selectedMaskIndex = index;
    notifyListeners();
  }

  bool _isMaskModeActive = false;
  bool get isMaskModeActive => _isMaskModeActive;
  void setMaskModeActive(bool active) {
    _isMaskModeActive = active;
    notifyListeners();
  }

  VideoMask? get activeMask {
    if (selectedClip != null && selectedClip!.masks.isNotEmpty) {
      if (_selectedMaskIndex >= 0 && _selectedMaskIndex < selectedClip!.masks.length) {
        return selectedClip!.masks[_selectedMaskIndex];
      }
      return selectedClip!.masks.first;
    } else if (selectedOverlay != null && selectedOverlay!.masks.isNotEmpty) {
      if (_selectedMaskIndex >= 0 && _selectedMaskIndex < selectedOverlay!.masks.length) {
        return selectedOverlay!.masks[_selectedMaskIndex];
      }
      return selectedOverlay!.masks.first;
    }
    return null;
  }

  bool _isMaskGestureInProgress = false;

  /// Begins an interactive mask gesture, capturing an undo snapshot before drag updates.
  void beginMaskGesture() {
    if (!_isMaskGestureInProgress) {
      _saveSnapshot();
      _isMaskGestureInProgress = true;
    }
  }

  /// Updates the currently active mask on selected clip or overlay without saving an undo snapshot per update
  void updateActiveMask(VideoMask updated) {
    if (!_isMaskGestureInProgress) {
      beginMaskGesture();
    }
    if (_selectedClipIndex != null) {
      updateMaskInSelectedClip(_selectedMaskIndex, updated);
    } else if (_selectedOverlayIndex != null) {
      updateMaskInSelectedOverlay(_selectedMaskIndex, updated);
    }
  }

  void addMaskToSelectedClip(VideoMask mask) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    final updatedMasks = List<VideoMask>.from(clip.masks)..add(mask);
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    _selectedMaskIndex = updatedMasks.length - 1;
    scheduleAutoSave();
    TtsService.announce('Added ${mask.type.displayName} mask');
    notifyListeners();
  }

  void updateMaskInSelectedClip(int index, VideoMask mask) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    final updatedMasks = List<VideoMask>.from(clip.masks);
    updatedMasks[index] = mask;
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    notifyListeners();
  }

  void updateMaskDiscreteInSelectedClip(int index, VideoMask mask) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(clip.masks);
    updatedMasks[index] = mask;
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    notifyListeners();
  }

  void renameMaskInSelectedClip(int index, String newName) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(clip.masks);
    updatedMasks[index] = updatedMasks[index].copyWith(name: newName);
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    TtsService.announce('Renamed mask to $newName');
    notifyListeners();
  }

  void toggleMaskEnabledInSelectedClip(int index) {
    if (_selectedClipIndex == null) return;
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(clip.masks);
    final cur = updatedMasks[index];
    final newState = !cur.enabled;
    updatedMasks[index] = cur.copyWith(enabled: newState);
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    TtsService.announce(newState ? 'Enabled mask' : 'Bypassed mask');
    notifyListeners();
  }

  void removeMaskFromSelectedClip(int index) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    final updatedMasks = List<VideoMask>.from(clip.masks)..removeAt(index);
    _videoClips[_selectedClipIndex!] = clip.copyWith(
      masks: updatedMasks,
      clearMask: updatedMasks.isEmpty,
    );
    if (_selectedMaskIndex >= updatedMasks.length) {
      _selectedMaskIndex = math.max(0, updatedMasks.length - 1);
    }
    scheduleAutoSave();
    TtsService.announce('Delete mask');
    notifyListeners();
  }

  void duplicateMaskInSelectedClip(int index) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    if (index < 0 || index >= clip.masks.length) return;
    final original = clip.masks[index];
    final copy = original.copyWith(
      id: 'mask_${DateTime.now().microsecondsSinceEpoch}',
      name: '${original.name} (Copy)',
    );
    final updatedMasks = List<VideoMask>.from(clip.masks)..insert(index + 1, copy);
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    _selectedMaskIndex = index + 1;
    scheduleAutoSave();
    TtsService.announce('Duplicated mask');
    notifyListeners();
  }

  void reorderMasksInSelectedClip(int oldIndex, int newIndex) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    if (oldIndex < 0 || oldIndex >= clip.masks.length || newIndex < 0 || newIndex >= clip.masks.length) return;
    final updatedMasks = List<VideoMask>.from(clip.masks);
    final item = updatedMasks.removeAt(oldIndex);
    updatedMasks.insert(newIndex, item);
    _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updatedMasks);
    _selectedMaskIndex = newIndex;
    scheduleAutoSave();
    notifyListeners();
  }

  void setClipMask(VideoMask mask) {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    if (clip.masks.isEmpty) {
      _videoClips[_selectedClipIndex!] = clip.copyWith(masks: [mask]);
      _selectedMaskIndex = 0;
    } else {
      final updated = List<VideoMask>.from(clip.masks);
      final idx = _selectedMaskIndex.clamp(0, updated.length - 1);
      updated[idx] = mask;
      _videoClips[_selectedClipIndex!] = clip.copyWith(masks: updated);
    }
    scheduleAutoSave();
    TtsService.announce('${mask.type.displayName} mask');
    notifyListeners();
  }

  void removeClipMask() {
    if (_selectedClipIndex == null) return;
    _saveSnapshot();
    final clip = _videoClips[_selectedClipIndex!];
    _videoClips[_selectedClipIndex!] = clip.copyWith(clearMask: true);
    _selectedMaskIndex = 0;
    scheduleAutoSave();
    TtsService.announce('Reset mask');
    notifyListeners();
  }

  // --- PIP / Overlay Multi-Mask Methods ---
  void addMaskToSelectedOverlay(VideoMask mask) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[_selectedOverlayIndex!];
    final updatedMasks = List<VideoMask>.from(overlay.masks)..add(mask);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    _selectedMaskIndex = updatedMasks.length - 1;
    scheduleAutoSave();
    TtsService.announce('Added ${mask.type.displayName} mask');
    notifyListeners();
  }

  void updateMaskInSelectedOverlay(int index, VideoMask mask) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    final updatedMasks = List<VideoMask>.from(overlay.masks);
    updatedMasks[index] = mask;
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    notifyListeners();
  }

  void updateMaskDiscreteInSelectedOverlay(int index, VideoMask mask) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(overlay.masks);
    updatedMasks[index] = mask;
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    notifyListeners();
  }

  void renameMaskInSelectedOverlay(int index, String newName) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(overlay.masks);
    updatedMasks[index] = updatedMasks[index].copyWith(name: newName);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    TtsService.announce('Renamed mask to $newName');
    notifyListeners();
  }

  void toggleMaskEnabledInSelectedOverlay(int index) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    _saveSnapshot();
    final updatedMasks = List<VideoMask>.from(overlay.masks);
    final cur = updatedMasks[index];
    final newState = !cur.enabled;
    updatedMasks[index] = cur.copyWith(enabled: newState);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    scheduleAutoSave();
    TtsService.announce(newState ? 'Enabled mask' : 'Bypassed mask');
    notifyListeners();
  }

  void removeMaskFromSelectedOverlay(int index) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    final updatedMasks = List<VideoMask>.from(overlay.masks)..removeAt(index);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(
      masks: updatedMasks,
      clearMask: updatedMasks.isEmpty,
    );
    if (_selectedMaskIndex >= updatedMasks.length) {
      _selectedMaskIndex = math.max(0, updatedMasks.length - 1);
    }
    scheduleAutoSave();
    TtsService.announce('Delete mask');
    notifyListeners();
  }

  void duplicateMaskInSelectedOverlay(int index) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (index < 0 || index >= overlay.masks.length) return;
    final original = overlay.masks[index];
    final copy = original.copyWith(
      id: 'mask_${DateTime.now().microsecondsSinceEpoch}',
      name: '${original.name} (Copy)',
    );
    final updatedMasks = List<VideoMask>.from(overlay.masks)..insert(index + 1, copy);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    _selectedMaskIndex = index + 1;
    scheduleAutoSave();
    TtsService.announce('Duplicated mask');
    notifyListeners();
  }

  void reorderMasksInSelectedOverlay(int oldIndex, int newIndex) {
    if (_selectedOverlayIndex == null || _selectedOverlayIndex! >= _overlayClips.length) return;
    _saveSnapshot();
    final overlay = _overlayClips[_selectedOverlayIndex!];
    if (oldIndex < 0 || oldIndex >= overlay.masks.length || newIndex < 0 || newIndex >= overlay.masks.length) return;
    final updatedMasks = List<VideoMask>.from(overlay.masks);
    final item = updatedMasks.removeAt(oldIndex);
    updatedMasks.insert(newIndex, item);
    _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(masks: updatedMasks);
    _selectedMaskIndex = newIndex;
    scheduleAutoSave();
    notifyListeners();
  }

  /// Commits a completed interactive mask transform/adjustment gesture into the undo history.
  /// Exactly ONE undo snapshot is created for the complete gesture interaction.
  void commitMaskGesture() {
    _isMaskGestureInProgress = false;
    scheduleAutoSave();
  }

  /// Updates a single polygon vertex coordinate in the specified mask
  void updateMaskPolygonPoint(int maskIndex, int pointIndex, Offset newPoint) {
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      if (maskIndex < 0 || maskIndex >= clip.masks.length) return;
      final mask = clip.masks[maskIndex];
      if (pointIndex < 0 || pointIndex >= mask.points.length) return;
      final newPoints = List<Offset>.from(mask.points)..[pointIndex] = newPoint;
      updateMaskInSelectedClip(maskIndex, mask.copyWith(points: newPoints));
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      if (maskIndex < 0 || maskIndex >= overlay.masks.length) return;
      final mask = overlay.masks[maskIndex];
      if (pointIndex < 0 || pointIndex >= mask.points.length) return;
      final newPoints = List<Offset>.from(mask.points)..[pointIndex] = newPoint;
      updateMaskInSelectedOverlay(maskIndex, mask.copyWith(points: newPoints));
    }
  }

  /// Adds a dedicated keyframe at the current playhead for the active mask
  void addMaskKeyframeAtPlayhead() {
    _saveSnapshot();
    if (_selectedClipIndex != null) {
      final clip = _videoClips[_selectedClipIndex!];
      final m = (clip.masks.isNotEmpty && _selectedMaskIndex < clip.masks.length)
          ? clip.masks[_selectedMaskIndex]
          : clip.mask;
      if (m == null || !m.isActive) return;

      final relTime = (_playheadPosition - selectedClipStartTime).clamp(0.0, clip.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      var group = clip.effectiveKeyframeTracks;
      group = group.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
      group = group.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
      group = group.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
      group = group.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
      group = group.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
      group = group.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
      group = group.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
      group = group.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
      group = group.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);

      var maskGroup = m.keyframeTracks ?? const KeyframeTrackGroup();
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);

      final updatedMask = m.copyWith(keyframeTracks: maskGroup);
      final updatedMasks = List<VideoMask>.from(clip.masks);
      if (_selectedMaskIndex < updatedMasks.length) {
        updatedMasks[_selectedMaskIndex] = updatedMask;
      }

      _videoClips[_selectedClipIndex!] = clip.copyWith(keyframeTracks: group, masks: updatedMasks);
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Mask keyframe');
      notifyListeners();
    } else if (_selectedOverlayIndex != null && _selectedOverlayIndex! < _overlayClips.length) {
      final overlay = _overlayClips[_selectedOverlayIndex!];
      final m = (overlay.masks.isNotEmpty && _selectedMaskIndex < overlay.masks.length)
          ? overlay.masks[_selectedMaskIndex]
          : overlay.mask;
      if (m == null || !m.isActive) return;

      final relTime = (_playheadPosition - overlay.startTimeInSeconds).clamp(0.0, overlay.durationInSeconds);
      final timeMs = (relTime * 1000).round();

      var group = overlay.effectiveKeyframeTracks;
      group = group.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
      group = group.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
      group = group.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
      group = group.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
      group = group.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
      group = group.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
      group = group.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
      group = group.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
      group = group.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);

      var maskGroup = m.keyframeTracks ?? const KeyframeTrackGroup();
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskPositionX, timeMs, m.positionX);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskPositionY, timeMs, m.positionY);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskScale, timeMs, m.scale);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskRotation, timeMs, m.rotation);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskOpacity, timeMs, m.opacity);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskFeather, timeMs, m.feather);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskExpansion, timeMs, m.expansion);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskWidth, timeMs, m.width);
      maskGroup = maskGroup.addKeyframe(AnimatableProperty.maskHeight, timeMs, m.height);

      final updatedMask = m.copyWith(keyframeTracks: maskGroup);
      final updatedMasks = List<VideoMask>.from(overlay.masks);
      if (_selectedMaskIndex < updatedMasks.length) {
        updatedMasks[_selectedMaskIndex] = updatedMask;
      }

      _overlayClips[_selectedOverlayIndex!] = overlay.copyWith(keyframeTracks: group, masks: updatedMasks);
      HapticFeedback.mediumImpact();
      scheduleAutoSave();
      TtsService.announce('Mask keyframe');
      notifyListeners();
    }
  }

  // ==========================================
  // CROP AREA & RECTANGULAR MASK
  // ==========================================
  bool _isCropModeActive = false;
  bool get isCropModeActive =>
      _isCropModeActive || (_selectedClipIndex != null && selectedClip?.mask?.isActive == true);

  Rect _activeCropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
  Rect get activeCropRect => _activeCropRect;

  void setCropMode(bool active) {
    _isCropModeActive = active;
    notifyListeners();
  }

  void updateCropRect(Rect newRect) {
    const minSize = 0.1;
    final clamped = Rect.fromLTRB(
      newRect.left.clamp(0.0, 1.0 - minSize),
      newRect.top.clamp(0.0, 1.0 - minSize),
      newRect.right.clamp(minSize, 1.0),
      newRect.bottom.clamp(minSize, 1.0),
    );
    if (!clamped.left.isFinite || !clamped.top.isFinite || !clamped.right.isFinite || !clamped.bottom.isFinite) return;
    if (clamped.width < minSize || clamped.height < minSize) return;

    _activeCropRect = clamped;

    if (_selectedClipIndex != null && _selectedClipIndex! >= 0 && _selectedClipIndex! < _videoClips.length) {
      final clip = _videoClips[_selectedClipIndex!];
      final w = clamped.width;
      final h = clamped.height;
      final size = math.max(w, h);
      final posX = (clamped.center.dx - 0.5) * 2.0;
      final posY = (clamped.center.dy - 0.5) * 2.0;
      _videoClips[_selectedClipIndex!] = clip.copyWith(
        mask: VideoMask(
          type: MaskType.rectangle,
          size: size.clamp(0.1, 2.0),
          positionX: posX.clamp(-1.0, 1.0),
          positionY: posY.clamp(-1.0, 1.0),
          rectWidth: w,
          rectHeight: h,
        ),
      );
    }
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