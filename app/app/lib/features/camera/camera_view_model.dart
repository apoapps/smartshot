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
  
  // Variables para la grabación de video
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
      
      // Iniciar grabación en loop si no estamos en macOS
      // En macOS, la grabación de video puede no estar completamente soportada
      if (!Platform.isMacOS) {
        _startVideoRecording();
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
      // Convertir imagen de cámara a formato adecuado
      final processedImage = await compute(_convertCameraImageToImage, image);
      
      // Detectar balón usando procesamiento de color
      final ballDetection = await compute(_detectBasketball, processedImage);
      
      // Guardar en el buffer y en la variable actual
      _detectionBuffer.add(ballDetection);
      detectedBall = ballDetection;
      
      // Guarda el último frame procesado
      if (processedImage != null) {
        final pngBytes = img.encodePng(processedImage);
        lastProcessedFrame = Uint8List.fromList(pngBytes);
      }
      
      // Detectar movimiento del balón
      _detectBasketballMotion();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error en procesamiento de imagen: $e');
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
      return;
    }
    
    _lastShotDetectionTime = now;
    _isShotDetected = true;
    
    // Actualizar contadores
    _totalShots++;
    if (isSuccessful) {
      _successfulShots++;
    }
    
    // Guardar el video actual con recorte
    final videoFile = await _saveCurrentRecording();
    
    if (videoFile != null) {
      // Registrar el clip en la sesión
      final videoPath = videoFile.path;
      final confidence = detectedBall?.confidence ?? 0.0;
      
      // Registrar el tiro en el modelo de sesión
      await _registerShotInSession(isSuccessful, videoPath, detectionType, confidence);
    }
    
    // Reiniciar la grabación
    await _startVideoRecording();
    
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

  Future<XFile?> _saveCurrentRecording() async {
    if (!isInitialized || cameraController == null || !isRecordingVideo) return null;
    
    try {
      // Detener la grabación actual
      final videoFile = await _stopVideoRecording();
      
      if (videoFile != null && currentRecordingFile != null) {
        // Calcular duración del video para recortar
        final videoDuration = _recordingStartTime != null 
            ? DateTime.now().difference(_recordingStartTime!) : const Duration(seconds: 0);
        
        // Para videos largos (>10s), realizar recorte
        if (videoDuration.inSeconds > 10) {
          try {
            // Guardar el video recortado (solo los últimos 5-10 segundos)
            return await _trimVideo(videoFile, currentRecordingFile!.path, videoDuration);
          } catch (e) {
            debugPrint('Error al recortar video: $e');
            // Si falla el recorte, usamos el video completo
          }
        }
            
        try {
          // Si el video es corto o falló el recorte, copia el archivo completo
          final destFile = File(currentRecordingFile!.path);
          await File(videoFile.path).copy(destFile.path);
          return currentRecordingFile;
        } catch (e) {
          debugPrint('Error al copiar archivo: $e');
          // Intentar mover el archivo en lugar de copiarlo
          final destFile = File(currentRecordingFile!.path);
          await File(videoFile.path).rename(destFile.path);
          return currentRecordingFile;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('Error al guardar grabación: $e');
      return null;
    }
  }
  
  Future<XFile> _trimVideo(XFile originalVideo, String outputPath, Duration videoDuration) async {
    // TODO: Implementar recorte de video con FFmpeg o similar
    // Por ahora, simplemente copiamos el archivo original
    
    // Simulamos el recorte
    debugPrint('Recortando video de $videoDuration segundos a 10 segundos...');
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Copiar el archivo original como solución provisional
    await File(originalVideo.path).copy(outputPath);
    return XFile(outputPath);
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
    
    // Implementación similar al algoritmo de MATLAB proporcionado
    final width = image.width;
    final height = image.height;
    
    // Umbrales mejorados para detección de color naranja (incluyendo tonos más opacos)
    const hueMin = 0.0;      // Incluye rojos
    const hueMax = 0.2;      // Ampliar hacia amarillo-naranja
    const satMin = 0.2;      // Menor saturación para colores más opacos
    const valMin = 0.15;     // Detectar colores más oscuros
    
    // Lista ampliada de colores específicos de balones de baloncesto (en RGB)
    final List<List<int>> basketballColors = [
      [0xd4, 0x68, 0x50], // d46850
      [0xa5, 0x53, 0x3c], // a5533c
      [0x91, 0x41, 0x31], // 914131
      [0xe7, 0x84, 0x6f], // e7846f
      [0x7f, 0x3a, 0x2d], // 7f3a2d
      [0x6b, 0x4c, 0x51], // 6b4c51
      [0xff, 0xbe, 0xa7], // ffbea7
      [0xec, 0x74, 0x35], // ec7435 - naranja típico
      [0xf8, 0x83, 0x27], // f88327 - naranja brillante
      [0xf9, 0x98, 0x46], // f99846 - naranja más claro
      [0xbc, 0x53, 0x24], // bc5324 - marrón-naranja oscuro
      [0xd7, 0x64, 0x33], // d76433 - naranja terracota
      [0xcd, 0x5a, 0x0a], // cd5a0a - naranja apagado
    ];
    
    // Tolerancia para la comparación de colores específicos
    const int colorTolerance = 35; // Aumentada para mayor flexibilidad
    
    // Crear una máscara binaria para los píxeles de color naranja
    final orangeMask = List.generate(
      height, 
      (_) => List.filled(width, false),
    );
    
    // Número de píxeles naranjas
    int orangePixelCount = 0;
    
    // Detectar píxeles naranjas
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Extraer los componentes RGB usando el método adecuado
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Verificación directa para los colores específicos de baloncesto
        bool isBasketballColor = false;
        for (final color in basketballColors) {
          final rRef = color[0];
          final gRef = color[1];
          final bRef = color[2];
          
          // Verificar si el color está dentro de la tolerancia
          if ((r - rRef).abs() <= colorTolerance && 
              (g - gRef).abs() <= colorTolerance && 
              (b - bRef).abs() <= colorTolerance) {
            isBasketballColor = true;
            break;
          }
        }
        
        // Verificación adicional para detectar naranjas opacos de forma directa
        // Esta condición detecta específicamente los tonos más apagados de naranja/marrón
        final bool isOpaqueOrange = (r > 90 && r < 240) && 
                                   (g > 40 && g < 170) && 
                                   (b < 120) &&
                                   (r > g * 1.2) && (g > b * 1.1);
        
        // Convertir a HSV
        final hsv = _rgbToHsv(r, g, b);
        final h = hsv[0];
        final s = hsv[1];
        final v = hsv[2];
        
        // Condición combinada para detectar colores de balón de baloncesto
        if (isBasketballColor || 
            (((h >= hueMin && h <= hueMax) || (h >= 0.94 && h <= 1.0)) && 
            (s > satMin) && (v > valMin)) || 
            isOpaqueOrange) {
          orangeMask[y][x] = true;
          orangePixelCount++;
        }
      }
    }
    
    // Si no hay suficientes píxeles naranjas, no se detecta un balón
    if (orangePixelCount < 200) return null;
    
    // Aplicar operaciones morfológicas (cierre morfológico)
    _applyDilation(orangeMask, 8);
    _applyErosion(orangeMask, 5);
    
    // Encontrar componentes conectados y seleccionar el más circular
    final components = _findConnectedComponents(orangeMask);
    
    BallDetection? bestBall;
    double bestCircularity = 0;
    
    for (final component in components) {
      if (component.pixels.length < 150) continue;  // Filtrar objetos pequeños
      
      // Calcular propiedades
      final properties = _calculateRegionProperties(component);
      final circularity = properties['circularity'] ?? 0;
      final radius = properties['radius'] ?? 0;
      final aspectRatio = properties['aspectRatio'] ?? 1.0;
      
      // Filtrar por forma y tamaño con umbrales ajustados para mayor precisión
      // Verificar circularidad, tamaño y proporción de aspecto (para evitar óvalos)
      if (circularity > 0.7 && radius >= 12 && radius <= 300 &&
          aspectRatio < 1.5 && aspectRatio > 0.67 &&
          circularity > bestCircularity) {
        bestCircularity = circularity;
        bestBall = BallDetection(
          center: properties['center'] ?? Offset.zero,
          radius: radius,
          confidence: circularity,
        );
      }
    }
    
    return bestBall;
  }
  
  static List<double> _rgbToHsv(int r, int g, int b) {
    // Normalizar RGB [0-255] a [0-1]
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    
    final cmax = [rf, gf, bf].reduce(max);
    final cmin = [rf, gf, bf].reduce(min);
    final delta = cmax - cmin;
    
    // Calcular matiz
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
    
    // Calcular saturación
    final s = cmax == 0 ? 0.0 : delta / cmax;
    
    // Valor
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
        
        // Aplicar dilatación
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              result[y + dy][x + dx] = true;
            }
          }
        }
      }
    }
    
    // Copiar resultado de vuelta a la máscara original
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
        // Verificar si todos los píxeles en el vecindario son true
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
    
    // Copiar resultado de vuelta a la máscara original
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
    
    // Pila para DFS (evitar desbordamiento de pila)
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
      
      // Añadir vecinos a la pila
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
    
    // Calcular centro
    double sumX = 0;
    double sumY = 0;
    
    // Encontrar límites para calcular aspect ratio
    int minX = component.pixels[0].x;
    int maxX = component.pixels[0].x;
    int minY = component.pixels[0].y;
    int maxY = component.pixels[0].y;
    
    for (final pixel in component.pixels) {
      sumX += pixel.x;
      sumY += pixel.y;
      
      // Actualizar límites
      minX = min(minX, pixel.x);
      maxX = max(maxX, pixel.x);
      minY = min(minY, pixel.y);
      maxY = max(maxY, pixel.y);
    }
    
    final centerX = sumX / component.pixels.length;
    final centerY = sumY / component.pixels.length;
    final center = Offset(centerX, centerY);
    
    // Calcular radio (distancia media al centro)
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
    
    // Calcular circularidad usando desviación estándar de la distancia al centro
    double sumDeviation = 0;
    for (final pixel in component.pixels) {
      final dx = pixel.x - centerX;
      final dy = pixel.y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      sumDeviation += (dist - avgRadius).abs();
    }
    
    final avgDeviation = sumDeviation / component.pixels.length;
    
    // Calcular circularidad (1 = círculo perfecto, menor = menos circular)
    final circularity = 1 - (avgDeviation / avgRadius);
    
    // Calcular aspect ratio (proporción entre ancho y alto del objeto)
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
    
    // Detener la grabación si está activa
    if (isRecordingVideo) {
      _stopVideoRecording();
    }
    
    // Liberar recursos de la cámara
    cameraController?.dispose();
    super.dispose();
  }
}

class _ConnectedComponent {
  final List<Point<int>> pixels = [];
}
