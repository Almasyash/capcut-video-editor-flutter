# Changelog

All notable changes to **Mahmas Studio** are documented in this file.

---

## [2.4.8] - 2026-09-06

### 🚀 Highlights & Major Features
- **Real-Time Visual Transition Rendering Engine**: Full multi-layer dual-video preview compositing with 12 distinct GPU-accelerated transition shaders (Fade, Dissolve, Slide Left/Right/Up/Down, Wipe Left/Right, Zoom In/Out, Flash Black/White).
- **Hardware-Accelerated Transition Export Pipeline**: Video compositing during gallery export embedding transition effects directly into exported MP4 media using Android MediaCodec & OpenGL ES.
- **Timeline Playhead Synchronization Engine**: Fixed playhead drift during playback by binding the timeline scrubber clock directly to native ExoPlayer position updates, with hard boundary clamping and zero end-of-clip drift.
- **CapCut-Like Split & Ripple Delete Engines**: Non-destructive split-cut trimming with adjacent transition validation and automatic ripple cleanup.
- **Full Test Suite & Quality Assurance**: 263/263 unit and widget tests passing with 0 static analysis issues. Verified on physical hardware (Realme RMX5003).

---

## [1.0.0] - 2026-08-28

### 🚀 Major Milestones & Architectural Redesign

#### Centralized MediaAsset Architecture
- Introduced canonical `MediaAsset` repository pattern across all timeline layers (`VideoClip`, `AudioTrack`, `OverlayClip`, `TextOverlay`).
- Decoupled timeline UI from raw file URIs and filesystem paths.
- Streamed Android Photo Picker `content://` URIs via native `ContentResolver` into private app storage (`context.filesDir/media/`).
- Automated native metadata extraction (precise duration probing and video frame thumbnail generation) via `MediaMetadataRetriever`.

#### Hardware-Accelerated Video Layer Controls
- **Playback**: Integrated Android `MediaPlayer` with `SurfaceTexture` / `Flutter Texture` for smooth zero-lag preview.
- **Speed Control**: Implemented dynamic variable speed scaling (0.25x – 4.0x) modifying native `MediaPlayer.playbackParams.speed` and recalculating active clip duration.
- **Volume Control**: Added per-clip volume slider (0% – 100%) mapped directly to native `MediaPlayer.setVolume()`, isolated per video clip.
- **Trimming**: Implemented non-destructive start/end trimming via draggable timeline handles and Toolbar quick-actions.
- **Split & Duplicate**: Implemented split at playhead (Part 1 & Part 2) and clip duplication to main timeline or PIP overlay.
- **Deletion**: Safe clip removal and automatic timeline duration recalculation.

#### Audio Layer Controls & Multi-Track Engine
- Supported direct local audio file import (`.mp3`, `.wav`, `.m4a`, `.aac`, `.ogg`).
- Multi-track timeline synchronization allowing external audio tracks to coexist with embedded video sound.
- Full audio editing: Split, Trim Left/Right, Speed (0.5x – 2.0x), Volume slider (0% – 100%), Mute toggle, Duplicate, and Delete.
- Auto-play prevention on track import to preserve user timeline positioning.

#### Text & Subtitle System
- Canvas text overlay rendering with real-time scaling, font sizing, and color swatches.
- Timeline integration supporting Text Split, Duplicate, Speed, and Delete.
- Integrated Android native `TextToSpeech` service for voice synthesis.

#### Project Persistence & Drafts Dashboard
- Automatic JSON project serialization (`ProjectStorageService`) on every timeline action.
- HomeScreen dashboard displaying recent drafts with real video thumbnails, durations, and clip counts.
- Seamless project reopening and state restoration.

#### UI & Clean-up
- Cleaned Add Clip media picker to display **only genuine user-imported media** (`Videos` and `Photos`).
- Removed all mock demo lists, sample assets, and fake dummy file generators.
- Removed legacy "Canvases" drawer and tab to streamline editing workflows.
- Fixed layout constraints in timeline clips preventing text and badge overflows on small clips.

---

### 🧪 Quality Assurance
- **Static Analysis**: `flutter analyze` completed with `0` issues.
- **Automated Tests**: `86/86` unit and widget tests passing.
- **Hardware Verification**: Verified live on physical Realme RMX5003 (Android 16 / API 36).
