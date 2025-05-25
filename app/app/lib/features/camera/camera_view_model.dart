import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:circular_buffer/circular_buffer.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:app/features/shared/sessions/data/session_model.dart';
import 'package:app/features/shared/sessions/data/session_repository.dart';
import 'package:app/features/shared/bluetooth/bluetooth_view_model.dart';
import 'package:app/features/shared/sessions/view_model/session_view_model.dart';

class BallDetection {
  final Offset center;
  final double radius;
  final double confidence;

  BallDetection({
    required this.center,
    required this.radius,
    required this.confidence,
  });
}

class CameraViewModel extends ChangeNotifier {
  // Dependencias
  final SessionRepository _sessionRepository;
  final BluetoothViewModel _bluetoothViewModel;
  final SessionViewModel? _sessionViewModel;
  
  // Variables de la cámara
  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  bool isInitialized = false;
  bool isLoading = false;
  String? errorMessage;
  
  // Variables para la detección del balón
  bool isProcessingFrame = false;
  BallDetection? detectedBall;
  bool isDetectionEnabled = true;
  
  // Variables para la grabación continua con buffer
  bool _isContinuousRecording = false;
  Timer? _recordingTimer;
  CircularBuffer<String> _videoBuffer = CircularBuffer(3); // Buffer para 3 segmentos de ~3-4 segundos cada uno
  String? _currentRecordingPath;
  DateTime? _currentSegmentStartTime;
  int _segmentCounter = 0;
  
  // Variables para detección de tiros
  bool isRecordingVideo = false;
  XFile? currentRecordingFile;
  DateTime? _recordingStartTime;
  
  // Buffer circular para almacenar detecciones recientes
  final int _bufferDurationSeconds = 30;
  bool _isShotDetected = false;
  bool _wasBasketballInMotion = false;
  DateTime? _basketballMotionStartTime;
  DateTime? _lastDistanceTriggerTime;
  DateTime? _lastShotDetectionTime;
  CircularBuffer<BallDetection?> _detectionBuffer = CircularBuffer(60); // Detección cada 0.5 segundos
  
  // Contador local de aciertos
  int _successfulShots = 0;
  int _totalShots = 0;

  // Umbral de distancia para considerar un tiro
  final double _distanciaUmbral = 50.0;
  
  // Almacenar el último frame procesado
  Uint8List? lastProcessedFrame;

  // Control de velocidad de muestreo
  final int _targetFps = 30; // 30 fotogramas por segundo
  DateTime? _lastFrameProcessTime;

  CameraViewModel(this._sessionRepository, this._bluetoothViewModel, [this._sessionViewModel]) {
    // Suscribirse a las actualizaciones del sensor
    _bluetoothViewModel.addListener(_handleSensorUpdate);
  }

  int get successfulShots => _successfulShots;
  int get totalShots => _totalShots;

  void _handleSensorUpdate() {
    // Verificar si se detectó un acierto desde el bluetooth
    if (_bluetoothViewModel.shotDetected) {
      _handleShotDetected(true, ShotDetectionType.sensor);
      return;
    }
    
    // Verificar la distancia del sensor para detectar tiros
    if (_bluetoothViewModel.isConnected) {
      final distanciaActual = _bluetoothViewModel.distancia;
      
      // Si la distancia es menor que el umbral, consideramos que es un tiro
      if (distanciaActual < _distanciaUmbral) {
        // Evitar múltiples detecciones en corto tiempo (debounce)
        if (_lastDistanceTriggerTime == null || 
            DateTime.now().difference(_lastDistanceTriggerTime!).inSeconds > 2) {
          _lastDistanceTriggerTime = DateTime.now();
          
          // Registramos un tiro exitoso
          _handleShotDetected(true, ShotDetectionType.sensor);
        }
      }
    }
  }

  Future<void> initializeCamera() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    
    try {
      // Inicializar el repositorio de sesiones
      await _sessionRepository.init();
      
      // Obtener cámaras disponibles
      cameras = await availableCameras();
      
      if (cameras.isEmpty) {
        errorMessage = "No se encontraron cámaras disponibles";
        isLoading = false;
        notifyListeners();
        return;
      }

      // Inicializar con la cámara trasera por defecto
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Configurar formato de imagen adecuado según la plataforma
      final imageFormatGroup = Platform.isAndroid
          ? ImageFormatGroup.yuv420
          : Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : Platform.isMacOS
                  ? ImageFormatGroup.bgra8888
                  : ImageFormatGroup.unknown;

      cameraController = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: true, // Habilitamos audio para los clips
        imageFormatGroup: imageFormatGroup,
      );

      // Inicializar la cámara
      await cameraController!.initialize();
      isInitialized = true;
      isLoading = false;

      // Comenzar procesamiento de frames
      _startImageStream();
      
      // Iniciar grabación continua en loop si no estamos en macOS
      if (!Platform.isMacOS) {
        await _startContinuousRecording();
      }
      
      notifyListeners();
    } catch (e) {
      errorMessage = "Error al inicializar la cámara: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  void switchCamera() async {
    if (cameras.length < 2 || cameraController == null) return;

    isLoading = true;
    notifyListeners();

    // Detener grabación si está activa
    if (isRecordingVideo) {
      await _stopVideoRecording();
    }

    // Obtener dirección actual
    final currentDirection = cameraController!.description.lensDirection;
    // Cambiar a la dirección opuesta
    final newDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // Encontrar la cámara con la nueva dirección
    final newCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == newDirection,
      orElse: () => cameras.first,
    );

    // Deshacer el controlador actual
    await cameraController!.dispose();

    // Configurar formato de imagen adecuado según la plataforma
    final imageFormatGroup = Platform.isAndroid
        ? ImageFormatGroup.yuv420
        : Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : Platform.isMacOS
                ? ImageFormatGroup.bgra8888
                : ImageFormatGroup.unknown;

    // Crear un nuevo controlador con la nueva cámara
    cameraController = CameraController(
      newCamera,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: imageFormatGroup,
    );

    try {
      await cameraController!.initialize();
      
      // Reiniciar procesamiento de frames
      _startImageStream();
      
      // Reiniciar grabación si no estamos en macOS
      if (!Platform.isMacOS) {
        _startVideoRecording();
      }
      
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = "Error al cambiar la cámara: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  void _startImageStream() {
    if (!isInitialized || cameraController == null) return;
    
    cameraController!.startImageStream((CameraImage image) {
      // Control de velocidad de muestreo a 30 fps
      final now = DateTime.now();
      if (_lastFrameProcessTime != null) {
        final elapsedMs = now.difference(_lastFrameProcessTime!).inMilliseconds;
        final targetIntervalMs = 1000 ~/ _targetFps;
        
        if (elapsedMs < targetIntervalMs) {
          return; // Saltamos este frame para mantener 30 fps
        }
      }
      
      if (!isProcessingFrame && isDetectionEnabled) {
        isProcessingFrame = true;
        _lastFrameProcessTime = now;
        _processImageForBallDetection(image);
      }
    });
  }

  void toggleDetection() {
    isDetectionEnabled = !isDetectionEnabled;
    notifyListeners();
    
    if (isDetectionEnabled) {
      _startImageStream();
    }
  }

  Future<void> _processImageForBallDetection(CameraImage image) async {
    try {
      final processedImage = await compute(_convertCameraImageToImage, image);
      
      final ballDetection = await compute(_detectBasketball, processedImage);
      
      // Apply temporal filtering to reduce false positives
      if (ballDetection != null) {
        // If we have a new detection, check if it's consistent with previous ones
        if (_detectionBuffer.isNotEmpty) {
          final validDetections = _detectionBuffer.toList()
              .where((d) => d != null)
              .toList();
          
          if (validDetections.isNotEmpty) {
            // Check if new detection is close to previous ones
            bool isConsistentWithPrevious = false;
            for (final prevDetection in validDetections) {
              final dx = ballDetection.center.dx - prevDetection!.center.dx;
              final dy = ballDetection.center.dy - prevDetection.center.dy;
              final distance = sqrt(dx * dx + dy * dy);
              
              // If the new detection is close to any previous valid detection
              if (distance < ballDetection.radius * 2) {
                isConsistentWithPrevious = true;
                break;
              }
            }
            
            // Only accept detection if it's consistent with previous ones
            // or if we haven't had any valid detections recently
            if (!isConsistentWithPrevious && validDetections.length >= 3) {
              // Reject this detection as a false positive
              _detectionBuffer.add(null);
              notifyListeners();
              isProcessingFrame = false;
              return;
            }
          }
        }
      } else {
        // If there's no detection, check if we've had consistent detections before
        final validDetections = _detectionBuffer.toList()
            .where((d) => d != null)
            .take(5)
            .toList();
            
        // Keep the last valid detection if we've had consistent detections
        if (validDetections.length >= 3) {
          _detectionBuffer.add(detectedBall);
          notifyListeners();
          isProcessingFrame = false;
          return;
        }
      }
      
      // Add the current detection to the buffer
      _detectionBuffer.add(ballDetection);
      detectedBall = ballDetection;
      
      if (processedImage != null) {
        final pngBytes = img.encodePng(processedImage);
        lastProcessedFrame = Uint8List.fromList(pngBytes);
      }
      
      _detectBasketballMotion();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Image processing error: $e');
    } finally {
      isProcessingFrame = false;
    }
  }

  void _detectBasketballMotion() {
    // Verificar si hay una detección actual
    if (detectedBall == null) {
      if (_wasBasketballInMotion) {
        // Balón desapareció después de movimiento
        _wasBasketballInMotion = false;
        
        // Verificar si hubo detección del sensor durante el ventaneo de tiempo
        final now = DateTime.now();
        final motionDuration = _basketballMotionStartTime != null 
            ? now.difference(_basketballMotionStartTime!).inSeconds 
            : 0;
            
        // Si no hubo detección reciente por sensor y el balón estuvo en movimiento 
        if (motionDuration > 1 && (_lastDistanceTriggerTime == null || 
            now.difference(_lastDistanceTriggerTime!).inSeconds > 3)) {
          // Detectamos un tiro fallido (el balón se movió pero el sensor no detectó)
          _handleShotDetected(false, ShotDetectionType.camera);
        }
        
        _basketballMotionStartTime = null;
      }
      return;
    }
    
    // Detectar si el balón está en movimiento
    if (_detectionBuffer.length > 5) {
      final previousDetections = _detectionBuffer.toList().reversed.take(5).toList();
      
      // Verificar si hay suficientes detecciones previas
      int validDetections = 0;
      double totalMovement = 0;
      
      for (int i = 1; i < previousDetections.length; i++) {
        if (previousDetections[i] != null && previousDetections[i-1] != null) {
          final dx = previousDetections[i]!.center.dx - previousDetections[i-1]!.center.dx;
          final dy = previousDetections[i]!.center.dy - previousDetections[i-1]!.center.dy;
          final movement = dx * dx + dy * dy;
          totalMovement += movement;
          validDetections++;
        }
      }
      
      // Si hay suficiente movimiento, registramos que el balón está en movimiento
      if (validDetections > 0) {
        final avgMovement = totalMovement / validDetections;
        
        if (avgMovement > 100) { // Umbral de movimiento significativo
          if (!_wasBasketballInMotion) {
            _wasBasketballInMotion = true;
            _basketballMotionStartTime = DateTime.now();
          }
        } else {
          if (_wasBasketballInMotion) {
            _wasBasketballInMotion = false;
            _basketballMotionStartTime = null;
          }
        }
      }
    }
  }

  Future<void> _handleShotDetected(bool isSuccessful, ShotDetectionType detectionType) async {
    // Evitar múltiples detecciones en corto tiempo
    final now = DateTime.now();
    if (_lastShotDetectionTime != null && 
        now.difference(_lastShotDetectionTime!).inSeconds < 2) {
      debugPrint('🚫 Detección ignorada - muy reciente (debounce)');
      return;
    }
    
    _lastShotDetectionTime = now;
    _isShotDetected = true;
    
    debugPrint('🏀 TIRO DETECTADO:');
    debugPrint('   ✨ Tipo: ${isSuccessful ? "ACIERTO" : "FALLO"}');
    debugPrint('   🔍 Detección: $detectionType');
    debugPrint('   📦 Segmentos en buffer: ${_videoBuffer.length}');
    
    // Actualizar contadores
    _totalShots++;
    if (isSuccessful) {
      _successfulShots++;
    }
    
    // Guardar el video de los últimos 10 segundos desde el buffer
    final videoFile = await _createClipFromBuffer();
    
    if (videoFile != null) {
      debugPrint('✅ Clip creado correctamente');
      
      // Registrar el clip en la sesión
      final videoPath = videoFile.path;
      final confidence = detectedBall?.confidence ?? 0.0;
      
      // Verificar que el archivo realmente existe antes de registrarlo
      final file = File(videoPath);
      if (await file.exists()) {
        final fileSize = await file.length();
        debugPrint('📁 Archivo verificado: $videoPath (${fileSize} bytes)');
        
        // Registrar el tiro en el modelo de sesión
        await _registerShotInSession(isSuccessful, videoPath, detectionType, confidence);
      } else {
        debugPrint('❌ ERROR: El archivo del clip no existe después de crearlo: $videoPath');
      }
    } else {
      debugPrint('❌ ERROR: No se pudo crear el clip de video');
    }
    
    // Reiniciar las variables de detección
    _isShotDetected = false;
    
    // Notificar cambios en la UI
    notifyListeners();
  }

  Future<void> _registerShotInSession(
    bool isSuccessful, 
    String videoPath, 
    ShotDetectionType detectionType,
    double confidence
  ) async {
    try {
      // Si tenemos un ViewModel de sesión, registrar el tiro
      if (_sessionViewModel != null) {
        await _sessionViewModel!.registerShot(
          isSuccessful: isSuccessful,
          videoPath: videoPath,
          detectionType: detectionType,
          confidenceScore: confidence,
        );
      } else {
        // De lo contrario, solo registrar en el log
        debugPrint('Tiro registrado: $isSuccessful, Video: $videoPath, Tipo: $detectionType');
      }
    } catch (e) {
      debugPrint('Error al registrar tiro en sesión: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (!isInitialized || cameraController == null || isRecordingVideo) return;
    
    try {
      // Obtener un nuevo archivo temporal para la grabación
      final videoPath = await _sessionRepository.getNewVideoFilePath();
      
      // Iniciar grabación
      await cameraController!.startVideoRecording();
      isRecordingVideo = true;
      
      // Guardar la referencia al archivo actual y el tiempo de inicio
      currentRecordingFile = XFile(videoPath);
      _recordingStartTime = DateTime.now();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error al iniciar grabación: $e');
    }
  }

  Future<XFile?> _stopVideoRecording() async {
    if (!isInitialized || cameraController == null || !isRecordingVideo) return null;
    
    try {
      // Detener grabación
      final file = await cameraController!.stopVideoRecording();
      isRecordingVideo = false;
      notifyListeners();
      return file;
    } catch (e) {
      debugPrint('Error al detener grabación: $e');
      return null;
    }
  }

  /// Inicia la grabación continua con buffer circular
  Future<void> _startContinuousRecording() async {
    if (!isInitialized || cameraController == null || _isContinuousRecording) {
      debugPrint('⚠️ No se puede iniciar grabación continua - Inicializado: $isInitialized, Controller: ${cameraController != null}, Ya grabando: $_isContinuousRecording');
      return;
    }
    
    try {
      _isContinuousRecording = true;
      _segmentCounter = 0;
      
      debugPrint('🎬 Iniciando grabación continua...');
      
      // Iniciar el primer segmento
      await _startNewRecordingSegment();
      
      // Configurar timer para crear nuevos segmentos cada 3-4 segundos
      _recordingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (_isContinuousRecording) {
          await _rotateRecordingSegment();
        }
      });
      
      debugPrint('✅ Grabación continua iniciada con buffer circular');
      
    } catch (e) {
      debugPrint('💥 Error al iniciar grabación continua: $e');
      _isContinuousRecording = false;
    }
  }
  
  /// Inicia un nuevo segmento de grabación
  Future<void> _startNewRecordingSegment() async {
    if (!isInitialized || cameraController == null) {
      debugPrint('⚠️ No se puede iniciar nuevo segmento - No inicializado');
      return;
    }
    
    try {
      // Generar path único para este segmento
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = await _sessionRepository.getNewVideoFilePath();
      _currentRecordingPath = _currentRecordingPath!.replaceAll('.mp4', '_segment_${_segmentCounter}_$timestamp.mp4');
      
      debugPrint('🎥 Iniciando segmento #$_segmentCounter: $_currentRecordingPath');
      
      // Iniciar grabación
      await cameraController!.startVideoRecording();
      _currentSegmentStartTime = DateTime.now();
      _segmentCounter++;
      
      debugPrint('✅ Segmento iniciado exitosamente');
      
    } catch (e) {
      debugPrint('💥 Error al iniciar nuevo segmento: $e');
    }
  }
  
  /// Rota al siguiente segmento del buffer circular
  Future<void> _rotateRecordingSegment() async {
    if (!isInitialized || cameraController == null || !_isContinuousRecording) {
      debugPrint('⚠️ No se puede rotar segmento - Estado inválido');
      return;
    }
    
    try {
      debugPrint('🔄 Rotando al siguiente segmento...');
      
      // Detener la grabación actual
      final recordedFile = await cameraController!.stopVideoRecording();
      
      debugPrint('⏹️ Grabación detenida: ${recordedFile.path}');
      
      // Copiar el archivo al path deseado si es necesario
      if (_currentRecordingPath != null && recordedFile.path != _currentRecordingPath) {
        await File(recordedFile.path).copy(_currentRecordingPath!);
        await File(recordedFile.path).delete();
        debugPrint('📁 Archivo movido a: $_currentRecordingPath');
      }
      
      // Agregar al buffer circular (esto automáticamente elimina el más antiguo si está lleno)
      if (_currentRecordingPath != null) {
        // Si el buffer está lleno, eliminar el archivo más antiguo
        if (_videoBuffer.isFilled) {
          final oldestFile = _videoBuffer.first;
          if (oldestFile != null && await File(oldestFile).exists()) {
            await File(oldestFile).delete();
            debugPrint('🗑️ Archivo antiguo eliminado: $oldestFile');
          }
        }
        
        // Verificar el tamaño del archivo antes de agregarlo
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('📦 Agregando al buffer: $_currentRecordingPath (${fileSize} bytes)');
          _videoBuffer.add(_currentRecordingPath!);
        } else {
          debugPrint('❌ ERROR: El segmento no existe: $_currentRecordingPath');
        }
      }
      
      // Iniciar el siguiente segmento
      await _startNewRecordingSegment();
      
    } catch (e) {
      debugPrint('💥 Error al rotar segmento: $e');
      // Intentar reiniciar grabación en caso de error
      try {
        await _startNewRecordingSegment();
      } catch (restartError) {
        debugPrint('💥 Error al reiniciar grabación: $restartError');
      }
    }
  }
  
  /// Detiene la grabación continua
  Future<void> _stopContinuousRecording() async {
    if (!_isContinuousRecording) return;
    
    try {
      _isContinuousRecording = false;
      _recordingTimer?.cancel();
      
      // Detener grabación actual si está activa
      if (cameraController != null) {
        try {
          await cameraController!.stopVideoRecording();
        } catch (e) {
          debugPrint('Error al detener grabación: $e');
        }
      }
      
      // Limpiar archivos del buffer
      for (final filePath in _videoBuffer.toList()) {
        if (filePath != null && await File(filePath).exists()) {
          await File(filePath).delete();
        }
      }
      _videoBuffer.clear();
      
      debugPrint('Grabación continua detenida');
      
    } catch (e) {
      debugPrint('Error al detener grabación continua: $e');
    }
  }

  /// Crea un clip de video combinando los segmentos del buffer para obtener ~10 segundos
  Future<XFile?> _createClipFromBuffer() async {
    if (_videoBuffer.isEmpty) {
      debugPrint('⚠️ Buffer de video vacío, no se puede crear clip');
      return null;
    }
    
    try {
      // Generar path para el clip final
      final clipPath = await _sessionRepository.getNewVideoFilePath();
      debugPrint('📹 Creando clip: $clipPath');
      debugPrint('📦 Segmentos en buffer: ${_videoBuffer.length}');
      
      // Listar todos los segmentos disponibles
      final availableSegments = <String>[];
      for (final segmentPath in _videoBuffer.toList()) {
        if (segmentPath != null && await File(segmentPath).exists()) {
          final fileSize = await File(segmentPath).length();
          debugPrint('✅ Segmento disponible: $segmentPath (${fileSize} bytes)');
          availableSegments.add(segmentPath);
        } else if (segmentPath != null) {
          debugPrint('❌ Segmento faltante: $segmentPath');
        }
      }
      
      if (availableSegments.isEmpty) {
        debugPrint('⚠️ No hay segmentos disponibles para crear clip');
        return null;
      }
      
      // Por ahora, usar el segmento más reciente como clip
      // TODO: Implementar concatenación real de múltiples segmentos con FFmpeg
      final mostRecentSegment = availableSegments.last;
      debugPrint('🎬 Usando segmento más reciente: $mostRecentSegment');
      
      // Copiar el archivo al path del clip
      await File(mostRecentSegment).copy(clipPath);
      
      // Verificar que el clip se creó correctamente
      final clipFile = File(clipPath);
      if (await clipFile.exists()) {
        final clipSize = await clipFile.length();
        debugPrint('✅ Clip creado exitosamente: $clipPath (${clipSize} bytes)');
        return XFile(clipPath);
      } else {
        debugPrint('❌ Error: El clip no se pudo crear en $clipPath');
        return null;
      }
      
    } catch (e) {
      debugPrint('💥 Error al crear clip desde buffer: $e');
      return null;
    }
  }

  static img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      if (Platform.isAndroid) {
        // Android usa YUV
        final width = cameraImage.width;
        final height = cameraImage.height;
        
        final yuvImage = img.Image(width: width, height: height);
        
        // Plano Y
        final yBuffer = cameraImage.planes[0].bytes;
        final yRowStride = cameraImage.planes[0].bytesPerRow;
        final yPixelStride = cameraImage.planes[0].bytesPerPixel ?? 1;
        
        // Planos U y V
        final uBuffer = cameraImage.planes[1].bytes;
        final uRowStride = cameraImage.planes[1].bytesPerRow;
        final uPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;
        final vBuffer = cameraImage.planes[2].bytes;
        final vRowStride = cameraImage.planes[2].bytesPerRow;
        final vPixelStride = cameraImage.planes[2].bytesPerPixel ?? 1;
        
        // Convertir YUV a RGB
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final yIndex = h * yRowStride + w * yPixelStride;
            // Los planos U y V tienen la mitad de la resolución
            final uvh = h ~/ 2;
            final uvw = w ~/ 2;
            final uIndex = uvh * uRowStride + uvw * uPixelStride;
            final vIndex = uvh * vRowStride + uvw * vPixelStride;
            
            if (yIndex < yBuffer.length && 
                uIndex < uBuffer.length && 
                vIndex < vBuffer.length) {
              // YUV a RGB
              final y = yBuffer[yIndex];
              final u = uBuffer[uIndex];
              final v = vBuffer[vIndex];
              
              int r = (y + 1.402 * (v - 128)).round().clamp(0, 255);
              int g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
              int b = (y + 1.772 * (u - 128)).round().clamp(0, 255);
              
              yuvImage.setPixelRgba(w, h, r, g, b, 255);
            }
          }
        }
        
        return yuvImage;
      } else {
        // iOS usa BGRA
        final width = cameraImage.width;
        final height = cameraImage.height;
        final bgra = img.Image(width: width, height: height);
        
        final buffer = cameraImage.planes[0].bytes;
        final rowStride = cameraImage.planes[0].bytesPerRow;
        final pixelStride = cameraImage.planes[0].bytesPerPixel ?? 4;
        
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final index = h * rowStride + w * pixelStride;
            if (index + 3 < buffer.length) {
              // BGRA a RGBA
              final b = buffer[index];
              final g = buffer[index + 1];
              final r = buffer[index + 2];
              final a = buffer[index + 3];
              
              bgra.setPixelRgba(w, h, r, g, b, a);
            }
          }
        }
        
        return bgra;
      }
    } catch (e) {
      debugPrint('Error al convertir imagen: $e');
      return null;
    }
  }

  static BallDetection? _detectBasketball(img.Image? image) {
    if (image == null) return null;
    
    final width = image.width;
    final height = image.height;
    
    // Enhanced thresholds for orange color detection (including darker shades)
    const hueMin = 0.0;      // Include reds
    const hueMax = 0.15;     // Reduce range to avoid yellows
    const satMin = 0.30;     // Increase minimum saturation
    const valMin = 0.20;     // Increase minimum value
    
    // Extended list of basketball-specific colors (RGB)
    final List<List<int>> basketballColors = [
      [0xec, 0x74, 0x35], // ec7435 - typical orange
      [0xf8, 0x83, 0x27], // f88327 - bright orange
      [0xd7, 0x64, 0x33], // d76433 - terracotta orange
      [0xcd, 0x5a, 0x0a], // cd5a0a - dull orange
      [0xd4, 0x68, 0x50], // d46850
      [0xa5, 0x53, 0x3c], // a5533c
      [0x91, 0x41, 0x31], // 914131 - darker orange
    ];
    
    // Tolerance for specific color comparison (reduced)
    const int colorTolerance = 30; // Reduced to avoid false positives
    
    // Create binary mask for orange pixels
    final orangeMask = List.generate(
      height, 
      (_) => List.filled(width, false),
    );
    
    // Create mask for all pixels (for circular detection)
    final allPixelsMask = List.generate(
      height, 
      (_) => List.filled(width, true),
    );
    
    // Count of orange pixels
    int orangePixelCount = 0;
    
    // Detect orange pixels - enhanced version for iOS
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Direct check for basketball-specific colors
        bool isBasketballColor = false;
        for (final color in basketballColors) {
          final rRef = color[0];
          final gRef = color[1];
          final bRef = color[2];
          
          if ((r - rRef).abs() <= colorTolerance && 
              (g - gRef).abs() <= colorTolerance && 
              (b - bRef).abs() <= colorTolerance) {
            isBasketballColor = true;
            break;
          }
        }
        
        // Improved check for basketball orange with more constraints
        final bool isOpaqueOrange = (r > 110 && r < 240) && 
                                   (g > 50 && g < 160) && 
                                   (b < 100) &&
                                   (r > g * 1.3) && // Increased ratio constraint
                                   (g > b * 1.3);   // Increased ratio constraint
        
        // Convert to HSV
        final hsv = _rgbToHsv(r, g, b);
        final h = hsv[0];
        final s = hsv[1];
        final v = hsv[2];
        
        // Combined condition to detect basketball colors with stricter requirements
        if (isBasketballColor || 
            (((h >= hueMin && h <= hueMax) || (h >= 0.95 && h <= 1.0)) && 
            (s > satMin) && (v > valMin) && (r > g) && (g > b)) || 
            isOpaqueOrange) {
          orangeMask[y][x] = true;
          orangePixelCount++;
        }
      }
    }
    
    // Apply morphological operations to both masks
    // For orange mask (color-based detection)
    if (orangePixelCount >= 250) {
      _applyDilation(orangeMask, 5);
      _applyErosion(orangeMask, 4);
    }
    
    // For shape-based detection, use all pixels
    _applyDilation(allPixelsMask, 3);
    _applyErosion(allPixelsMask, 2);
    
    // Find connected components for both masks
    final orangeComponents = orangePixelCount >= 250 ? 
        _findConnectedComponents(orangeMask) : [];
    final allComponents = _findConnectedComponents(allPixelsMask);
    
    // Store best candidates
    BallDetection? bestColorBall;
    BallDetection? bestShapeBall;
    BallDetection? bestCombinedBall;
    
    double bestColorCircularity = 0;
    double bestShapeCircularity = 0;
    double bestCombinedScore = 0;
    
    // Process color-based components (orange objects)
    for (final component in orangeComponents) {
      if (component.pixels.length < 200) continue;
      
      final properties = _calculateRegionProperties(component);
      final circularity = properties['circularity'] ?? 0;
      final radius = properties['radius'] ?? 0;
      final aspectRatio = properties['aspectRatio'] ?? 1.0;
      
      // Relaxed constraints for color-based detection
      if (circularity > 0.65 && 
          radius >= 15 && radius <= 250 &&
          aspectRatio < 1.5 && aspectRatio > 0.65) {
        
        // If also has good circularity, consider it for combined detection
        if (circularity > 0.75) {
          final combinedScore = circularity * 2.0; // Double weight for combined
          
          if (combinedScore > bestCombinedScore) {
            bestCombinedScore = combinedScore;
            bestCombinedBall = BallDetection(
              center: properties['center'] ?? Offset.zero,
              radius: radius,
              confidence: circularity,
            );
          }
        }
        
        // Consider for color-only detection
        if (circularity > bestColorCircularity) {
          bestColorCircularity = circularity;
          bestColorBall = BallDetection(
            center: properties['center'] ?? Offset.zero,
            radius: radius,
            confidence: circularity,
          );
        }
      }
    }
    
    // Process shape-based components (circular objects)
    for (final component in allComponents) {
      if (component.pixels.length < 300 || component.pixels.length > 15000) continue;
      
      final properties = _calculateRegionProperties(component);
      final circularity = properties['circularity'] ?? 0;
      final radius = properties['radius'] ?? 0;
      final aspectRatio = properties['aspectRatio'] ?? 1.0;
      
      // Stricter circularity constraints for shape-based detection
      if (circularity > 0.85 && 
          radius >= 20 && radius <= 200 &&
          aspectRatio < 1.2 && aspectRatio > 0.8) {
        
        // Check if this component overlaps with an orange one
        bool overlapsWithOrange = false;
        final center = properties['center'] as Offset;
        
        for (final orangeComponent in orangeComponents) {
          final orangeProperties = _calculateRegionProperties(orangeComponent);
          final orangeCenter = orangeProperties['center'] as Offset;
          final orangeRadius = orangeProperties['radius'] ?? 0;
          
          final dx = center.dx - orangeCenter.dx;
          final dy = center.dy - orangeCenter.dy;
          final distance = sqrt(dx * dx + dy * dy);
          
          if (distance < (radius + orangeRadius) * 0.7) {
            overlapsWithOrange = true;
            break;
          }
        }
        
        // If overlaps with orange component, prioritize as combined
        if (overlapsWithOrange) {
          final combinedScore = circularity * 1.5; // Higher weight
          
          if (combinedScore > bestCombinedScore) {
            bestCombinedScore = combinedScore;
            bestCombinedBall = BallDetection(
              center: center,
              radius: radius,
              confidence: circularity,
            );
          }
        }
        
        // Consider for shape-only detection
        if (circularity > bestShapeCircularity) {
          bestShapeCircularity = circularity;
          bestShapeBall = BallDetection(
            center: center,
            radius: radius,
            confidence: circularity * 0.9, // Slightly reduced confidence
          );
        }
      }
    }
    
    // Return the best detection based on priority:
    // 1. Combined (color + shape)
    // 2. Color-based
    // 3. Shape-based
    if (bestCombinedBall != null) {
      return bestCombinedBall;
    } else if (bestColorBall != null) {
      return bestColorBall;
    } else {
      return bestShapeBall;
    }
  }
  
  static List<double> _rgbToHsv(int r, int g, int b) {
    // Normalize RGB [0-255] to [0-1]
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    
    final cmax = [rf, gf, bf].reduce(max);
    final cmin = [rf, gf, bf].reduce(min);
    final delta = cmax - cmin;
    
    // Calculate hue
    double h = 0.0;
    if (delta != 0) {
      if (cmax == rf) {
        h = (((gf - bf) / delta) % 6) / 6;
      } else if (cmax == gf) {
        h = (((bf - rf) / delta) + 2) / 6;
      } else {
        h = (((rf - gf) / delta) + 4) / 6;
      }
    }
    
    if (h < 0) h += 1.0;
    
    // Calculate saturation
    final s = cmax == 0 ? 0.0 : delta / cmax;
    
    // Value
    final v = cmax;
    
    return [h, s, v];
  }
  
  static void _applyDilation(List<List<bool>> mask, int size) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(
      height, 
      (y) => List.from(mask[y]),
    );
    
    final radius = size ~/ 2;
    
    for (int y = radius; y < height - radius; y++) {
      for (int x = radius; x < width - radius; x++) {
        if (!mask[y][x]) continue;
        
        // Apply dilation
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              result[y + dy][x + dx] = true;
            }
          }
        }
      }
    }
    
    // Copy result back to the mask
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        mask[y][x] = result[y][x];
      }
    }
  }
  
  static void _applyErosion(List<List<bool>> mask, int size) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(
      height, 
      (y) => List.from(mask[y]),
    );
    
    final radius = size ~/ 2;
    
    for (int y = radius; y < height - radius; y++) {
      for (int x = radius; x < width - radius; x++) {
        // Check if all pixels in the neighborhood are true
        bool allTrue = true;
        
        for (int dy = -radius; dy <= radius && allTrue; dy++) {
          for (int dx = -radius; dx <= radius && allTrue; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              if (!mask[y + dy][x + dx]) {
                allTrue = false;
                break;
              }
            }
          }
        }
        
        result[y][x] = allTrue;
      }
    }
    
    // Copy result back to the mask
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        mask[y][x] = result[y][x];
      }
    }
  }
  
  static List<_ConnectedComponent> _findConnectedComponents(List<List<bool>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final visited = List.generate(
      height, 
      (_) => List.filled(width, false),
    );
    
    final components = <_ConnectedComponent>[];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (mask[y][x] && !visited[y][x]) {
          final component = _ConnectedComponent();
          _floodFill(mask, visited, x, y, component);
          components.add(component);
        }
      }
    }
    
    return components;
  }
  
  static void _floodFill(
    List<List<bool>> mask, 
    List<List<bool>> visited, 
    int x, 
    int y, 
    _ConnectedComponent component
  ) {
    final height = mask.length;
    final width = mask[0].length;
    
    // Stack for DFS (to avoid stack overflow)
    final stack = <Point<int>>[];
    stack.add(Point(x, y));
    
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final px = point.x;
      final py = point.y;
      
      if (px < 0 || py < 0 || px >= width || py >= height) continue;
      if (!mask[py][px] || visited[py][px]) continue;
      
      visited[py][px] = true;
      component.pixels.add(Point(px, py));
      
      // Add neighbors to the stack
      stack.add(Point(px + 1, py));
      stack.add(Point(px - 1, py));
      stack.add(Point(px, py + 1));
      stack.add(Point(px, py - 1));
    }
  }
  
  static Map<String, dynamic> _calculateRegionProperties(_ConnectedComponent component) {
    if (component.pixels.isEmpty) {
      return {'center': Offset.zero, 'radius': 0, 'circularity': 0, 'aspectRatio': 1.0};
    }
    
    // Calculate center
    double sumX = 0;
    double sumY = 0;
    
    // Find limits to calculate aspect ratio
    int minX = component.pixels[0].x;
    int maxX = component.pixels[0].x;
    int minY = component.pixels[0].y;
    int maxY = component.pixels[0].y;
    
    for (final pixel in component.pixels) {
      sumX += pixel.x;
      sumY += pixel.y;
      
      // Update limits
      minX = min(minX, pixel.x);
      maxX = max(maxX, pixel.x);
      minY = min(minY, pixel.y);
      maxY = max(maxY, pixel.y);
    }
    
    final centerX = sumX / component.pixels.length;
    final centerY = sumY / component.pixels.length;
    final center = Offset(centerX, centerY);
    
    // Calculate radius (average distance to center)
    double sumDist = 0;
    double maxDist = 0;
    
    for (final pixel in component.pixels) {
      final dx = pixel.x - centerX;
      final dy = pixel.y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      sumDist += dist;
      maxDist = max(maxDist, dist);
    }
    
    final avgRadius = sumDist / component.pixels.length;
    
    // Calculate circularity using standard deviation of distance to center
    double sumDeviation = 0;
    for (final pixel in component.pixels) {
      final dx = pixel.x - centerX;
      final dy = pixel.y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      sumDeviation += (dist - avgRadius).abs();
    }
    
    final avgDeviation = sumDeviation / component.pixels.length;
    
    // Calculate circularity (1 = perfect circle, less = less circular)
    final circularity = 1 - (avgDeviation / avgRadius);
    
    // Calculate aspect ratio (proportion between width and height of object)
    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    final aspectRatio = width / height;
    
    return {
      'center': center,
      'radius': avgRadius,
      'circularity': circularity,
      'aspectRatio': aspectRatio,
    };
  }

  @override
  void dispose() {
    // Desuscribirse de las actualizaciones del sensor
    _bluetoothViewModel.removeListener(_handleSensorUpdate);
    
    // Detener la grabación continua
    _stopContinuousRecording();
    
    // Liberar recursos de la cámara
    cameraController?.dispose();
    super.dispose();
  }

  /// Método para testing - simula la detección de un tiro
  Future<void> simulateShot(bool isSuccessful) async {
    debugPrint('🧪 SIMULANDO TIRO: ${isSuccessful ? "ACIERTO" : "FALLO"}');
    await _handleShotDetected(isSuccessful, ShotDetectionType.manual);
  }
  
  /// Obtiene información de debug sobre el estado del buffer
  String getBufferDebugInfo() {
    final info = StringBuffer();
    info.writeln('=== BUFFER DEBUG ===');
    info.writeln('Grabación continua activa: $_isContinuousRecording');
    info.writeln('Segmentos en buffer: ${_videoBuffer.length}');
    info.writeln('Contador de segmentos: $_segmentCounter');
    info.writeln('Path actual: $_currentRecordingPath');
    info.writeln('');
    
    for (int i = 0; i < _videoBuffer.length; i++) {
      final segment = _videoBuffer.toList()[i];
      if (segment != null) {
        final exists = File(segment).existsSync();
        final size = exists ? File(segment).lengthSync() : 0;
        info.writeln('Segmento #$i: ${exists ? "✅" : "❌"} ($size bytes)');
        info.writeln('  $segment');
      }
    }
    
    return info.toString();
  }
}

class _ConnectedComponent {
  final List<Point<int>> pixels = [];
}
