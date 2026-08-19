# CapCut-Style Mobile Video Editing App (Flutter)

A modern, high-performance mobile video editor application built with Flutter, inspired by CapCut.

## 🚀 Features

- **Top Video Preview Screen**:
  - Multi-aspect ratio canvas supporting **9:16** (TikTok, Reels, Shorts), **16:9** (YouTube), **1:1** (Instagram Square), and **4:5** (Portrait Feed).
  - High-precision timecode indicator (`00:04.12 / 00:20.00`).
  - Active subtitle / text overlay rendering on top of the live video.
  - Interactive tap-to-play / pause toggle.

- **Middle Action Toolbar**:
  - ✂️ **Split**: Intelligently splits the selected clip at the exact playhead position into two continuous segments with frame-accurate offsets.
  - 📐 **Trim Left & Trim Right**: Quick one-tap trimming to playhead position.
  - 🗑️ **Delete**: Remove selected clip from timeline.
  - 📋 **Duplicate**: Duplicate selected clip instantly.
  - ⚡ **Speed**: Adjust playback speed (0.5x, 1x, 1.5x, 2x, 3x).
  - 🔊 **Volume**: Fine-tune audio volume from 0% to 100%.
  - ➕ **Add Clip**: Append new media assets to timeline.
  - 📤 **Export**: Quick export trigger.

- **Interactive Multi-Track Timeline (Bottom)**:
  - Scrollable time ruler with millisecond and second tick marks.
  - Fixed center playhead needle with cyan marker and white line.
  - Main video track with filmstrip preview and draggable amber trim handles.
  - Audio track with rendered audio waveform visualizer.
  - Subtitle / Text track.
  - Pinch / slider zoom scale (`pixelsPerSecond`).

- **Undo / Redo History**:
  - Full state snapshot history stack supporting undo and redo across all timeline edits.

- **Export & Rendering Engine**:
  - Resolution presets (720P, 1080P, 2K, 4K).
  - Frame rate presets (24 FPS Cinematic, 30 FPS Standard, 60 FPS Ultra Smooth).
  - Live export rendering modal with progress percentage indicator and completion confirmation.

---

## 📁 Architecture & Folder Structure

Adheres strictly to the layered **MVVM (Model-View-ViewModel)** pattern:

```text
capcut_video_editor/
├── pubspec.yaml
├── analysis_options.yaml
├── README.md
├── lib/
│   ├── main.dart                               # App entrypoint
│   ├── app.dart                                # MaterialApp & Theme config
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart                 # Dark theme palette & gradients
│   │   │   ├── app_dimensions.dart             # Layout & sizing constraints
│   │   │   └── app_typography.dart             # Text styles & tabular figures
│   │   ├── theme/
│   │   │   └── app_theme.dart                  # Global ThemeData
│   │   └── utils/
│   │       └── time_formatter.dart             # Timecode formatting utilities
│   ├── domain/
│   │   ├── enums/
│   │   │   ├── aspect_ratio_preset.dart        # 9:16, 16:9, 1:1, 4:5
│   │   │   ├── tool_action_type.dart           # Split, Trim, Delete, etc.
│   │   │   └── export_resolution.dart          # 720p, 1080p, 4k, 60fps
│   │   └── models/
│   │       ├── video_clip.dart                 # Video segment model
│   │       ├── audio_track.dart                # BGM track & waveform model
│   │       ├── text_overlay.dart               # Subtitles model
│   │       └── export_settings.dart            # Export render config
│   ├── data/
│   │   └── repositories/
│   │       └── mock_media_repository.dart      # Demo assets generator
│   └── ui/
│       └── features/
│           └── editor/
│               ├── view_models/
│               │   └── editor_view_model.dart  # State management & edit actions
│               └── views/
│                   ├── editor_screen.dart      # Main screen layout
│                   └── widgets/
│                       ├── top_navigation_bar.dart
│                       ├── video_preview_section.dart
│                       ├── action_toolbar.dart
│                       ├── timeline_section.dart
│                       ├── timeline_ruler.dart
│                       ├── timeline_clip_item.dart
│                       ├── audio_track_item.dart
│                       ├── export_modal_sheet.dart
│                       └── bottom_tool_selector.dart
└── test/
    ├── unit/
    │   ├── time_formatter_test.dart
    │   └── editor_view_model_test.dart
    └── widget/
        └── editor_screen_test.dart
```

---

## 🛠️ Running the Project

1. Navigate to the project workspace:
   ```bash
   cd C:\Users\almas\.gemini\antigravity\scratch\capcut_video_editor
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run on your connected device, emulator, or Chrome:
   ```bash
   flutter run
   ```
4. Run automated tests:
   ```bash
   flutter test
   ```
