import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

import 'session_model.dart';

class SessionRepository {
  static const String _sessionsBoxName = 'sessions';
  static const String _videosFolderName = 'shot_videos';
  late Box<SessionModel> _sessionsBox;
  late Directory _videosDirectory;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    // Inicializar Hive
    await Hive.initFlutter();
    
    // Registrar adaptadores
    Hive.registerAdapter(SessionModelAdapter());
    Hive.registerAdapter(ShotClipAdapter());
    Hive.registerAdapter(ShotDetectionTypeAdapter());
    
    // Abrir la box
    _sessionsBox = await Hive.openBox<SessionModel>(_sessionsBoxName);
    
    // Crear directorio para videos
    final documentsDir = await getApplicationDocumentsDirectory();
    _videosDirectory = Directory(path.join(documentsDir.path, _videosFolderName));
    if (!await _videosDirectory.exists()) {
      await _videosDirectory.create(recursive: true);
    }
    
    _isInitialized = true;
  }
  
  Future<void> saveSession(SessionModel session) async {
    await _ensureInitialized();
    await _sessionsBox.put(session.id, session);
  }
  
  Future<List<SessionModel>> getAllSessions() async {
    await _ensureInitialized();
    return _sessionsBox.values.toList();
  }
  
  Future<SessionModel?> getSessionById(String id) async {
    await _ensureInitialized();
    return _sessionsBox.get(id);
  }
  
  Future<void> deleteSession(String id) async {
    await _ensureInitialized();
    final session = _sessionsBox.get(id);
    
    if (session != null) {
      // Eliminar videos asociados
      for (final clip in session.shotClips) {
        final videoFile = File(clip.videoPath);
        if (await videoFile.exists()) {
          await videoFile.delete();
        }
      }
      
      // Eliminar la sesión
      await _sessionsBox.delete(id);
    }
  }
  
  Future<String> getNewVideoFilePath() async {
    await _ensureInitialized();
    return path.join(_videosDirectory.path, '${DateTime.now().millisecondsSinceEpoch}.mp4');
  }
  
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }
  
  Future<void> close() async {
    if (_isInitialized) {
      await _sessionsBox.close();
      _isInitialized = false;
    }
  }
}
