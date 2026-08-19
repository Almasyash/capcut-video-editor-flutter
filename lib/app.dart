import 'package:flutter/material.dart';
import 'package:capcut_video_editor/core/theme/app_theme.dart';
import 'package:capcut_video_editor/ui/features/editor/views/editor_screen.dart';

/// Root application widget
class CapCutVideoEditorApp extends StatelessWidget {
  const CapCutVideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CapCut Video Editor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const EditorScreen(),
    );
  }
}
