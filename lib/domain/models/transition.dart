import 'package:uuid/uuid.dart';
import 'package:capcut_video_editor/domain/enums/transition_type.dart';

class Transition {
  final String id;
  final TransitionType type;
  final double duration; // seconds
  final String leftClipId;
  final String rightClipId;
  final bool enabled;

  Transition({
    String? id,
    required this.type,
    required this.duration,
    required this.leftClipId,
    required this.rightClipId,
    this.enabled = true,
  }) : id = id ?? const Uuid().v4();

  Transition copyWith({
    TransitionType? type,
    double? duration,
    bool? enabled,
  }) => Transition(
        id: id,
        type: type ?? this.type,
        duration: duration ?? this.duration,
        leftClipId: leftClipId,
        rightClipId: rightClipId,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'duration': duration,
        'leftClipId': leftClipId,
        'rightClipId': rightClipId,
        'enabled': enabled,
      };

  factory Transition.fromJson(Map<String, dynamic> json) => Transition(
        id: json['id'] as String?,
        type: TransitionType.values.firstWhere(
            (e) => e.name == (json['type'] as String? ?? 'none')),
        duration: (json['duration'] as num).toDouble(),
        leftClipId: json['leftClipId'] as String,
        rightClipId: json['rightClipId'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );
}
