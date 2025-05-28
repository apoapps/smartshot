// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionModelAdapter extends TypeAdapter<SessionModel> {
  @override
  final int typeId = 0;

  @override
  SessionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionModel(
      id: fields[0] as String?,
      dateTime: fields[1] as DateTime,
      durationInSeconds: fields[2] as int,
      totalShots: fields[3] as int,
      successfulShots: fields[4] as int,
      shotClips: (fields[5] as List).cast<ShotClip>(),
    );
  }

  @override
  void write(BinaryWriter writer, SessionModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.dateTime)
      ..writeByte(2)
      ..write(obj.durationInSeconds)
      ..writeByte(3)
      ..write(obj.totalShots)
      ..writeByte(4)
      ..write(obj.successfulShots)
      ..writeByte(5)
      ..write(obj.shotClips);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ShotClipAdapter extends TypeAdapter<ShotClip> {
  @override
  final int typeId = 1;

  @override
  ShotClip read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ShotClip(
      id: fields[0] as String?,
      timestamp: fields[1] as DateTime,
      isSuccessful: fields[2] as bool,
      videoPath: fields[3] as String,
      confidenceScore: fields[4] as double?,
      detectionType: fields[5] as ShotDetectionType,
    );
  }

  @override
  void write(BinaryWriter writer, ShotClip obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.timestamp)
      ..writeByte(2)
      ..write(obj.isSuccessful)
      ..writeByte(3)
      ..write(obj.videoPath)
      ..writeByte(4)
      ..write(obj.confidenceScore)
      ..writeByte(5)
      ..write(obj.detectionType);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShotClipAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ShotDetectionTypeAdapter extends TypeAdapter<ShotDetectionType> {
  @override
  final int typeId = 2;

  @override
  ShotDetectionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ShotDetectionType.sensor;
      case 1:
        return ShotDetectionType.camera;
      case 2:
        return ShotDetectionType.manual;
      case 3:
        return ShotDetectionType.watch;
      default:
        return ShotDetectionType.sensor;
    }
  }

  @override
  void write(BinaryWriter writer, ShotDetectionType obj) {
    switch (obj) {
      case ShotDetectionType.sensor:
        writer.writeByte(0);
        break;
      case ShotDetectionType.camera:
        writer.writeByte(1);
        break;
      case ShotDetectionType.manual:
        writer.writeByte(2);
        break;
      case ShotDetectionType.watch:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShotDetectionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
