import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import '../shared/sessions/view_model/session_view_model.dart';
import '../shared/sessions/data/session_model.dart';

class BallDetection {
  final Offset center;
  final double radius;
  final double confidence;
  final DateTime timestamp;

  BallDetection({
    required this.center,
    required this.radius,
    required this.confidence,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class CameraViewModel extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _errorMessage;
  
  // ML Kit
  ObjectDetector? _objectDetector;
  bool _isProcessingFrame = false;
  DateTime _lastProcessTime = DateTime.now();
  
  // Detección de pelota
  BallDetection? _currentDetection;
  List<BallDetection> _detectionHistory = [];
  
  // Métricas
  int _totalFrames = 0;
  int _detectedFrames = 0;
  
  // Sesión
  SessionViewModel? _sessionViewModel;
  
  // Control de tiros para evitar duplicados
  DateTime? _lastShotTime;
  
  // Getters
  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get errorMessage => _errorMessage;
  BallDetection? get currentDetection => _currentDetection;
  List<BallDetection> get detectionHistory => _detectionHistory;
  int get totalFrames => _totalFrames;
  int get detectedFrames => _detectedFrames;
  double get detectionRate => _totalFrames > 0 ? _detectedFrames / _totalFrames : 0.0;

  CameraViewModel({SessionViewModel? sessionViewModel})
      : _sessionViewModel = sessionViewModel;

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

      // Inicializar ML Kit
      await _initializeMLKit();

      // Comenzar stream de procesamiento
      _startImageStream();

      _isInitialized = true;
      debugPrint('✅ Cámara y ML Kit inicializados correctamente');
      
    } catch (e) {
      _errorMessage = 'Error initializing camera: $e';
      debugPrint('❌ Error: $_errorMessage');
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _initializeMLKit() async {
    try {
      // Configuración optimizada para balones de basketball
      final options = ObjectDetectorOptions(
        mode: DetectionMode.stream, // Modo stream para tiempo real
        classifyObjects: true,
        multipleObjects: true, // Cambiar a true para detectar múltiples objetos
      );
      
      _objectDetector = ObjectDetector(options: options);
      debugPrint('✅ ML Kit ObjectDetector inicializado');
      debugPrint('📊 Configuración: stream mode, clasificación activa, múltiples objetos');
      
    } catch (e) {
      debugPrint('❌ Error inicializando ML Kit: $e');
      throw e;
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((CameraImage cameraImage) {
      _processFrameAsync(cameraImage);
    });
  }

  void _processFrameAsync(CameraImage cameraImage) async {
    // Control de frecuencia de procesamiento (máximo cada 200ms para más detecciones)
    final now = DateTime.now();
    if (now.difference(_lastProcessTime).inMilliseconds < 200) {
      return;
    }

    if (_isProcessingFrame || _objectDetector == null) return;

    _isProcessingFrame = true;
    _lastProcessTime = now;
    _totalFrames++;

    try {
      // Convertir CameraImage a InputImage para ML Kit
      final inputImage = _convertToInputImage(cameraImage);
      if (inputImage == null) {
        _isProcessingFrame = false;
        return;
      }

      // Solo log cada 20 frames para reducir spam
      final shouldLog = _totalFrames % 20 == 0;
      if (shouldLog) {
        debugPrint('🔄 Procesando frame ${cameraImage.width}x${cameraImage.height} (Frame #$_totalFrames)');
      }

      // Procesar con ML Kit de forma asíncrona
      final objects = await _objectDetector!.processImage(inputImage);
      
      // Buscar pelota de basketball en las detecciones
      BallDetection? detection = _findBasketballInObjects(objects, cameraImage, shouldLog);
      
      if (detection != null) {
        _detectedFrames++;
        debugPrint('🏀 ¡Pelota detectada! Confianza: ${detection.confidence.toStringAsFixed(2)} (${_detectedFrames}/${_totalFrames})');
        _updateDetection(detection);
        _checkForShotDetection();
      } else {
        // Limpiar detección antigua si no se detecta nada por más de 1 segundo
        if (_currentDetection != null && 
            now.difference(_currentDetection!.timestamp).inSeconds > 1) {
          _currentDetection = null;
          debugPrint('🧹 Limpiando detección antigua');
          notifyListeners();
        }
      }

    } catch (e) {
      debugPrint('❌ Error procesando frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage? _convertToInputImage(CameraImage cameraImage) {
    try {
      final camera = _cameraController!.description;
      
      // Obtener metadatos de rotación e imagen
      final sensorOrientation = camera.sensorOrientation;
      InputImageRotation? rotation;
      
      if (Platform.isIOS) {
        rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
      } else if (Platform.isAndroid) {
        var rotationCompensation = _orientations[_cameraController!.value.deviceOrientation];
        if (rotationCompensation == null) return null;
        
        if (camera.lensDirection == CameraLensDirection.front) {
          rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
        } else {
          rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
        }
        rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
      }

      if (rotation == null) return null;

      // Crear metadatos
      final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
      if (format == null || (Platform.isAndroid && format != InputImageFormat.nv21) ||
          (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

      // Concatenar planos de imagen
      final bytes = _concatenatePlanes(cameraImage.planes);
      
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: cameraImage.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('❌ Error convirtiendo imagen: $e');
      return null;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  BallDetection? _findBasketballInObjects(List<DetectedObject> objects, CameraImage cameraImage, bool shouldLog) {
    if (shouldLog) {
      debugPrint('🔍 Objetos detectados: ${objects.length}');
    }
    
    for (int i = 0; i < objects.length; i++) {
      final DetectedObject object = objects[i];
      final boundingBox = object.boundingBox;
      
      // Primero intentar detección por clasificación
      for (final Label label in object.labels) {
        if (shouldLog) {
          debugPrint('🏷️ Etiqueta: "${label.text}" (confianza: ${label.confidence.toStringAsFixed(2)})');
        }
        
        if (_isBasketballLabel(label.text) && label.confidence > 0.3) {
          debugPrint('✅ ¡Pelota detectada por clasificación: "${label.text}"!');
          return _createBallDetection(boundingBox, label.confidence);
        }
      }
      
      // Si no hay clasificación específica, intentar detección por forma
      if (_isCircularObject(boundingBox) && _isSuitableSize(boundingBox, cameraImage)) {
        if (shouldLog) {
          debugPrint('✅ ¡Objeto circular detectado por forma! Tamaño: ${boundingBox.width.toInt()}x${boundingBox.height.toInt()}');
        }
        return _createBallDetection(boundingBox, 0.6);
      }
    }
    
    return null;
  }

  bool _isBasketballLabel(String label) {
    final basketballTerms = [
      'ball', 'basketball', 'sports ball', 'sport ball',
      'sphere', 'orange ball', 'round object', 'circle',
      'wilson', 'spalding', 'nike' // Marcas específicas de pelotas
    ];
    
    // Etiquetas a excluir específicamente
    final excludedTerms = [
      'food', 'fruit', 'orange', 'apple', 'fashion', 'home good', 'toy'
    ];
    
    final lowerLabel = label.toLowerCase();
    
    // Si contiene términos excluidos, no es una pelota
    if (excludedTerms.any((term) => lowerLabel.contains(term))) {
      return false;
    }
    
    return basketballTerms.any((term) => lowerLabel.contains(term));
  }

  bool _isCircularObject(Rect boundingBox) {
    // Verificar si el objeto es aproximadamente circular (más estricto)
    final aspectRatio = boundingBox.width / boundingBox.height;
    final minSize = 80.0; // Aumentar tamaño mínimo
    final maxSize = 300.0; // Agregar tamaño máximo
    
    return aspectRatio >= 0.85 && aspectRatio <= 1.15 && // Más estricto para círculos perfectos
           boundingBox.width >= minSize && boundingBox.height >= minSize &&
           boundingBox.width <= maxSize && boundingBox.height <= maxSize;
  }

  bool _isSuitableSize(Rect boundingBox, CameraImage cameraImage) {
    // Verificar si el tamaño es apropiado para una pelota (más restrictivo)
    final imageArea = cameraImage.width * cameraImage.height;
    final objectArea = boundingBox.width * boundingBox.height;
    final areaRatio = objectArea / imageArea;
    
    // La pelota debería ocupar entre 1% y 12% de la imagen
    return areaRatio >= 0.01 && areaRatio <= 0.12;
  }

  BallDetection _createBallDetection(Rect boundingBox, double confidence) {
    final center = Offset(
      boundingBox.left + boundingBox.width / 2,
      boundingBox.top + boundingBox.height / 2,
    );
    final radius = (boundingBox.width + boundingBox.height) / 4;

    return BallDetection(
      center: center,
      radius: radius,
      confidence: confidence,
    );
  }

  void _updateDetection(BallDetection detection) {
    debugPrint('🔔 _updateDetection: center=${detection.center}, radius=${detection.radius}');
    _currentDetection = detection;
    
    // Mantener historial de detecciones (últimas 10)
    _detectionHistory.add(detection);
    if (_detectionHistory.length > 10) {
      _detectionHistory.removeAt(0);
    }
    
    notifyListeners(); // Notificar a los listeners para repaint del overlay
  }

  void _checkForShotDetection() {
    if (_detectionHistory.length < 8) return; // Necesitamos más puntos para ser más precisos

    // Análisis más estricto de trayectoria para detectar tiros
    final recentPoints = _detectionHistory.length >= 8 
        ? _detectionHistory.sublist(_detectionHistory.length - 8)
        : _detectionHistory;
    
    // Verificar si hay un movimiento claro y consistente
    bool hasSignificantUpwardMotion = false;
    bool hasSignificantDownwardMotion = false;
    double totalUpwardMovement = 0;
    double totalDownwardMovement = 0;
    
    for (int i = 1; i < recentPoints.length; i++) {
      final prevY = recentPoints[i - 1].center.dy;
      final currentY = recentPoints[i].center.dy;
      final movement = prevY - currentY; // Positivo = hacia arriba
      
      if (movement > 15) { // Movimiento significativo hacia arriba
        totalUpwardMovement += movement;
        hasSignificantUpwardMotion = true;
      } else if (movement < -15) { // Movimiento significativo hacia abajo
        totalDownwardMovement += movement.abs();
        if (hasSignificantUpwardMotion) {
          hasSignificantDownwardMotion = true;
        }
      }
    }

    // Solo registrar tiro si hay movimiento significativo en ambas direcciones
    final minimumMovement = 50.0; // Píxeles mínimos de movimiento
    if (hasSignificantUpwardMotion && hasSignificantDownwardMotion &&
        totalUpwardMovement > minimumMovement && totalDownwardMovement > minimumMovement) {
      
      // Verificar que no hemos registrado un tiro muy recientemente
      final now = DateTime.now();
      if (_lastShotTime == null || now.difference(_lastShotTime!).inSeconds > 3) {
        _lastShotTime = now;
        _registerShotDetection();
      }
    }
  }

  void _registerShotDetection() {
    if (_sessionViewModel == null) return;
    
    // Por ahora registrar como tiro exitoso (se puede mejorar con análisis de canasta)
    _sessionViewModel!.registerShot(
      isSuccessful: true, // Análisis básico
      videoPath: '', // Implementar grabación después
      detectionType: ShotDetectionType.sensor, // Cambiar a sensor por ahora
      confidenceScore: _currentDetection?.confidence ?? 0.8,
    );
    
    debugPrint('🏀 Tiro detectado y registrado!');
  }

  void dispose() {
    _objectDetector?.close();
    _cameraController?.dispose();
    super.dispose();
  }
} 