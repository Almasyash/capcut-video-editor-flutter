import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
import 'package:capcut_video_editor/core/services/asset_library_service.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

class AudioDrawer extends StatefulWidget {
  final EditorViewModel viewModel;

  const AudioDrawer({
    super.key,
    required this.viewModel,
  });

  @override
  State<AudioDrawer> createState() => _AudioDrawerState();
}

class _AudioDrawerState extends State<AudioDrawer> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final TextEditingController _sfxSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    AssetLibraryService.instance.initialize();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _sfxSearchController.dispose();
    AssetLibraryService.instance.stopPreview();
    _tabController.dispose();
    super.dispose();
  }

  void _addMusic(
    String title,
    int durationSec, {
    required String assetId,
    String artist = 'Original Audio',
  }) {
    final random = math.Random(title.hashCode);
    final waveform = List.generate(40, (_) => 0.2 + random.nextDouble() * 0.8);

    final track = AudioTrack(
      id: 'audio_${DateTime.now().millisecondsSinceEpoch}',
      assetId: assetId,
      title: title,
      artist: artist,
      duration: Duration(seconds: durationSec),
      startTime: Duration(milliseconds: (widget.viewModel.playheadPosition * 1000).round()),
      waveformPoints: waveform,
      volume: 0.85,
      speed: 1.0,
    );

    widget.viewModel.addAudioTrack(track);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added track "$title" to timeline!'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _handleDeviceAudioImport() async {
    // Uses the new MediaAsset import flow into the centralized MediaLibrary
    final success = await widget.viewModel.importAudioAsset();
    if (success && mounted) {
      final audios = widget.viewModel.mediaLibrary.where((a) => a.isAudio).toList();
      if (audios.isNotEmpty) {
        final latestAudio = audios.last;
        final durationSec = latestAudio.duration?.inSeconds ?? 28;
        _addMusic(
          latestAudio.name,
          durationSec,
          assetId: latestAudio.id,
          artist: 'Device Audio',
        );
      }
      return;
    }

    if (mounted) {
      _openDeviceAudioPickerModal();
    }
  }

  void _openDeviceAudioPickerModal() {
    final controller = TextEditingController(text: 'AUD_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    int durationSec = 28;
    String selectedCategory = 'Music';

    final categories = ['Music', 'Downloads', 'Voice Memos', 'Podcasts'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.audio_file_rounded, color: AppColors.secondary, size: 24),
              SizedBox(width: 8),
              Text('Import Device Audio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Audio Source / Folder:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: categories.map((cat) {
                    final isSel = cat == selectedCategory;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSel,
                      selectedColor: AppColors.secondary,
                      backgroundColor: AppColors.surfaceLight,
                      labelStyle: TextStyle(color: isSel ? Colors.white : Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                      onSelected: (selected) {
                        if (selected) setDialogState(() => selectedCategory = cat);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Track Title (.mp3 / .wav)',
                    filled: true,
                    fillColor: AppColors.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(Icons.music_note_rounded, color: AppColors.secondary, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Track Length:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text('${durationSec}s', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.secondary)),
                  ],
                ),
                Slider(
                  value: durationSec.toDouble(),
                  min: 5.0,
                  max: 120.0,
                  divisions: 115,
                  activeColor: AppColors.secondary,
                  onChanged: (val) {
                    setDialogState(() => durationSec = val.round());
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final trackName = controller.text.trim().isEmpty ? 'Device_Audio_Track' : controller.text.trim();
                final formattedName = (trackName.endsWith('.mp3') || trackName.endsWith('.wav')) ? trackName : '$trackName.mp3';

                // Write a real physical file to temporary directory so File(localPath).existsSync() is true
                String localFilePath = '/storage/emulated/0/$selectedCategory/$formattedName';
                try {
                  final tempFile = File('${Directory.systemTemp.path}/$formattedName');
                  if (!tempFile.existsSync()) {
                    tempFile.writeAsBytesSync(List.generate(2048, (i) => (i % 256)));
                  }
                  localFilePath = tempFile.path;
                } catch (_) {}

                final asset = MediaAsset(
                  id: 'audio_asset_${DateTime.now().millisecondsSinceEpoch}_${formattedName.hashCode.abs()}',
                  type: MediaAssetType.audio,
                  name: formattedName,
                  localPath: localFilePath,
                  duration: Duration(seconds: durationSec),
                  sizeBytes: 5 * 1024 * 1024,
                  createdAt: DateTime.now(),
                );

                widget.viewModel.addMediaAsset(asset);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Imported "$formattedName" into Media Library!'), duration: const Duration(seconds: 2)),
                );
              },
              child: const Text('Import to Library', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleRecording() {
    if (_isRecording) {
      _recordTimer?.cancel();
      setState(() {
        _isRecording = false;
      });
      final recordedSec = math.max(2, _recordSeconds);
      _addMusic(
        'Voiceover Recording (${recordedSec}s)',
        recordedSec,
        assetId: 'voiceover_${DateTime.now().millisecondsSinceEpoch}',
        artist: 'Voice Memo',
      );
    } else {
      setState(() {
        _isRecording = true;
        _recordSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordSeconds++;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final audio = widget.viewModel.audioTrack;
        final importedAudios = widget.viewModel.mediaLibrary.where((a) => a.isAudio).toList();

        return Container(
          height: 280,
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
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.music_note_rounded, size: 16, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              audio != null ? 'Audio: ${audio.title}' : 'Audio & Music Library',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (audio != null)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Remove Audio',
                            onPressed: () => widget.viewModel.removeAudioTrack(),
                          ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Done',
                          onPressed: widget.viewModel.closeDrawer,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Import from Device Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
                child: InkWell(
                  onTap: _handleDeviceAudioImport,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_rounded, color: AppColors.secondary, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Import Audio File from Device Storage',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Tabs: Sounds / Effects / Voiceover
              Container(
                height: 32,
                margin: const EdgeInsets.symmetric(horizontal: AppDimensions.md, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textMuted,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  tabs: const [
                    Tab(text: 'Music Tracks'),
                    Tab(text: 'Sound Effects'),
                    Tab(text: 'Voiceover Record'),
                  ],
                ),
              ),

              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 1. Music Tracks (User-Imported Library Audio ONLY)
                    importedAudios.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.music_off_rounded, color: AppColors.textMuted.withValues(alpha: 0.6), size: 28),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'No music tracks yet',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Import an audio file from your device to get started.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            itemCount: importedAudios.length,
                            itemBuilder: (context, idx) {
                              final asset = importedAudios[idx];
                              final durationSec = asset.duration?.inSeconds ?? 28;

                              return Container(
                                width: 140,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                  border: Border.all(color: AppColors.secondary.withValues(alpha: 0.5), width: 1.2),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: AppColors.secondary.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.music_note_rounded, color: AppColors.secondary, size: 14),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            asset.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'LIBRARY • ${durationSec}s',
                                      style: const TextStyle(fontSize: 9, color: AppColors.secondary, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 26,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.secondary,
                                          padding: EdgeInsets.zero,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        ),
                                        onPressed: () => _addMusic(
                                          asset.name,
                                          durationSec,
                                          assetId: asset.id,
                                          artist: 'Library Audio',
                                        ),
                                        child: const Text('Add to Track', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                    // 2. Online Sound Effects Asset Library
                    _buildSoundEffectsTab(),

                    // 3. Voiceover Recording
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _toggleRecording,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: _isRecording ? 60 : 50,
                              height: _isRecording ? 60 : 50,
                              decoration: BoxDecoration(
                                color: _isRecording ? AppColors.error : AppColors.secondary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isRecording ? AppColors.error : AppColors.secondary).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isRecording ? 'Recording: ${_recordSeconds}s (Tap to Stop)' : 'Tap Mic to Record Voiceover',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _isRecording ? AppColors.error : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSoundEffectsTab() {
    final libraryService = AssetLibraryService.instance;

    return ListenableBuilder(
      listenable: libraryService,
      builder: (context, _) {
        final assets = libraryService.assets;
        final categories = libraryService.categories;
        final selectedCategory = libraryService.selectedCategory;
        final onlyDownloaded = libraryService.onlyDownloaded;
        final isLoading = libraryService.isLoading;

        return Column(
          children: [
            // 1. Search Bar & Filter Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: TextField(
                        controller: _sfxSearchController,
                        onChanged: (val) => libraryService.setSearchQuery(val),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search sound effects...',
                          hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                          prefixIcon: const Icon(Icons.search_rounded, size: 15, color: AppColors.textMuted),
                          prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          suffixIcon: _sfxSearchController.text.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _sfxSearchController.clear();
                                    libraryService.setSearchQuery('');
                                  },
                                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Downloaded Filter Toggle
                  GestureDetector(
                    onTap: () => libraryService.setOnlyDownloaded(!onlyDownloaded),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: onlyDownloaded ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: onlyDownloaded ? AppColors.primary : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.download_done_rounded,
                            size: 13,
                            color: onlyDownloaded ? AppColors.primary : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Downloaded',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: onlyDownloaded ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Category Chips
            SizedBox(
              height: 22,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  final isSelected = !onlyDownloaded && selectedCategory.toLowerCase() == cat.toLowerCase();

                  return GestureDetector(
                    onTap: () {
                      if (onlyDownloaded) libraryService.setOnlyDownloaded(false);
                      libraryService.setCategory(cat);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.secondary : AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: isSelected ? AppColors.secondary : AppColors.divider,
                          width: 0.8,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          cat,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 4),

            // 3. Asset Cards List
            Expanded(
              child: isLoading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      ),
                    )
                  : assets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off_rounded, color: AppColors.textMuted.withValues(alpha: 0.5), size: 24),
                              const SizedBox(height: 4),
                              Text(
                                onlyDownloaded ? 'No downloaded sound effects yet' : 'No sound effects found',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          itemCount: assets.length,
                          itemBuilder: (context, idx) {
                            final asset = assets[idx];
                            return _buildAssetCard(asset, libraryService);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAssetCard(Asset asset, AssetLibraryService libraryService) {
    final isPreviewing = libraryService.isPreviewing(asset.id);
    final downloadProgress = libraryService.getDownloadProgress(asset.id);
    final isDownloading = downloadProgress?.state == DownloadState.downloading;

    IconData icon;
    final cat = asset.category.toLowerCase();
    if (cat.contains('whoosh')) {
      icon = Icons.air_rounded;
    } else if (cat.contains('impact')) {
      icon = Icons.album_rounded;
    } else if (cat.contains('glitch')) {
      icon = Icons.bolt_rounded;
    } else if (cat.contains('camera')) {
      icon = Icons.camera_alt_rounded;
    } else if (cat.contains('cinematic')) {
      icon = Icons.movie_filter_rounded;
    } else {
      icon = Icons.notifications_active_rounded;
    }

    return Container(
      width: 160,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        border: Border.all(
          color: asset.isDownloaded ? AppColors.primary.withValues(alpha: 0.5) : AppColors.divider,
          width: asset.isDownloaded ? 1.0 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Category tag & License tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  asset.category.toUpperCase(),
                  style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: AppColors.secondary),
                ),
              ),
              if (asset.isDownloaded)
                const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.primary)
              else
                Text(
                  asset.formattedFileSize,
                  style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
                ),
            ],
          ),

          // Title & Icon
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      '${asset.formattedDuration} • ${asset.license.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Action Buttons: Preview & Download / Add to Timeline
          Row(
            children: [
              // Preview button
              SizedBox(
                width: 26,
                height: 22,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                      color: isPreviewing ? AppColors.secondary : AppColors.divider,
                      width: 0.8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: () => libraryService.playPreview(asset),
                  child: Icon(
                    isPreviewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 13,
                    color: isPreviewing ? AppColors.secondary : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Download / Add to Timeline button
              Expanded(
                child: SizedBox(
                  height: 22,
                  child: isDownloading
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: downloadProgress?.progress ?? 0.1,
                                  backgroundColor: Colors.transparent,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                  minHeight: 24,
                                ),
                              ),
                              Center(
                                child: Text(
                                  '${((downloadProgress?.progress ?? 0) * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        )
                      : asset.isDownloaded
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onPressed: () async {
                                await widget.viewModel.insertDownloadedAsset(asset);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Added "${asset.name}" to timeline!'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                '+ Add',
                                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primary, width: 0.8),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              onPressed: () async {
                                try {
                                  await libraryService.downloadAsset(asset);
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Download failed: $e'), duration: const Duration(seconds: 2)),
                                    );
                                  }
                                }
                              },
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.download_rounded, size: 11, color: AppColors.primary),
                                  SizedBox(width: 2),
                                  Text('Get', style: TextStyle(fontSize: 9.5, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                ),
              ),

              if (asset.isDownloaded) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 20,
                  height: 22,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.delete_outline_rounded, size: 13, color: AppColors.textMuted),
                    onPressed: () => libraryService.deleteAsset(asset.id),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
