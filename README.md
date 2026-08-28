# Mahmas Studio

> A modern, local-first Flutter video editing application built with high-performance Android native media pipelines and interactive multi-track timeline controls.

---

## 📖 Overview

**Mahmas Studio** is an open-source, local-first mobile video editor designed for high-performance timeline editing on Android devices. Built using Flutter and Dart with native Kotlin platform bridges, Mahmas Studio provides a non-linear video editing experience without relying on cloud processing or remote servers.

### Key Highlights
- **Local-First Media Engine**: All imported videos, images, and audio tracks are stored directly in the device's app-private storage (`context.filesDir/media/`), processed locally, and played offline.
- **Native Android Hardware Acceleration**: Utilizes Android `MediaPlayer`, `SurfaceTexture`, `Flutter Texture`, and `MediaMetadataRetriever` for zero-lag hardware-accelerated video rendering, thumbnail extraction, and dynamic playback control.
- **Centralized MediaAsset Pipeline**: All timeline tracks (Video, Audio, Overlay, Text) reference canonical `MediaAsset` entities, ensuring consistent duration, file paths, and timing metadata across operations.
- **Interactive Multi-Track Timeline**: Features draggable timeline tracks, dual-handle edge trimming, split at playhead, duplication, speed manipulation, and per-track volume controls.
- **Persistent JSON Project Architecture**: Automatic background draft saving and recovery, preserving full timeline state, clip bounds, trim intervals, speeds, and volume settings.

---

## 🎬 Current Verified Features

### 1. Video Layer Controls
- **Device & Gallery Video Import**: Uses Android Photo Picker and File Picker to import real local MP4/MKV videos.
- **Persistent Local Media Storage**: Streams raw `content://` URIs through Android `ContentResolver` into sanitized, app-private local files.
- **Native Metadata & Thumbnail Extraction**: Asynchronously extracts duration and video frame thumbnails via `MediaMetadataRetriever`.
- **Hardware-Accelerated Playback**: Real-time video preview powered by native `SurfaceTexture` / `Flutter Texture` ID.
- **Split Video**: Splits active video clips into two independent clips at the playhead position with preserved timing.
- **Non-Destructive Trimming**: Draggable left/right handles and Quick-Trim toolbar buttons adjust `trimStart` and `trimEnd` non-destructively without modifying the original media file.
- **Video Speed Adjustment**: Variable speed scaling (0.25x – 4.0x) powered by Android `MediaPlayer.playbackParams`, dynamically recalculating clip duration and playhead offset.
- **Video Volume Control**: Per-clip volume slider (0% – 100%) mapped directly to native `MediaPlayer.setVolume()`, isolated per video clip.
- **Video Duplication**: Clones clips to either the Main Timeline or Picture-in-Picture (PIP) overlay track with isolated properties.
- **Video Delete**: Safely removes clips from the project timeline and recalculates the total project duration.

### 2. Audio Layer Controls
- **Local Audio Import**: Direct import of local audio files (`.mp3`, `.wav`, `.m4a`, `.aac`, `.ogg`) into persistent project storage.
- **Multi-Track Coexistence**: Multiple audio tracks can coexist simultaneously alongside embedded video audio.
- **Audio Playback & Sync**: Synchronized playback controlled via `AudioPlaybackService` and native `MediaPlayer`.
- **Audio Split**: Splits audio tracks at the playhead into independent segments.
- **Audio Trim**: Non-destructive start and end trimming.
- **Audio Speed**: Independent audio playback speed adjustments (0.5x – 2.0x).
- **Audio Volume & Mute**: Per-track volume slider (0% – 100%) and one-tap track mute toggle.
- **Audio Duplicate & Delete**: Independent track cloning and deletion.

### 3. Text & Subtitle Layer
- **Live Text Overlays**: Render dynamic text and subtitles directly over the video canvas.
- **Styling & Colors**: Real-time font size scaling, color swatches, background highlights, and alignment.
- **Text Timeline Controls**: Independent timeline bars with draggable position, Split, Duplicate, Speed, and Delete actions.
- **Text-to-Speech (TTS)**: Speech generation service integration powered by Android native `TextToSpeech`.

### 4. Project Persistence & Drafts
- **Auto-Save Draft Engine**: Project state is automatically serialized to JSON on every edit action.
- **Home Screen Drafts**: Dashboard listing recent projects with live video thumbnails, clip counts, duration, and last-modified timestamps.
- **Draft Reopening & Recovery**: Load and resume full editing sessions with zero loss of timeline or asset configuration.

### 5. Media Library & Add Clip
- **Zero Mock Media**: Clean, production-ready media sheet displaying **only genuine user-imported media**.
- **Tabs**: Dedicated `Videos` and `Photos` library tabs with empty states and import CTA buttons.
- **No Unused Options**: Removed outdated sample assets and canvas drawers.

---

## 🏗️ Architecture

Mahmas Studio uses a centralized **MediaAsset** repository model to decouple raw device storage from the timeline presentation layer.

```
+-------------------------------------------------------------+
|             Device Gallery / File Picker Storage            |
|         (content:// Android URIs or Local Storage)          |
+-------------------------------------------------------------+
                              |
                              v  (Streamed via ContentResolver)
+-------------------------------------------------------------+
|                     DeviceMediaService                      |
|       - Sanitizes filename                                  |
|       - Writes to context.filesDir/media/                   |
|       - Extracts duration & thumbnail via native retriever  |
+-------------------------------------------------------------+
                              |
                              v  (Emits MediaAsset entity)
+-------------------------------------------------------------+
|                         MediaAsset                          |
|   { id, type, name, localPath, durationMs, thumbnailPath }  |
+-------------------------------------------------------------+
                              |
                              v  (Registered in Project)
+-------------------------------------------------------------+
|                EditorViewModel.mediaLibrary                 |
+-------------------------------------------------------------+
         |                                           |
         v                                           v
+-----------------------+                 +-----------------------+
|       VideoClip       |                 |      AudioTrack       |
| (References assetId)  |                 | (References assetId)  |
| - startTime, trim     |                 | - startTime, trim     |
| - speed, volume       |                 | - speed, volume       |
+-----------------------+                 +-----------------------+
         |                                           |
         v                                           v
+-----------------------+                 +-----------------------+
| VideoPlaybackService  |                 | AudioPlaybackService  |
| - Android MediaPlayer |                 | - Android MediaPlayer |
| - SurfaceTexture / ID |                 | - Multi-source audio  |
+-----------------------+                 +-----------------------+
```

---

## 🔒 Storage & Privacy

- **App-Private Storage**: All imported media files are copied to `context.filesDir/media/` (`/data/user/0/com.example.capcut_video_editor/files/media/`).
- **ContentResolver Streaming**: Raw Android `content://` URIs from the Android Photo Picker are streamed into private local files rather than being accessed as raw filesystem paths.
- **Filename Sanitization**: Special characters, spaces, and path traversals are sanitized upon import.
- **100% Offline & Local**: Media is processed entirely on the local device without transmitting any video or audio data to external servers.

---

## 🤖 Android Native Integration

| Native Component | Technology | Role in Mahmas Studio |
|---|---|---|
| **Video Player** | `android.media.MediaPlayer` + `SurfaceTexture` | Native video decoding, scaling, speed control (`playbackParams.speed`), and volume adjustments. |
| **Audio Player** | `android.media.MediaPlayer` | External audio track playback, volume management, and multi-track mixing. |
| **Metadata & Thumbnails** | `android.media.MediaMetadataRetriever` | High-speed duration probe and frame capture for video thumbnails. |
| **Text to Speech** | `android.speech.tts.TextToSpeech` | Native TTS voice synthesis for subtitle voiceovers. |
| **Platform Channels** | `MethodChannel` (`VIDEO_PLAYER_CHANNEL`, `AUDIO_PLAYER_CHANNEL`) | Asynchronous bidirectional communication between Dart and Kotlin. |

---

## 💻 Tech Stack

- **Framework**: Flutter 3.22+ (Dart SDK `>=3.0.0 <4.0.0`)
- **Language**: Dart (UI & State) & Kotlin (Android Platform Engine)
- **Kotlin Version**: `2.0.0`
- **Android Gradle Plugin (AGP)**: `8.5.2`
- **Gradle Version**: `8.7`
- **Java / JDK**: OpenJDK 17 (JVM 17 Target)
- **Android SDK**:
  - `compileSdk`: `34` (Android 14)
  - `minSdk`: `24` (Android 7.0+)
  - `targetSdk`: `34` (Android 14)

---

## 📁 Project Structure

```
lib/
├── app.dart                                # Application root widget & theme
├── main.dart                               # Flutter app entry point
├── core/
│   ├── constants/
│   │   ├── app_colors.dart                 # Design system colors
│   │   ├── app_dimensions.dart             # Layout sizing & metrics
│   │   └── app_typography.dart             # Text styles & fonts
│   ├── services/
│   │   ├── audio_playback_service.dart     # Native audio playback controller
│   │   ├── device_media_service.dart       # Device file picker & media importer
│   │   ├── project_storage_service.dart    # JSON project persistence & draft storage
│   │   ├── tts_service.dart                # Native Text-To-Speech service
│   │   └── video_playback_service.dart     # Native video texture & playback engine
│   ├── theme/
│   │   └── app_theme.dart                  # Material dark theme configuration
│   └── utils/
│       └── time_formatter.dart             # Timecode formatting utility
├── data/
│   └── repositories/
│       └── mock_media_repository.dart      # Fallback asset definitions
├── domain/
│   ├── enums/
│   │   ├── aspect_ratio_preset.dart        # Canvas aspect ratios (9:16, 16:9, 1:1, etc.)
│   │   ├── export_resolution.dart          # Export resolutions (720p, 1080p, 4k)
│   │   └── tool_action_type.dart           # Action categories & tool types
│   └── models/
│       ├── audio_track.dart                # Audio track model & serialization
│       ├── color_adjustments.dart          # Brightness, contrast, saturation adjustments
│       ├── editor_filter.dart              # Color LUT filter model
│       ├── export_settings.dart            # Resolution & frame rate export model
│       ├── media_asset.dart                # Canonical media asset model
│       ├── overlay_clip.dart               # PIP overlay model
│       ├── project.dart                    # Top-level project model
│       ├── sticker_item.dart               # Sticker overlay model
│       ├── text_overlay.dart               # Subtitle & text model
│       ├── video_clip.dart                 # Main video clip model & timing
│       └── video_effect.dart               # Visual effect model
└── ui/
    └── features/
        ├── home/
        │   └── views/
        │       └── home_screen.dart        # Projects dashboard & draft manager
        └── editor/
            ├── view_models/
            │   └── editor_view_model.dart  # Centralized video editor state manager
            └── views/
                ├── editor_screen.dart      # Main editing workspace
                └── widgets/
                    ├── action_toolbar.dart # Dynamic context toolbar (Split, Speed, Vol, Trim, etc.)
                    ├── audio_track_item.dart # Timeline audio track widget
                    ├── bottom_tool_selector.dart # Bottom drawer navigation selector
                    ├── duplicate_options_sheet.dart # Duplicate destination modal
                    ├── export_modal_sheet.dart # Video render progress dialog
                    ├── media_picker_sheet.dart # User media import sheet
                    ├── timeline_clip_item.dart # Timeline video clip with trim handles
                    ├── timeline_ruler.dart # Scrollable millisecond time ruler
                    ├── timeline_section.dart # Multi-track interactive timeline
                    ├── top_navigation_bar.dart # Top bar (Aspect ratio, undo/redo, export)
                    ├── video_preview_section.dart # Native video preview viewport
                    └── drawers/            # Feature-specific drawers (Audio, Text, Adjust, etc.)
```

---

## 🚀 Setup & Build Instructions

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `>=3.10.0`)
- [Android Studio / SDK](https://developer.android.com/studio) (Android SDK Platform 34)
- JDK 17

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/Almasyash/capcut-video-editor-flutter.git
cd capcut-video-editor-flutter
flutter pub get
```

### 2. Run Static Analysis
```bash
flutter analyze
```

### 3. Run Automated Tests
```bash
flutter test
```

### 4. Run on a Physical Android Device
```bash
# Verify connected devices
flutter devices

# Run on your target device
flutter run -d <DEVICE_ID>
```

### 5. Build Debug APK
```bash
flutter build apk --debug --android-skip-build-dependency-validation
```

> **Note on Release Signing**: Release signing keys are not committed to source control. To generate a production-signed APK, configure your signing credentials in `android/key.properties` and update `android/app/build.gradle.kts`.

---

## 🧪 Testing Status

- **Static Analysis**: `flutter analyze` completed with **0 issues**.
- **Automated Tests**: **86/86 unit and widget tests passing** covering:
  - Video speed, volume, trim, split, duplication, and deletion
  - Audio multi-track synchronization and auto-play prevention
  - Text layer styling, duration scaling, and duplication
  - Canonical `MediaAsset` serialization and project draft recovery
  - UI category drawers and media picker sheets

---

## 📄 License & Contributing

- **License**: A formal license decision is currently pending. Please refer to repository maintainers for usage terms.
- **Contributions**: Pull requests and issue reports are welcome. Ensure all new features are accompanied by unit/widget tests and adhere to the centralized `MediaAsset` architecture.

