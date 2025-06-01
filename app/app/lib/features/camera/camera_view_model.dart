import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../shared/sessions/view_model/session_view_model.dart';
import '../shared/sessions/data/session_model.dart';
import '../shared/bluetooth/bluetooth_view_model.dart';

class CameraViewModel extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _errorMessage;

  // Sesión
  SessionViewModel? _sessionViewModel;

  // Control de tiros para evitar duplicados
  DateTime? _lastShotTime;

  // Grabación de video
  bool _isRecording = false;
  String _currentVideoPath = '';
  Timer? _videoBufferTimer;
  Directory? _videosDirectory;

  // Para acceder al BluetoothViewModel
  BluetoothViewModel? _bluetoothViewModel;

  // Control para intento de tiro con timeout
  bool _isWaitingForShot = false;
  Timer? _shotTimeoutTimer;

  // Getters
  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  bool get isWaitingForShot => _isWaitingForShot;

  CameraViewModel({
    SessionViewModel? sessionViewModel,
    BluetoothViewModel? bluetoothViewModel,
  }) : _sessionViewModel = sessionViewModel,
       _bluetoothViewModel = bluetoothViewModel {
    // Escuchar cambios en el BluetoothViewModel para detectar aciertos
    _bluetoothViewModel?.addListener(_onBluetoothDataChanged);
    _initializeVideoDirectory();
  }

  /// Inicializa el directorio de videos de forma permanente
  Future<void> _initializeVideoDirectory() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      _videosDirectory = Directory(path.join(documentsDir.path, 'shot_videos'));

      if (!await _videosDirectory!.exists()) {
        await _videosDirectory!.create(recursive: true);
        debugPrint('📁 Directorio de videos creado: ${_videosDirectory!.path}');
      } else {
        debugPrint(
          '📁 Directorio de videos existente: ${_videosDirectory!.path}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error al crear directorio de videos: $e');
    }
  }

  Future<void> initialize() async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Asegurar que el directorio de videos esté listo
      await _initializeVideoDirectory();

      // Obtener cámaras disponibles
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Inicializar controlador de cámara
      _cameraController = CameraController(
        _cameras[0], // Usar primera cámara (trasera)
        ResolutionPreset.medium, // Resolución media para mejor rendimiento
        enableAudio: false,
        imageFormatGroup:
            Platform.isIOS
                ? ImageFormatGroup.bgra8888
                : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      // Iniciar buffer de video usando el método robusto
      await _ensureVideoBufferIsActive();

      _isInitialized = true;
      debugPrint('✅ Cámara inicializada correctamente');
      if (_isRecording) {
        debugPrint('✅ Buffer de video activo después de inicialización');
      } else {
        debugPrint(
          '⚠️ Advertencia: Buffer de video no está activo después de inicialización',
        );
      }
    } catch (e) {
      _errorMessage = 'Error initializing camera: $e';
      debugPrint('❌ Error: $_errorMessage');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _onBluetoothDataChanged() {
    // Verificar si hubo un acierto detectado por el ESP32
    if (_bluetoothViewModel?.shotDetected == true && _isWaitingForShot) {
      debugPrint('🏀 ¡Acierto detectado por ESP32 durante timeout!');
      _shotTimeoutTimer?.cancel();
      _registerShotDetection(ShotDetectionType.sensor, isSuccessful: true);
      _isWaitingForShot = false;
      notifyListeners();
    }
  }

  /// Simula un tiro manual para testing (asegura que haya video)
  void simulateManualShot({bool isSuccessful = true}) {
    if (!_isInitialized || _sessionViewModel == null) {
      debugPrint(
        '⚠️ Cámara no inicializada o sesión no disponible para simular tiro',
      );
      return;
    }

    debugPrint(
      '🏀 Simulando tiro manual: ${isSuccessful ? "ACIERTO" : "FALLO"}',
    );
    _registerShotDetection(
      ShotDetectionType.manual,
      isSuccessful: isSuccessful,
    );
  }

  /// Simula un intento de tiro - espera 5 segundos para detectar respuesta del ESP32
  void simulateShotAttempt() {
    if (_isWaitingForShot) {
      debugPrint('⚠️ Ya hay un intento de tiro en proceso');
      return;
    }

    debugPrint('🏀 Iniciando intento de tiro - esperando 5 segundos...');
    _isWaitingForShot = true;
    notifyListeners();

    // Iniciar timeout de 5 segundos
    _shotTimeoutTimer = Timer(const Duration(seconds: 5), () {
      // Si llegamos aquí, no hubo detección de acierto
      debugPrint(
        '⏰ Timeout - No se detectó acierto del ESP32, registrando como fallo',
      );
      _registerShotDetection(ShotDetectionType.sensor, isSuccessful: false);
      _isWaitingForShot = false;
      notifyListeners();
    });
  }

  void onShotDetectedFromBluetooth() {
    debugPrint('🏀 Tiro detectado desde ESP32');

    // Verificar que no hemos registrado un tiro muy recientemente
    final now = DateTime.now();
    if (_lastShotTime == null || now.difference(_lastShotTime!).inSeconds > 3) {
      _lastShotTime = now;
      _registerShotDetection(ShotDetectionType.sensor, isSuccessful: true);
    }
  }

  void _registerShotDetection(
    ShotDetectionType detectionType, {
    required bool isSuccessful,
  }) {
    if (_sessionViewModel == null) return;

    debugPrint('🏀 Registrando tiro: ${isSuccessful ? "ACIERTO" : "FALLO"}');

    // Detener grabación si estamos grabando y guardar clip
    _stopRecordingAndSaveClip().then((videoPath) {
      // Registrar el tiro con el video y el resultado
      _sessionViewModel!.registerShot(
        isSuccessful: isSuccessful,
        videoPath: videoPath,
        detectionType: detectionType,
        confidenceScore: 0.9, // Alta confianza para sensores físicos
      );

      if (videoPath.isNotEmpty) {
        debugPrint('🎥 Video guardado permanentemente: $videoPath');
      } else {
        debugPrint('⚠️ No se pudo guardar el video');
      }
      debugPrint(
        '📊 Tiro registrado en sesión: ${isSuccessful ? "ACIERTO" : "FALLO"}',
      );
    });
  }

  // Inicia la grabación continua en buffer
  Future<void> _startVideoBuffer() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint(
        '❌ No se puede iniciar buffer de video: cámara no inicializada',
      );
      return;
    }

    if (_videosDirectory == null) {
      debugPrint('❌ Directorio de videos no inicializado');
      return;
    }

    // Si ya estamos grabando, detener primero la grabación actual
    if (_isRecording) {
      debugPrint('⚠️ Ya hay una grabación en curso, deteniendola primero...');
      try {
        await _cameraController!.stopVideoRecording();
        _isRecording = false;
        debugPrint('✅ Grabación anterior detenida correctamente');
      } catch (e) {
        debugPrint('⚠️ Error al detener grabación anterior: $e');
        _isRecording = false; // Forzar el estado a false
      }

      // Pequeña pausa para estabilizar el controlador
      await Future.delayed(Duration(milliseconds: 200));
    }

    try {
      // Usar directorio temporal para el buffer
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentVideoPath = path.join(tempDir.path, 'buffer_$timestamp.mp4');

      await _cameraController!.startVideoRecording();
      _isRecording = true;

      debugPrint('🎥 Buffer de video iniciado en: $_currentVideoPath');

      // Reiniciar el buffer cada 30 segundos para mantenerlo actualizado
      _videoBufferTimer?.cancel(); // Cancelar timer anterior si existe
      _videoBufferTimer = Timer.periodic(Duration(seconds: 30), (_) async {
        if (_isRecording &&
            _cameraController != null &&
            _cameraController!.value.isInitialized) {
          await _restartVideoBuffer();
        }
      });
    } catch (e) {
      debugPrint('❌ Error al iniciar buffer de video: $e');
      _isRecording = false;

      // Si el error es porque ya se está grabando, intentar obtener el estado correcto
      if (e.toString().contains('recording')) {
        debugPrint('🔍 Verificando estado real de grabación...');
        try {
          // Intentar detener cualquier grabación existente
          await _cameraController!.stopVideoRecording();
          debugPrint('✅ Grabación fantasma detenida');

          // Esperar un momento y reintentar
          await Future.delayed(Duration(milliseconds: 500));
          await _startVideoBuffer();
        } catch (e2) {
          debugPrint('❌ Error al manejar grabación fantasma: $e2');
        }
      }
    }
  }

  // Reinicia el buffer de video para mantenerlo actualizado
  Future<void> _restartVideoBuffer() async {
    if (!_isRecording ||
        _cameraController == null ||
        _videosDirectory == null ||
        !_cameraController!.value.isInitialized) {
      debugPrint('⚠️ No se puede reiniciar buffer: condiciones no cumplidas');
      return;
    }

    try {
      debugPrint('🔄 Reiniciando buffer periódico...');

      // Detener la grabación actual de forma controlada
      await _cameraController!.stopVideoRecording();
      _isRecording = false;

      // Pequeña pausa para estabilizar
      await Future.delayed(Duration(milliseconds: 300));

      // Iniciar nueva grabación usando el método robusto
      await _ensureVideoBufferIsActive();

      if (_isRecording) {
        debugPrint('✅ Buffer reiniciado exitosamente');
      } else {
        debugPrint('⚠️ Buffer no se pudo reiniciar correctamente');
      }
    } catch (e) {
      debugPrint('❌ Error al reiniciar buffer de video: $e');
      _isRecording = false;

      // Intentar recuperar usando el método robusto
      try {
        await _ensureVideoBufferIsActive();
      } catch (e2) {
        debugPrint('❌ Error crítico al recuperar buffer: $e2');
      }
    }
  }

  // Detiene la grabación y guarda el clip en ubicación permanente
  Future<String> _stopRecordingAndSaveClip() async {
    if (_videosDirectory == null) {
      debugPrint('❌ Directorio de videos no disponible');
      return '';
    }

    // Si no estamos grabando, intentar obtener el último buffer disponible
    if (!_isRecording || _cameraController == null) {
      debugPrint('⚠️ No hay grabación activa para guardar');
      debugPrint('   - _isRecording: $_isRecording');
      debugPrint('   - _cameraController: ${_cameraController != null}');
      debugPrint('   - _videosDirectory: ${_videosDirectory != null}');

      // Intentar reiniciar el buffer para futuros tiros
      await _startVideoBuffer();
      return '';
    }

    try {
      debugPrint('🎥 Iniciando proceso de guardado de video...');

      // Detener la grabación actual
      final videoFile = await _cameraController!.stopVideoRecording();
      _isRecording = false;
      debugPrint('🎥 Grabación detenida, archivo temporal: ${videoFile.path}');

      // Crear nombre único para el archivo permanente
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      var permanentPath = path.join(
        _videosDirectory!.path,
        'shot_$timestamp.mp4',
      );
      debugPrint('🎥 Ruta permanente planificada: $permanentPath');

      // Verificar que el archivo temporal existe
      final tempFile = File(videoFile.path);
      if (!await tempFile.exists()) {
        debugPrint('❌ Archivo temporal no encontrado: ${videoFile.path}');
        await _startVideoBuffer(); // Reiniciar buffer
        return '';
      }

      final tempFileSize = await tempFile.length();
      debugPrint(
        '📁 Archivo temporal encontrado: ${videoFile.path} (${tempFileSize} bytes)',
      );

      // Copiar el archivo a la ubicación permanente
      debugPrint('📋 Iniciando copia a ubicación permanente...');
      await tempFile.copy(permanentPath);
      debugPrint('📋 Copia completada');

      // Verificar que la copia fue exitosa
      final permanentFile = File(permanentPath);
      if (await permanentFile.exists()) {
        final fileSize = await permanentFile.length();
        debugPrint(
          '✅ Video copiado exitosamente: $permanentPath (${fileSize} bytes)',
        );

        // Verificar que los tamaños coinciden
        if (fileSize == tempFileSize) {
          debugPrint('✅ Verificación de integridad exitosa: tamaños coinciden');
        } else {
          debugPrint(
            '⚠️ Advertencia: tamaños no coinciden (original: $tempFileSize, copia: $fileSize)',
          );
        }

        // Eliminar archivo temporal
        try {
          await tempFile.delete();
          debugPrint('🗑️ Archivo temporal eliminado: ${videoFile.path}');
        } catch (e) {
          debugPrint('⚠️ No se pudo eliminar archivo temporal: $e');
        }
      } else {
        debugPrint(
          '❌ La copia del archivo falló - archivo no existe en destino',
        );
        permanentPath = ''; // Retornar string vacío si falló
      }

      // Reiniciar el buffer de video inmediatamente para continuar grabando
      debugPrint('🔄 Reiniciando buffer de video inmediatamente...');
      await _ensureVideoBufferIsActive();

      return permanentPath;
    } catch (e) {
      debugPrint('❌ Error al guardar clip de video: $e');
      debugPrint('❌ Stack trace: ${StackTrace.current}');
      _isRecording = false;
      // Intentar reiniciar el buffer
      await _ensureVideoBufferIsActive();
      return '';
    }
  }

  /// Asegura que el buffer de video esté activo, reintentando si es necesario
  Future<void> _ensureVideoBufferIsActive() async {
    // Si ya estamos grabando, no hacer nada
    if (_isRecording &&
        _cameraController != null &&
        _cameraController!.value.isInitialized) {
      debugPrint('✅ Buffer de video ya está activo');
      return;
    }

    debugPrint('🔄 Asegurando que el buffer de video esté activo...');

    // Reintentar hasta 3 veces si es necesario
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await _startVideoBuffer();
        if (_isRecording) {
          debugPrint('✅ Buffer de video activado en intento $attempt');
          return;
        }
      } catch (e) {
        debugPrint('❌ Error en intento $attempt de activar buffer: $e');
        if (attempt < 3) {
          // Esperar un poco antes del siguiente intento
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
    }

    debugPrint('❌ No se pudo activar el buffer de video después de 3 intentos');
  }

  /// Método para obtener la ruta de todos los videos guardados (para debug)
  Future<List<String>> getStoredVideos() async {
    if (_videosDirectory == null) return [];

    try {
      final files = await _videosDirectory!.list().toList();
      return files
          .where((file) => file is File && file.path.endsWith('.mp4'))
          .map((file) => file.path)
          .toList();
    } catch (e) {
      debugPrint('❌ Error al listar videos: $e');
      return [];
    }
  }

  /// Método para limpiar videos antiguos (opcional, para evitar uso excesivo de almacenamiento)
  Future<void> cleanOldVideos({int maxAgeInDays = 30}) async {
    if (_videosDirectory == null) return;

    try {
      final files = await _videosDirectory!.list().toList();
      final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeInDays));

      for (final file in files) {
        if (file is File && file.path.endsWith('.mp4')) {
          final fileStat = await file.stat();
          if (fileStat.modified.isBefore(cutoffDate)) {
            await file.delete();
            debugPrint('🗑️ Video antiguo eliminado: ${file.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error al limpiar videos antiguos: $e');
    }
  }

  @override
  void dispose() {
    _videoBufferTimer?.cancel();
    _shotTimeoutTimer?.cancel();
    _bluetoothViewModel?.removeListener(_onBluetoothDataChanged);

    // Detener grabación de forma segura si está activa
    if (_isRecording && _cameraController != null) {
      try {
        _cameraController!
            .stopVideoRecording()
            .then((_) {
              debugPrint('🎥 Grabación detenida correctamente en dispose');
            })
            .catchError((e) {
              debugPrint('⚠️ Error al detener grabación en dispose: $e');
              return null; // Retornar null para cumplir con el tipo Future<XFile>
            });
      } catch (e) {
        debugPrint('⚠️ Error sincrónico al detener grabación en dispose: $e');
      }
    }

    _cameraController?.dispose();
    super.dispose();
  }
}
