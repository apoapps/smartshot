import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../shared/sessions/view_model/session_view_model.dart';
import '../shared/sessions/data/session_model.dart';
import '../shared/bluetooth/bluetooth_view_model.dart';
import '../shared/watch/watch_service.dart';

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
  
  // Apple Watch Service
  WatchService _watchService = WatchService();
  StreamSubscription<DateTime>? _watchShotSubscription;
  
  // Getters
  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;

  CameraViewModel({
    SessionViewModel? sessionViewModel, 
    BluetoothViewModel? bluetoothViewModel
  }) : 
    _sessionViewModel = sessionViewModel,
    _bluetoothViewModel = bluetoothViewModel;

  Future<void> initialize() async {
    if (_isInitializing || _isInitialized) return;
    
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
        imageFormatGroup: Platform.isIOS 
            ? ImageFormatGroup.bgra8888 
            : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      // Iniciar buffer de video
      await _startVideoBuffer();
      
      // Inicializar Watch Service
      await _watchService.initialize();
      
      // Configurar suscripción a detecciones de tiro desde el Apple Watch
      _watchShotSubscription = _watchService.onShotDetected.listen((timestamp) {
        _onShotDetectedFromWatch(timestamp);
      });

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
  
  void _onShotDetectedFromWatch(DateTime timestamp) {
    debugPrint('🏀 Tiro detectado desde Apple Watch: $timestamp');
    
    // Verificar que no hemos registrado un tiro muy recientemente
    final now = DateTime.now();
    if (_lastShotTime == null || now.difference(_lastShotTime!).inSeconds > 3) {
      _lastShotTime = now;
      // Usar sensor temporalmente hasta que se pueda regenerar el archivo .g.dart
      _registerShotDetection(ShotDetectionType.sensor);
    }
  }
  
  void onShotDetectedFromBluetooth() {
    debugPrint('🏀 Tiro detectado desde sensor Bluetooth');
    
    // Verificar que no hemos registrado un tiro muy recientemente
    final now = DateTime.now();
    if (_lastShotTime == null || now.difference(_lastShotTime!).inSeconds > 3) {
      _lastShotTime = now;
      _registerShotDetection(ShotDetectionType.sensor);
    }
  }

  void _registerShotDetection(ShotDetectionType detectionType) {
    if (_sessionViewModel == null) return;
    
    debugPrint('🏀 Iniciando registro de tiro');
    
    // Detener grabación si estamos grabando
    _stopRecordingAndSaveClip().then((videoPath) {
      // Verificar si el bluetooth detectó un acierto
      final isSuccessful = _bluetoothViewModel?.shotDetected ?? false;
      
      debugPrint('🎯 Tiro detectado - Acierto: ${isSuccessful ? 'SÍ' : 'NO'} (según sensor Bluetooth)');
      
      // Registrar el tiro con el video y el resultado del sensor
      _sessionViewModel!.registerShot(
        isSuccessful: isSuccessful,
        videoPath: videoPath,
        detectionType: detectionType,
        confidenceScore: 0.9, // Alta confianza para sensores físicos
      );
      
      debugPrint('🎥 Video guardado: $videoPath');
      debugPrint('📊 Tiro registrado en sesión');
    });
  }
  
  // Inicia la grabación continua en buffer
  Future<void> _startVideoBuffer() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      debugPrint('❌ No se puede iniciar buffer de video: cámara no inicializada');
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
  
  // Iniciar monitoreo desde el Apple Watch
  Future<void> startWatchMonitoring() async {
    await _watchService.startWatchMonitoring();
    debugPrint('⌚ Monitoreo de Apple Watch iniciado');
  }
  
  // Detener monitoreo desde el Apple Watch
  Future<void> stopWatchMonitoring() async {
    await _watchService.stopWatchMonitoring();
    debugPrint('⌚ Monitoreo de Apple Watch detenido');
  }

  void dispose() {
    _videoBufferTimer?.cancel();
    if (_isRecording && _cameraController != null) {
      _cameraController!.stopVideoRecording();
    }
    _watchShotSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }
} 