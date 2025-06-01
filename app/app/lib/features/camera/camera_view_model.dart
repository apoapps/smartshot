import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  }

  Future<void> initialize() async {
    _isInitializing = true;
    _errorMessage = null;
    notifyListeners();

    try {
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

      // Iniciar buffer de video
      await _startVideoBuffer();

      _isInitialized = true;
      debugPrint('✅ Cámara inicializada correctamente');
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

    // Detener grabación si estamos grabando
    _stopRecordingAndSaveClip().then((videoPath) {
      // Registrar el tiro con el video y el resultado
      _sessionViewModel!.registerShot(
        isSuccessful: isSuccessful,
        videoPath: videoPath,
        detectionType: detectionType,
        confidenceScore: 0.9, // Alta confianza para sensores físicos
      );

      debugPrint('🎥 Video guardado: $videoPath');
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

    if (_isRecording) {
      debugPrint('⚠️ Ya hay una grabación en curso');
      return;
    }

    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentVideoPath = '${directory.path}/buffer_$timestamp.mp4';

      await _cameraController!.startVideoRecording();
      _isRecording = true;

      debugPrint('🎥 Buffer de video iniciado');

      // Reiniciar el buffer cada 30 segundos para mantenerlo actualizado
      _videoBufferTimer = Timer.periodic(Duration(seconds: 30), (_) async {
        if (_isRecording) {
          await _restartVideoBuffer();
        }
      });
    } catch (e) {
      debugPrint('❌ Error al iniciar buffer de video: $e');
    }
  }

  // Reinicia el buffer de video para mantenerlo actualizado
  Future<void> _restartVideoBuffer() async {
    if (!_isRecording || _cameraController == null) return;

    try {
      // Detener la grabación actual
      await _cameraController!.stopVideoRecording();

      // Iniciar una nueva grabación
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentVideoPath = '${directory.path}/buffer_$timestamp.mp4';

      await _cameraController!.startVideoRecording();
      debugPrint('🔄 Buffer de video reiniciado');
    } catch (e) {
      debugPrint('❌ Error al reiniciar buffer de video: $e');
      _isRecording = false;
    }
  }

  // Detiene la grabación y guarda el clip
  Future<String> _stopRecordingAndSaveClip() async {
    if (!_isRecording || _cameraController == null) {
      debugPrint('⚠️ No hay grabación activa para guardar');
      return '';
    }

    try {
      final videoFile = await _cameraController!.stopVideoRecording();
      _isRecording = false;

      // Guardar el video en un lugar permanente
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final permanentPath = '${directory.path}/shot_$timestamp.mp4';

      // Copiar el archivo a la ubicación permanente
      await File(videoFile.path).copy(permanentPath);

      // Reiniciar el buffer de video
      _startVideoBuffer();

      return permanentPath;
    } catch (e) {
      debugPrint('❌ Error al guardar clip de video: $e');
      // Intentar reiniciar el buffer
      _startVideoBuffer();
      return '';
    }
  }

  void dispose() {
    _videoBufferTimer?.cancel();
    _shotTimeoutTimer?.cancel();
    _bluetoothViewModel?.removeListener(_onBluetoothDataChanged);
    if (_isRecording && _cameraController != null) {
      _cameraController!.stopVideoRecording();
    }
    _cameraController?.dispose();
    super.dispose();
  }
}
