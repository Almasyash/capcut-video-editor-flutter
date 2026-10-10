# EDITOR FS — DEVELOPMENT CONTINUATION PLAN

**Milestone Target**: v1.7.1 Maintenance & Release Hardening  
**Target Branch**: `dev/v1.7.1-hardening`  
**Base Commit**: `c867380` (Tree SHA: `3256cb74eb76618fb78105d8d213ef708ce493aa`)  
**Parity Target**: Dual Remotes (`origin` and `secondary`)  

---

## 1. Development Objectives

With v1.7.0 fully stabilized, verified on physical hardware (Realme RMX5003), and passing all 743 automated tests, development resumes with targeted hardening and UX improvements identified during the v1.7.0 independent audit:

```
[v1.7.0 Production Stable]
       │
       ▼ (Create dedicated branch: dev/v1.7.1-hardening)
 ┌─────────────────────────────────────────────────────────────┐
 │ Task 1: Export Progress Modal Dismissal Safeguard (P2)      │
 │ Prevent accidental sheet dismissal during hardware encode    │
 └─────────────────────────────────────────────────────────────┘
       │
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ Task 2: Empty Project Auto-Cleanup on Back Navigation (P2)  │
 │ Discard newly opened blank drafts with zero media on exit   │
 └─────────────────────────────────────────────────────────────┘
       │
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ Task 3: Speed Curve Touch Target Expansion for High-DPI (P3)│
 │ Expand Bezier anchor hit radius from 12dp to 24dp           │
 └─────────────────────────────────────────────────────────────┘
       │
       ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ Task 4: Regression Testing & Dual-Remote Synchronization    │
 │ Re-run 743+ tests, flutter analyze, and propose sync plan   │
 └─────────────────────────────────────────────────────────────┘
```

---

## 2. Detailed Task Breakdown

### Task 1: Export Modal Dismissal Safeguard (P2)
* **Problem**: In `TopNavigationBar` and `ActionToolbar`, `ExportModalSheet` is displayed via `showModalBottomSheet`. While exporting, tapping the backdrop or swiping down dismisses the sheet while `VideoExportEngine` continues rendering in the background. The user loses visual feedback of the export progress.
* **Solution**:
  1. In `ExportModalSheet`, wrap the view with `PopScope(canPop: !widget.viewModel.isExporting, onPopInvoked: ...)`.
  2. In `TopNavigationBar` and `ActionToolbar`, dynamically bind `isDismissible: !viewModel.isExporting` and `enableDrag: !viewModel.isExporting`.
* **Testing**:
  - Add unit/widget regression test in `test/widget/export_modal_sheet_test.dart` asserting that while `isExporting == true`, the modal cannot be dismissed via back navigation or barrier tap.

### Task 2: Empty Project Auto-Cleanup on Back Navigation (P2)
* **Problem**: When a user taps "New Project" and immediately backs out without importing clips, stickers, text, or audio, an empty draft file (`Project MM/DD HH:MM`) is permanently saved in the Recent Drafts list.
* **Solution**:
  1. Add `bool get isBlankProject` getter in `EditorViewModel` checking if all tracks (`videoClips`, `overlayClips`, `stickerOverlays`, `textOverlays`, `audioTracks`) are empty and duration is zero.
  2. On Back navigation in `TopNavigationBar`, if the project is a newly created blank draft, call `ProjectStorageService.instance.deleteProject(project.id)` instead of `saveCurrentProject()`.
* **Testing**:
  - Add test in `test/unit/project_storage_service_test.dart` and `test/unit/editor_view_model_draft_test.dart` validating that blank projects are discarded cleanly on exit.

### Task 3: Speed Curve High-DPI Touch Target Expansion (P3)
* **Problem**: On high-density devices (408+ dpi override), the touch target radius of Bezier anchor points in `SpeedAdjustmentSheet` is $12\text{ dp}$, requiring high precision to grab.
* **Solution**:
  1. Increase the invisible touch hit-target radius from $12\text{ dp}$ to $24\text{ dp}$ while preserving the sleek $6\text{ dp}$ visual circle rendering.
* **Testing**:
  - Update `test/unit/speed_curve_test.dart` to verify touch bounds.

---

## 3. Dual-Remote Synchronization Strategy

Once the hardening commits are finalized on `dev/v1.7.1-hardening`:
1. The new commits can be fast-forward merged into local `main`.
2. A clean synchronization plan will be prepared for both `origin` (`FS-Groupz/Editor-FS`) and `secondary` (`Almasyash/capcut-video-editor-flutter`).
3. Explicit user consent will be obtained before running any push commands.
