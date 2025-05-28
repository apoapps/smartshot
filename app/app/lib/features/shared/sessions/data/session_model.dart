import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'session_model.g.dart';

@HiveType(typeId: 0)
class SessionModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime dateTime;

  @HiveField(2)
  final int durationInSeconds;

  @HiveField(3)
  final int totalShots;

  @HiveField(4)
  final int successfulShots;

  @HiveField(5)
  final List<ShotClip> shotClips;

  SessionModel({
    String? id,
    required this.dateTime,
    required this.durationInSeconds,
    required this.totalShots,
    required this.successfulShots,
    required this.shotClips,
  }) : id = id ?? const Uuid().v4();

  int get missedShots => totalShots - successfulShots;
  
  double get successRate => totalShots > 0 
      ? (successfulShots / totalShots) * 100 
      : 0.0;
}

@HiveType(typeId: 1)
class ShotClip extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final DateTime timestamp;

  @HiveField(2)
  final bool isSuccessful;

  @HiveField(3)
  final String videoPath;

  @HiveField(4)
  final double? confidenceScore;

  @HiveField(5)
  final ShotDetectionType detectionType;

  ShotClip({
    String? id,
    required this.timestamp,
    required this.isSuccessful,
    required this.videoPath,
    this.confidenceScore,
    required this.detectionType,
  }) : id = id ?? const Uuid().v4();
}

@HiveType(typeId: 2)
enum ShotDetectionType {
  @HiveField(0)
  sensor,
  
  @HiveField(1)
  camera,
  
  @HiveField(2)
  manual,
  
  @HiveField(3)
  watch
} 