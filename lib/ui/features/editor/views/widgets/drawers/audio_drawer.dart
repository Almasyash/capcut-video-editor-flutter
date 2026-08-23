import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/constants/app_colors.dart';
import 'package:capcut_video_editor/core/constants/app_dimensions.dart';
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

  static const List<Map<String, dynamic>> _musicTracks = [
    {'title': 'Lofi Chill Vibes', 'artist': 'Chilled Beats', 'duration': 24, 'genre': 'Lofi'},
    {'title': 'Trending Hyper Pop', 'artist': 'Synth Wave', 'duration': 18, 'genre': 'Pop'},
    {'title': 'Epic Cinematic Intro', 'artist': 'Orchestra Studio', 'duration': 30, 'genre': 'Cinematic'},
    {'title': 'Deep House Sunset', 'artist': 'Club Mix', 'duration': 22, 'genre': 'EDM'},
  ];

  static const List<Map<String, dynamic>> _soundEffects = [
    {'title': 'Whoosh Transition', 'duration': 2, 'icon': Icons.air_rounded},
    {'title': 'Glitch Sound FX', 'duration': 3, 'icon': Icons.electric_bolt_rounded},
    {'title': 'Camera Shutter', 'duration': 1, 'icon': Icons.camera_alt_rounded},
    {'title': 'Pop Bubble Ding', 'duration': 1, 'icon': Icons.touch_app_rounded},
    {'title': 'Success Bell Chime', 'duration': 2, 'icon': Icons.notifications_active_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
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
      waveformPoints: waveform,
      volume: 0.85,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imported audio file into Media Library! Select it below to add to timeline.'),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
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

                final asset = MediaAsset(
                  id: 'audio_asset_${DateTime.now().millisecondsSinceEpoch}_${formattedName.hashCode.abs()}',
                  type: MediaAssetType.audio,
                  name: formattedName,
                  localPath: '/storage/emulated/0/$selectedCategory/$formattedName',
                  duration: Duration(seconds: durationSec),
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
          height: 250,
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
                    Row(
                      children: [
                        const Icon(Icons.music_note_rounded, size: 16, color: AppColors.secondary),
                        const SizedBox(width: 6),
                        Text(
                          audio != null ? 'Audio: ${audio.title}' : 'Audio & Music Library',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    Row(
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
                      color: AppColors.secondary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                      border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
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
                    // 1. Music Tracks (Imported Library Audio + Preset Tracks)
                    ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: importedAudios.length + _musicTracks.length,
                      itemBuilder: (context, idx) {
                        if (idx < importedAudios.length) {
                          final asset = importedAudios[idx];
                          final durationSec = asset.duration?.inSeconds ?? 28;

                          return Container(
                            width: 140,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                              border: Border.all(color: AppColors.secondary.withOpacity(0.5), width: 1.2),
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
                                        color: AppColors.secondary.withOpacity(0.2),
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
                        }

                        final presetIdx = idx - importedAudios.length;
                        final item = _musicTracks[presetIdx];
                        return Container(
                          width: 130,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            border: Border.all(color: AppColors.divider),
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
                                      color: AppColors.secondary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.music_note_rounded, color: AppColors.secondary, size: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item['title'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              Text('${item['genre']} • ${item['duration']}s', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
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
                                    item['title'] as String,
                                    item['duration'] as int,
                                    assetId: 'preset_audio_${item['title'].hashCode.abs()}',
                                  ),
                                  child: const Text('Add Track', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // 2. Sound Effects
                    ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      itemCount: _soundEffects.length,
                      itemBuilder: (context, idx) {
                        final sfx = _soundEffects[idx];
                        return Container(
                          width: 115,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Icon(sfx['icon'] as IconData, color: AppColors.primary, size: 22),
                              Text(
                                sfx['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              Text('${sfx['duration']}s FX', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
                              SizedBox(
                                width: double.infinity,
                                height: 24,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.primary, width: 0.8),
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  onPressed: () => _addMusic(
                                    sfx['title'] as String,
                                    sfx['duration'] as int,
                                    assetId: 'preset_sfx_${sfx['title'].hashCode.abs()}',
                                    artist: 'Sound Effect',
                                  ),
                                  child: const Text('Insert', style: TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

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
                                    color: (_isRecording ? AppColors.error : AppColors.secondary).withOpacity(0.4),
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
}
