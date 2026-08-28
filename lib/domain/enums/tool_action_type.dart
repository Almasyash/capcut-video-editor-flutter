import 'package:flutter/material.dart';

/// Primary toolbar actions and categories in CapCut editor
enum ToolActionType {
  split('Split', Icons.call_split_rounded),
  trimLeft('Trim Left', Icons.align_horizontal_left_rounded),
  trimRight('Trim Right', Icons.align_horizontal_right_rounded),
  delete('Delete', Icons.delete_outline_rounded),
  duplicate('Duplicate', Icons.copy_all_rounded),
  speed('Speed', Icons.speed_rounded),
  volume('Volume', Icons.volume_up_rounded),
  filter('Filters', Icons.auto_awesome_rounded),
  effects('Effects', Icons.blur_on_rounded),
  addClip('Add Clip', Icons.add_photo_alternate_outlined),
  export('Export', Icons.file_upload_outlined);

  const ToolActionType(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Bottom tab category items
enum EditorCategory {
  edit('Edit', Icons.content_cut_rounded),
  audio('Audio', Icons.music_note_rounded),
  text('Text', Icons.title_rounded),
  stickers('Stickers', Icons.emoji_emotions_outlined),
  effects('Effects', Icons.auto_fix_high_rounded),
  filters('Filters', Icons.photo_filter_rounded),
  adjust('Adjust', Icons.tune_rounded);

  const EditorCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}
