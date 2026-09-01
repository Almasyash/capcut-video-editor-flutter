import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:capcut_video_editor/core/services/asset_download_service.dart';
import 'package:capcut_video_editor/core/services/asset_library_service.dart';
import 'package:capcut_video_editor/core/services/asset_storage_service.dart';
import 'package:capcut_video_editor/data/repositories/asset_repository.dart';
import 'package:capcut_video_editor/domain/models/asset.dart';
import 'package:capcut_video_editor/domain/models/audio_track.dart';
import 'package:capcut_video_editor/domain/models/media_asset.dart';
import 'package:capcut_video_editor/domain/models/project.dart';
import 'package:capcut_video_editor/ui/features/editor/view_models/editor_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Online Asset Library & Downloadable Store Tests', () {
    late RemoteAssetRepository remoteRepo;
    late AssetStorageService storageService;
    late AssetDownloadService downloadService;
    late AssetLibraryService libraryService;

    setUp(() async {
      remoteRepo = RemoteAssetRepository();
      storageService = AssetStorageService.instance;
      downloadService = AssetDownloadService.instance;
      libraryService = AssetLibraryService.instance;
      await storageService.clearAll();
      await libraryService.initialize();
    });

    tearDown(() async {
      await storageService.clearAll();
    });

    test('TEST 1: Old hardcoded/demo SFX are no longer present in the active library', () async {
      final assets = await remoteRepo.getAssets();
      final titles = assets.map((a) => a.name.toLowerCase()).toList();

      expect(titles.contains('woosh transition'), isFalse);
      expect(titles.contains('glitch sound fx'), isFalse);
      expect(titles.contains('camera shutter'), isFalse);
      expect(titles.contains('pop bubble ding'), isFalse);
      expect(titles.contains('success bell chime'), isFalse);
    });

    test('TEST 2: AssetRepository returns valid Asset models', () async {
      final assets = await remoteRepo.getAssets();
      expect(assets.isNotEmpty, isTrue);
      for (final asset in assets) {
        expect(asset.id, isNotEmpty);
        expect(asset.name, isNotEmpty);
        expect(asset.category, isNotEmpty);
        expect(asset.durationMs, greaterThan(0));
        expect(asset.fileSizeBytes, greaterThan(0));
        expect(asset.previewUrl, startsWith('https://'));
        expect(asset.downloadUrl, startsWith('https://'));
        expect(asset.license.name, isNotEmpty);
      }
    });

    test('TEST 3: Sound effect asset metadata is parsed correctly', () {
      final json = {
        'id': 'sfx_test_01',
        'name': 'Test Sound Effect',
        'category': 'Impact',
        'type': 'soundEffect',
        'description': 'A heavy test bass impact',
        'durationMs': 2400,
        'fileSizeBytes': 211680,
        'previewUrl': 'https://assets.editorfs.app/sfx/test_preview.wav',
        'downloadUrl': 'https://assets.editorfs.app/sfx/test.wav',
        'version': '1.1.0',
        'license': {
          'name': 'Creative Commons 0',
          'attributionRequired': false,
        },
        'tags': ['impact', 'bass'],
        'isDownloaded': false,
      };

      final asset = Asset.fromJson(json);
      expect(asset.id, equals('sfx_test_01'));
      expect(asset.name, equals('Test Sound Effect'));
      expect(asset.category, equals('Impact'));
      expect(asset.type, equals(AssetType.soundEffect));
      expect(asset.durationMs, equals(2400));
      expect(asset.formattedDuration, equals('2.4s'));
      expect(asset.formattedFileSize, equals('206.7 KB'));
      expect(asset.license.name, equals('Creative Commons 0'));
      expect(asset.license.attributionRequired, isFalse);
    });

    test('TEST 4: Transition asset metadata is parsed correctly', () {
      final json = {
        'id': 'trn_test_01',
        'name': 'Dynamic Whip Pan',
        'category': 'Whoosh',
        'type': 'transition',
        'description': 'Directional whip blur transition',
        'durationMs': 800,
        'fileSizeBytes': 705644,
        'previewUrl': 'https://assets.editorfs.app/trn/whip_preview.mp4',
        'downloadUrl': 'https://assets.editorfs.app/trn/whip.zip',
        'version': '1.0.0',
        'license': {
          'name': 'Editor FS Royalty-Free Standard',
          'attributionRequired': false,
        },
        'tags': ['transition', 'whip'],
      };

      final asset = Asset.fromJson(json);
      expect(asset.id, equals('trn_test_01'));
      expect(asset.type, equals(AssetType.transition));
      expect(asset.category, equals('Whoosh'));
      expect(asset.formattedDuration, equals('0.8s'));
      expect(asset.formattedFileSize, equals('689.1 KB'));
    });

    test('TEST 5: Download state changes correctly', () async {
      final asset = (await remoteRepo.getAssets()).first;
      expect(await storageService.isAssetDownloaded(asset.id), isFalse);

      final localPath = await downloadService.downloadAsset(asset);
      expect(localPath, isNotEmpty);
      expect(await storageService.isAssetDownloaded(asset.id), isTrue);

      final progress = downloadService.getProgress(asset.id);
      expect(progress?.state, equals(DownloadState.downloaded));
      expect(progress?.progress, equals(1.0));
    });

    test('TEST 6: Download progress is reported correctly', () async {
      final asset = (await remoteRepo.getAssets()).first;
      final reportedStates = <DownloadState>[];

      final sub = downloadService.progressStream.listen((p) {
        if (p.assetId == asset.id) {
          reportedStates.add(p.state);
        }
      });

      await downloadService.downloadAsset(asset);
      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(reportedStates, contains(DownloadState.downloading));
      expect(reportedStates, contains(DownloadState.downloaded));
    });

    test('TEST 7: Successful download stores the file locally', () async {
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);

      final file = File(localPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));
    });

    test('TEST 8: Downloaded asset persists after app restart/repository recreation', () async {
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);

      // Recreate storage service simulating app restart
      final newStorage = AssetStorageService.instance;
      await newStorage.initialize();

      expect(await newStorage.isAssetDownloaded(asset.id), isTrue);
      final restoredPath = await newStorage.getLocalPath(asset.id);
      expect(restoredPath, equals(localPath));
      expect(File(restoredPath!).existsSync(), isTrue);

      final newLocalRepo = LocalAssetRepository(storageService: newStorage);
      final downloadedList = await newLocalRepo.getAssets();
      expect(downloadedList.any((a) => a.id == asset.id), isTrue);
    });

    test('TEST 9: Downloaded SFX can be converted into an AudioTrack', () async {
      final vm = EditorViewModel();
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);
      final downloadedAsset = asset.copyWith(isDownloaded: true, localPath: localPath);

      final track = await vm.insertDownloadedAsset(downloadedAsset);

      expect(vm.audioTracks.length, equals(1));
      expect(track.assetId, equals(asset.id));
      expect(track.title, equals(asset.name));
      expect(track.artist, equals('Asset Library'));

      final mediaAsset = vm.getAssetById(track.assetId);
      expect(mediaAsset, isNotNull);
      expect(mediaAsset!.localPath, equals(localPath));
      expect(File(mediaAsset.localPath!).existsSync(), isTrue);

      vm.dispose();
    });

    test('TEST 10: Inserted downloaded SFX has correct duration', () async {
      final vm = EditorViewModel();
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);
      final downloadedAsset = asset.copyWith(isDownloaded: true, localPath: localPath);

      final track = await vm.insertDownloadedAsset(downloadedAsset);
      expect(track.duration, equals(asset.duration));
      expect(track.durationInSeconds, equals(asset.durationInSeconds));

      vm.dispose();
    });

    test('TEST 11: Inserted downloaded SFX preserves timeline start', () async {
      final vm = EditorViewModel();
      vm.seekTo(4.2); // Set playhead at 4.2s

      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);
      final downloadedAsset = asset.copyWith(isDownloaded: true, localPath: localPath);

      final track = await vm.insertDownloadedAsset(downloadedAsset);
      expect(track.startTimeInSeconds, equals(4.2));
      expect(track.durationInSeconds, equals(asset.durationInSeconds));
      expect(track.endTimeInSeconds, closeTo(4.2 + asset.durationInSeconds, 0.01));

      vm.dispose();
    });

    test('TEST 12: Downloaded SFX can be serialized', () async {
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);
      expect(File(localPath).existsSync(), isTrue);

      final track = AudioTrack(
        id: 'audio_lib_serialize_test',
        assetId: asset.id,
        title: asset.name,
        artist: 'Asset Library',
        duration: asset.duration,
        startTime: const Duration(seconds: 1),
      );

      final json = track.toJson();
      expect(json['id'], equals('audio_lib_serialize_test'));
      expect(json['assetId'], equals(asset.id));
      expect(json['name'], equals(asset.name));
      expect(json['artist'], equals('Asset Library'));
      expect(json['durationMs'], equals(asset.durationMs));
    });

    test('TEST 13: Downloaded SFX can be restored and resolved by EditorViewModel', () async {
      final asset = (await remoteRepo.getAssets()).first;
      final localPath = await downloadService.downloadAsset(asset);

      final track = AudioTrack(
        id: 'audio_lib_restore_test',
        assetId: asset.id,
        title: asset.name,
        artist: 'Asset Library',
        duration: asset.duration,
        startTime: const Duration(seconds: 1),
      );

      final project = Project(
        id: 'proj_sfx_test_1',
        name: 'SFX Restore Project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        audioTracks: [track],
      );

      final projectJson = project.toJson();
      final restored = Project.fromJson(projectJson);

      expect(restored.audioTracks.length, equals(1));
      expect(restored.audioTracks.first.assetId, equals(asset.id));

      final freshVm = EditorViewModel();
      final resolvedAsset = freshVm.getAssetById(restored.audioTracks.first.assetId);
      expect(resolvedAsset, isNotNull);
      expect(resolvedAsset!.localPath, equals(localPath));
      expect(File(resolvedAsset.localPath!).existsSync(), isTrue);

      freshVm.dispose();
    });

    test('TEST 14: Offline downloaded assets remain available when remote repository is offline', () async {
      final asset = (await remoteRepo.getAssets()).first;
      await downloadService.downloadAsset(asset);

      final offlineLibrary = AssetLibraryService.instance;
      offlineLibrary.setOfflineMode(true);
      await offlineLibrary.refresh();

      expect(offlineLibrary.assets.length, equals(1));
      expect(offlineLibrary.assets.first.id, equals(asset.id));
      expect(offlineLibrary.assets.first.isDownloaded, isTrue);

      offlineLibrary.setOfflineMode(false);
    });

    test('TEST 15: Download failure does not corrupt the asset library', () async {
      const corruptAsset = Asset(
        id: 'corrupt_test_asset',
        name: 'Corrupt Asset',
        category: 'Test',
        type: AssetType.soundEffect,
        description: 'Test corrupt download',
        durationMs: 1000,
        fileSizeBytes: 100,
        previewUrl: '',
        downloadUrl: 'invalid://invalid-url-failure',
        license: AssetLicense(name: 'CC0'),
      );

      try {
        await downloadService.downloadAsset(corruptAsset);
      } catch (_) {}

      expect(await storageService.isAssetDownloaded(corruptAsset.id), isFalse);
      final list = await storageService.getAllDownloadedAssets();
      expect(list.any((a) => a.id == corruptAsset.id), isFalse);
    });

    test('TEST 16: Existing user audio import from device storage remains fully functional', () {
      final vm = EditorViewModel();
      final userAsset = MediaAsset(
        id: 'user_custom_audio_101',
        type: MediaAssetType.audio,
        name: 'MySong.mp3',
        localPath: '/storage/emulated/0/Music/MySong.mp3',
        duration: const Duration(seconds: 45),
        sizeBytes: 1024 * 1024 * 4,
        createdAt: DateTime.now(),
      );

      vm.addMediaAsset(userAsset);
      expect(vm.mediaLibrary.where((a) => a.isAudio).length, equals(1));

      vm.addAudioTrackFromAsset(userAsset);
      expect(vm.audioTracks.length, equals(1));
      expect(vm.audioTracks.first.title, equals('MySong.mp3'));
      expect(vm.audioTracks.first.artist, equals('Local Audio'));

      vm.dispose();
    });

    test('TEST 17: Fresh project still starts with 0 default music tracks', () {
      final vm = EditorViewModel();
      expect(vm.audioTracks, isEmpty);
      expect(vm.mediaLibrary.where((a) => a.isAudio), isEmpty);
      vm.dispose();
    });

    test('TEST 18: No default demo music is reintroduced', () {
      final vm = EditorViewModel();
      final audioTitles = vm.mediaLibrary.where((a) => a.isAudio).map((a) => a.name.toLowerCase()).toList();

      expect(audioTitles.contains('midnight beats'), isFalse);
      expect(audioTitles.contains('lofi chill vibes'), isFalse);
      expect(audioTitles.contains('trending hyper'), isFalse);
      expect(audioTitles.contains('epic cinematic'), isFalse);
      vm.dispose();
    });
  });
}
