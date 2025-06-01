import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

import 'session_model.dart';

class SessionRepository {
  static const String _sessionsBoxName = 'sessions';
  static const String _videosFolderName = 'shot_videos';
  late Box<SessionModel> _sessionsBox;
  late Directory _videosDirectory;
  bool _isInitialized = false;

  /// Inicializa el repositorio y configura el almacenamiento
  Future<void> init() async {
    if (_isInitialized) {
      debugPrint('📦 SessionRepository ya inicializado');
      return;
    }

    try {
      debugPrint('📦 Inicializando SessionRepository...');

      // Inicializar Hive
      await Hive.initFlutter();

      // Registrar adaptadores si no están registrados
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(SessionModelAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(ShotClipAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(ShotDetectionTypeAdapter());
      }

      // Abrir la box
      _sessionsBox = await Hive.openBox<SessionModel>(_sessionsBoxName);
      debugPrint(
        '📦 Box de sesiones abierta: ${_sessionsBox.length} sesiones encontradas',
      );

      // Crear directorio para videos
      await _createVideosDirectory();

      // Verificar integridad de datos existentes
      await _verifyDataIntegrity();

      _isInitialized = true;
      debugPrint('✅ SessionRepository inicializado correctamente');
    } catch (e) {
      debugPrint('❌ Error al inicializar SessionRepository: $e');
      rethrow;
    }
  }

  /// Crea el directorio de videos si no existe
  Future<void> _createVideosDirectory() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _videosDirectory = Directory(
        path.join(documentsDir.path, _videosFolderName),
      );

      if (!await _videosDirectory.exists()) {
        await _videosDirectory.create(recursive: true);
        debugPrint('📁 Directorio de videos creado: ${_videosDirectory.path}');
      } else {
        debugPrint(
          '📁 Directorio de videos existente: ${_videosDirectory.path}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error al crear directorio de videos: $e');
      rethrow;
    }
  }

  /// Verifica la integridad de los datos almacenados
  Future<void> _verifyDataIntegrity() async {
    try {
      int corruptedSessions = 0;
      int missingVideos = 0;

      final sessions = _sessionsBox.values.toList();

      for (final session in sessions) {
        if (session.id.isEmpty || session.shotClips.isEmpty) {
          continue; // Saltar sesiones sin clips
        }

        for (final clip in session.shotClips) {
          if (clip.videoPath.isNotEmpty) {
            final videoFile = File(clip.videoPath);
            if (!await videoFile.exists()) {
              missingVideos++;
              debugPrint('⚠️ Video faltante: ${clip.videoPath}');
            }
          }
        }
      }

      if (missingVideos > 0) {
        debugPrint(
          '⚠️ Se encontraron $missingVideos videos faltantes de ${sessions.length} sesiones',
        );
      } else {
        debugPrint(
          '✅ Verificación de integridad completada: todos los videos están presentes',
        );
      }
    } catch (e) {
      debugPrint('❌ Error en verificación de integridad: $e');
    }
  }

  /// Guarda una sesión en el almacenamiento persistente
  Future<void> saveSession(SessionModel session) async {
    await _ensureInitialized();

    try {
      // Validar que la sesión tenga datos válidos
      if (session.id.isEmpty) {
        throw Exception('ID de sesión inválido');
      }

      // Verificar que los videos existen antes de guardar
      for (final clip in session.shotClips) {
        if (clip.videoPath.isNotEmpty) {
          final videoFile = File(clip.videoPath);
          if (!await videoFile.exists()) {
            debugPrint(
              '⚠️ Video no encontrado al guardar sesión: ${clip.videoPath}',
            );
            // Nota: No lanzamos error aquí, solo advertimos
          }
        }
      }

      await _sessionsBox.put(session.id, session);
      debugPrint(
        '💾 Sesión guardada: ${session.id} con ${session.shotClips.length} clips',
      );
    } catch (e) {
      debugPrint('❌ Error al guardar sesión: $e');
      rethrow;
    }
  }

  /// Obtiene todas las sesiones guardadas, ordenadas por fecha
  Future<List<SessionModel>> getAllSessions() async {
    await _ensureInitialized();

    try {
      final sessions = _sessionsBox.values.toList();
      // Ordenar por fecha, más recientes primero
      sessions.sort((a, b) => b.dateTime.compareTo(a.dateTime));

      debugPrint('📋 Cargadas ${sessions.length} sesiones');
      return sessions;
    } catch (e) {
      debugPrint('❌ Error al cargar sesiones: $e');
      return [];
    }
  }

  /// Obtiene una sesión específica por ID
  Future<SessionModel?> getSessionById(String id) async {
    await _ensureInitialized();

    try {
      return _sessionsBox.get(id);
    } catch (e) {
      debugPrint('❌ Error al obtener sesión $id: $e');
      return null;
    }
  }

  /// Elimina una sesión y sus videos asociados
  Future<void> deleteSession(String id) async {
    await _ensureInitialized();

    try {
      final session = _sessionsBox.get(id);

      if (session != null) {
        // Eliminar videos asociados
        int deletedVideos = 0;
        for (final clip in session.shotClips) {
          if (clip.videoPath.isNotEmpty) {
            final videoFile = File(clip.videoPath);
            if (await videoFile.exists()) {
              await videoFile.delete();
              deletedVideos++;
              debugPrint('🗑️ Video eliminado: ${clip.videoPath}');
            }
          }
        }

        // Eliminar la sesión de la base de datos
        await _sessionsBox.delete(id);
        debugPrint(
          '🗑️ Sesión eliminada: $id ($deletedVideos videos eliminados)',
        );
      } else {
        debugPrint('⚠️ Sesión no encontrada para eliminar: $id');
      }
    } catch (e) {
      debugPrint('❌ Error al eliminar sesión $id: $e');
      rethrow;
    }
  }

  /// Genera una nueva ruta para un archivo de video
  Future<String> getNewVideoFilePath() async {
    await _ensureInitialized();

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      return path.join(_videosDirectory.path, 'shot_$timestamp.mp4');
    } catch (e) {
      debugPrint('❌ Error al generar ruta de video: $e');
      rethrow;
    }
  }

  /// Obtiene estadísticas del almacenamiento
  Future<Map<String, dynamic>> getStorageStats() async {
    await _ensureInitialized();

    try {
      final sessions = await getAllSessions();
      int totalVideos = 0;
      int existingVideos = 0;
      int totalSize = 0;

      for (final session in sessions) {
        for (final clip in session.shotClips) {
          if (clip.videoPath.isNotEmpty) {
            totalVideos++;
            final videoFile = File(clip.videoPath);
            if (await videoFile.exists()) {
              existingVideos++;
              final fileSize = await videoFile.length();
              totalSize += fileSize;
            }
          }
        }
      }

      return {
        'totalSessions': sessions.length,
        'totalVideos': totalVideos,
        'existingVideos': existingVideos,
        'missingVideos': totalVideos - existingVideos,
        'totalSizeBytes': totalSize,
        'totalSizeMB': totalSize / (1024 * 1024),
        'videosDirectory': _videosDirectory.path,
      };
    } catch (e) {
      debugPrint('❌ Error al obtener estadísticas: $e');
      return {};
    }
  }

  /// Limpia videos huérfanos (videos que no están referenciados en ninguna sesión)
  Future<int> cleanOrphanedVideos() async {
    await _ensureInitialized();

    try {
      final sessions = await getAllSessions();
      final referencedVideos = <String>{};

      // Recopilar todas las rutas de video referenciadas
      for (final session in sessions) {
        for (final clip in session.shotClips) {
          if (clip.videoPath.isNotEmpty) {
            referencedVideos.add(clip.videoPath);
          }
        }
      }

      // Listar todos los archivos de video en el directorio
      final videoFiles = await _videosDirectory.list().toList();
      int deletedCount = 0;

      for (final file in videoFiles) {
        if (file is File && file.path.endsWith('.mp4')) {
          if (!referencedVideos.contains(file.path)) {
            await file.delete();
            deletedCount++;
            debugPrint('🗑️ Video huérfano eliminado: ${file.path}');
          }
        }
      }

      debugPrint(
        '🧹 Limpieza completada: $deletedCount videos huérfanos eliminados',
      );
      return deletedCount;
    } catch (e) {
      debugPrint('❌ Error al limpiar videos huérfanos: $e');
      return 0;
    }
  }

  /// Asegura que el repositorio esté inicializado
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// Cierra el repositorio y libera recursos
  Future<void> close() async {
    if (_isInitialized) {
      await _sessionsBox.close();
      _isInitialized = false;
      debugPrint('📦 SessionRepository cerrado');
    }
  }

  /// Verifica si el repositorio está inicializado
  bool get isInitialized => _isInitialized;

  /// Obtiene la ruta del directorio de videos
  String get videosDirectoryPath => _videosDirectory.path;
}
