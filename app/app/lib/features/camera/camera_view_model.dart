import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data'; // Para Uint8List
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:circular_buffer/circular_buffer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // Para DeviceOrientation
import 'package:flutter/scheduler.dart'; // Para WidgetsBinding
import 'package:image/image.dart' as img;
import 'package:app/features/shared/sessions/data/session_model.dart';
import 'package:app/features/shared/sessions/data/session_repository.dart';
import 'package:app/features/shared/bluetooth/bluetooth_view_model.dart';
import 'package:app/features/shared/sessions/view_model/session_view_model.dart';
import 'package:app/features/shared/analysis/analysis_service.dart';
import 'package:flutter/material.dart';
import '../shared/analysis/pose_detection_service.dart'; // Servicio nativo de poses ML Kit

// *** CLASES PARA ANÁLISIS DE TRAYECTORIA ***
class TrajectoryPoint {
  final Offset position;
  final DateTime timestamp;
  final double velocity;
  final Offset velocityVector;

  TrajectoryPoint({
    required this.position,
    required this.timestamp,
    this.velocity = 0.0,
    this.velocityVector = Offset.zero,
  });
}

enum ShotPhase {
  noShot,
  preparation,
  release,
  flight,
  landing,
}

// *** CLASE PARA DETECTAR ZONA DE CANASTA ***
class BasketZone {
  final Offset center;
  final double radius;
  final double rimHeight; // En píxeles de la imagen

  BasketZone({
    required this.center,
    required this.radius,
    required this.rimHeight,
  });

  bool isNearBasket(Offset point, {double tolerance = 1.5}) {
    final distance = (point - center).distance;
    return distance <= radius * tolerance;
  }
}

// *** CLASE PARA ANÁLISIS DE TIRO ***
class ShotAnalysis {
  final List<TrajectoryPoint> trajectory;
  final bool isShotAttempt;
  final bool isMake;
  final double shotQuality;
  final double confidence;
  final double releaseAngle;
  final double releaseVelocity;
  final Offset releasePoint;
  final Offset? predictedLandingPoint;
  final ShotPhase phase;
  final bool isPredictedMake;

  ShotAnalysis({
    required this.trajectory,
    required this.isShotAttempt,
    required this.isMake,
    required this.shotQuality,
    required this.confidence,
    this.releaseAngle = 0.0,
    this.releaseVelocity = 0.0,
    this.releasePoint = Offset.zero,
    this.predictedLandingPoint,
    this.phase = ShotPhase.noShot,
    this.isPredictedMake = false,
  });
}

// *** POINT CLASS HELPER ***
class PixelPoint {
  final int x;
  final int y;
  
  PixelPoint(this.x, this.y);
}

class BallDetection {
  final Offset center;
  final double radius;
  final double confidence;
  final DateTime timestamp;
  final String source; // "ml_kit", "color"

  BallDetection({
    required this.center,
    required this.radius,
    required this.confidence,
    DateTime? timestamp,
    this.source = "unknown",
  }) : timestamp = timestamp ?? DateTime.now();
}

class DetectionMetrics {
  int totalFrames = 0;
  int mlKitDetections = 0;
  int colorDetections = 0;
  int failedDetections = 0;
  DateTime lastReset = DateTime.now();

  void reset() {
    totalFrames = 0;
    mlKitDetections = 0;
    colorDetections = 0;
    failedDetections = 0;
    lastReset = DateTime.now();
  }

  double get mlKitSuccessRate => 
      totalFrames > 0 ? mlKitDetections / totalFrames : 0.0;
  double get colorSuccessRate => 
      totalFrames > 0 ? colorDetections / totalFrames : 0.0;
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
  bool _isInitializing = false; // Prevenir múltiples inicializaciones
  String? errorMessage;
  
  // Detección de baloncesto
  final CircularBuffer<BallDetection> _recentDetections = CircularBuffer(50);
  BallDetection? _lastDetection;
  bool _useMLKitAnalysis = true;  // Usar ML Kit como método principal
  bool _backendHealthy = false;
  
  // Métricas y análisis
  final DetectionMetrics _metrics = DetectionMetrics();
  
  // Análisis de tiro
  final List<BallDetection> _currentShotTrajectory = [];
  
  // Sistemas de fallback
  String _currentDetectionMethod = "Inicializando...";
  
  // Servicios
  final AnalysisService _analysisService = AnalysisService();
  final PoseDetectionService _poseDetectionService = PoseDetectionService(); // Servicio nativo ML Kit
  
  // Variables para la detección del balón
  bool isProcessingFrame = false;
  BallDetection? detectedBall;
  bool isDetectionEnabled = true;
  
  // Variables para fallback
  bool _useColorDetectionFallback = true;
  
  // Variables para la grabación continua con buffer
  bool _isContinuousRecording = false;
  Timer? _recordingTimer;
  final CircularBuffer<String> _videoBuffer = CircularBuffer(3); // Buffer para 3 segmentos de ~3-4 segundos cada uno
  String? _currentRecordingPath;
  int _segmentCounter = 0;
  
  // Variables para detección de tiros
  bool isRecordingVideo = false;
  XFile? currentRecordingFile;
  
  // *** NUEVAS VARIABLES PARA ANÁLISIS DE TRAYECTORIA ***
  final List<TrajectoryPoint> _trajectoryBuffer = [];
  ShotAnalysis? _currentShotAnalysis;
  BasketZone? _basketZone;
  bool _isTrajectoryTracking = false;
  ShotPhase _currentShotPhase = ShotPhase.noShot;
  
  // Buffer para análisis de trayectoria (últimos 3 segundos)
  final int _maxTrajectoryPoints = 180; // 3 segundos a 60 FPS
  
  // Configuración de la zona de canasta (se puede ajustar manualmente)
  bool _isCalibrating = false;
  Offset? _basketCenter;
  double _basketRadius = 50.0;
  final double _basketRimHeight = 100.0; // Altura estimada del aro en píxeles
  
  // Buffer circular para almacenar detecciones recientes
  bool _isShotDetected = false;
  DateTime? _lastDistanceTriggerTime;
  DateTime? _lastShotDetectionTime;
  final CircularBuffer<BallDetection?> _detectionBuffer = CircularBuffer(60); // Detección cada 0.5 segundos
  
  // Contador local de aciertos
  int _successfulShots = 0;
  int _totalShots = 0;

  // Umbral de distancia para considerar un tiro
  final double _distanciaUmbral = 50.0;
  
  // Almacenar el último frame procesado
  Uint8List? lastProcessedFrame;

  // Control de velocidad de muestreo
  final int _targetFps = 30; // FPS objetivo para detección
  DateTime? _lastFrameProcessTime;

  // *** NUEVAS VARIABLES PARA MONITOREO DE RENDIMIENTO ***
  int _processedFramesCount = 0;
  DateTime? _fpsCounterStartTime;
  double _currentDetectionFps = 0.0;
  int _totalDetectionsCount = 0;
  DateTime? _lastDetectionTime;

  // *** VARIABLES PARA DETECCIÓN DE TIROS FALLIDOS ***
  List<BallDetection> _ballTrajectory = [];
  DateTime? _lastBallDetectionTime;
  bool _isPotentialShot = false;
  double _lastBallHeight = 0.0;
  int _consecutiveAscendingFrames = 0;
  int _consecutiveDescendingFrames = 0;
  static const int SHOT_DETECTION_THRESHOLD = 5; // Frames necesarios para detectar tiro
  static const int MISS_DETECTION_THRESHOLD = 8; // Frames descendiendo para confirmar fallo
  static const double HEIGHT_THRESHOLD = 50.0; // Píxeles de cambio mínimo para considerar movimiento

  // *** VARIABLES PARA DEBUG ***
  bool _debugMode = true; // Activar debug por defecto
  int _debugFrameCount = 0;
  DateTime? _lastDebugReport;

  CameraViewModel(this._sessionRepository, this._bluetoothViewModel, [this._sessionViewModel]) {
    // Posponer la inicialización hasta después del primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCamera();
      // Inicializar pose detection de forma asíncrona para no bloquear
      Future.microtask(() async {
        await _initializePoseDetection();
      });
      _checkBackendHealth();
    });
  }

  // *** MÉTODOS FALTANTES AGREGADOS ***
  
  /// Inicializar cámara (método corregido)
  Future<void> _initializeCamera() async {
    if (_isInitializing || isInitialized) {
      debugPrint('⚠️ Inicialización ya en progreso o completada');
      return;
    }
    
    _isInitializing = true;
    isLoading = true;
    errorMessage = null;
    
    try {
      // Inicializar el repositorio de sesiones
      await _sessionRepository.init();
      
      debugPrint('📷 Inicializando detector ML Kit...');
      
      // SISTEMA HÍBRIDO: Color ultra-rápido + ML Kit en hilo separado
      debugPrint('🔄 Inicializando sistema híbrido de detección...');
      
      // Usar detección por color como principal (ultra-rápida)
      _useColorDetectionFallback = true;
      _currentDetectionMethod = "Sistema híbrido: Color + ML Kit + Detección de fallos";
      
      // Inicializar ML Kit de forma asíncrona en hilo separado
      Future.microtask(() async {
        try {
          final mlKitInitialized = await _poseDetectionService.initialize();
          if (mlKitInitialized) {
            _useMLKitAnalysis = true; // Activar ML Kit como complemento
            debugPrint('✅ ML Kit activado en hilo separado para detección de poses');
            WidgetsBinding.instance.addPostFrameCallback((_) {
              notifyListeners();
            });
          } else {
            debugPrint('⚠️ ML Kit no disponible - usando solo detección visual');
          }
        } catch (e) {
          debugPrint('❌ Error inicializando ML Kit: $e');
        }
      });
      
      // Obtener cámaras disponibles
      cameras = await availableCameras();
      
      if (cameras.isEmpty) {
        errorMessage = "No se encontraron cámaras disponibles";
        isLoading = false;
        _isInitializing = false;
        // Posponer notifyListeners para evitar setState durante build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
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
        ResolutionPreset.high, // Usar resolución alta para mejor detección
        enableAudio: true, // Habilitamos audio para los clips
        imageFormatGroup: imageFormatGroup,
      );

      // Inicializar la cámara
      await cameraController!.initialize();
      
      // Esperar a que esté completamente lista
      await Future.delayed(Duration(milliseconds: 200));
      
      // Verificar que la cámara esté realmente inicializada
      if (!cameraController!.value.isInitialized) {
        throw Exception('Camera controller failed to initialize');
      }
      
      // *** CONFIGURAR ZOOM MÁS AMPLIO DISPONIBLE ***
      try {
        // Intentar configurar el zoom más amplio (0.5x si está disponible)
        final minZoom = await cameraController!.getMinZoomLevel();
        final maxZoom = await cameraController!.getMaxZoomLevel();
        debugPrint('📷 Zoom disponible: ${minZoom}x - ${maxZoom}x');
        
        // Usar el zoom mínimo para el campo de visión más amplio
        await cameraController!.setZoomLevel(minZoom);
        debugPrint('📷 Zoom configurado a: ${minZoom}x (más amplio)');
      } catch (e) {
        debugPrint('⚠️ No se pudo configurar zoom: $e');
      }
      
      // *** NO FORZAR ORIENTACIÓN - RESPETAR LA NATURAL ***
      // Remover el forzado de orientación landscape
      debugPrint('📱 Usando orientación natural de la cámara');
      
      isInitialized = true;
      isLoading = false;
      _isInitializing = false;

      // Posponer notifyListeners para evitar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      // Comenzar procesamiento de frames DESPUÉS de que todo esté listo
      await Future.delayed(Duration(milliseconds: 100));
      await _startImageStream();
      
      // Iniciar grabación continua en loop si no estamos en macOS
      if (!Platform.isMacOS) {
        await Future.delayed(Duration(milliseconds: 200));
        await _startContinuousRecording();
      }
      
    } catch (e) {
      errorMessage = "Error al inicializar la cámara: $e";
      isLoading = false;
      _isInitializing = false;
      // Posponer notifyListeners para evitar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }

  /// Inicializar detección de poses nativa con ML Kit
  Future<void> _initializePoseDetection() async {
    try {
      final success = await _poseDetectionService.initialize();
      if (success) {
        debugPrint('✅ ML Kit Pose Detection inicializado correctamente');
        _currentDetectionMethod = "ML Kit Pose Detection";
      } else {
        debugPrint('❌ Falló la inicialización de ML Kit Pose Detection');
        _currentDetectionMethod = "Solo detección por color";
      }
    } catch (e) {
      debugPrint('❌ Error inicializando Pose Detection: $e');
      _currentDetectionMethod = "Solo detección por color";
    }
    // Posponer notifyListeners para evitar setState durante build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  /// Verificar estado del backend OpenPose
  Future<void> _checkBackendHealth() async {
    try {
      final isHealthy = await _analysisService.isHealthy();
      _backendHealthy = isHealthy;
      
      if (isHealthy) {
        debugPrint('✅ Backend OpenPose disponible');
      } else {
        debugPrint('❌ Backend OpenPose no disponible, usando ML Kit');
      }
    } catch (e) {
      debugPrint('❌ Error verificando backend: $e');
      _backendHealthy = false;
    }
    // Posponer notifyListeners para evitar setState durante build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  int get successfulShots => _successfulShots;
  int get totalShots => _totalShots;
  
  // *** NUEVOS GETTERS PARA ESTADÍSTICAS ***
  double get currentDetectionFps => _currentDetectionFps;
  int get totalDetectionsCount => _totalDetectionsCount;
  
  // *** GETTERS PARA ANÁLISIS DE TRAYECTORIA ***
  List<TrajectoryPoint> get trajectoryBuffer => List.unmodifiable(_trajectoryBuffer);
  ShotAnalysis? get currentShotAnalysis => _currentShotAnalysis;
  BasketZone? get basketZone => _basketZone;
  bool get isTrajectoryTracking => _isTrajectoryTracking;
  ShotPhase get currentShotPhase => _currentShotPhase;
  bool get isCalibrating => _isCalibrating;
  Offset? get basketCenter => _basketCenter;
  BallDetection? get lastDetection => _lastDetection;
  List<BallDetection> get recentDetections => _recentDetections.toList();
  bool get useMLKitAnalysis => _useMLKitAnalysis;
  bool get backendHealthy => _backendHealthy;
  DetectionMetrics get metrics => _metrics;
  String get currentDetectionMethod => _currentDetectionMethod;
  bool get shotInProgress => _currentShotAnalysis != null;
  List<BallDetection> get currentShotTrajectory => _currentShotTrajectory;

  void _handleSensorUpdate() {
    // *** SISTEMA HÍBRIDO: ARDUINO + VISIÓN ***
    
    // Verificar si se detectó un acierto desde el bluetooth
    if (_bluetoothViewModel.shotDetected) {
      debugPrint('🎯 ARDUINO: Tiro detectado por sensor');
      
      // Verificar si hay confirmación visual
      if (detectedBall != null) {
        debugPrint('✅ CONFIRMADO: Arduino + Visión detectaron tiro');
        _handleShotDetected(true, ShotDetectionType.sensor);
      } else {
        debugPrint('⚠️ Arduino detectó tiro sin confirmación visual - registrando igualmente');
        // Arduino es confiable, registrar el tiro
        _handleShotDetected(true, ShotDetectionType.sensor);
      }
      return;
    }
    
    // Verificar la distancia del sensor para detectar tiros por proximidad
    if (_bluetoothViewModel.isConnected) {
      final distanciaActual = _bluetoothViewModel.distancia;
      
      // Si la distancia es menor que el umbral Y hay detección visual
      if (distanciaActual < _distanciaUmbral && detectedBall != null) {
        // Evitar múltiples detecciones en corto tiempo (debounce)
        if (_lastDistanceTriggerTime == null || 
            DateTime.now().difference(_lastDistanceTriggerTime!).inSeconds > 2) {
          _lastDistanceTriggerTime = DateTime.now();
          
          debugPrint('🎯 PROXIMIDAD + VISIÓN: Tiro detectado por distancia (${distanciaActual.toStringAsFixed(1)}cm) + pelota visible');
          _handleShotDetected(true, ShotDetectionType.sensor);
        }
      }
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
      
      // Esperar a que esté completamente inicializada
      await Future.delayed(Duration(milliseconds: 100));
      
      // Reiniciar procesamiento de frames
      await _startImageStream();
      
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

  Future<void> _startImageStream() async {
    if (!isInitialized || cameraController == null) {
      debugPrint('⚠️ No se puede iniciar stream - Inicializado: $isInitialized, Controller: ${cameraController != null}');
      return;
    }
    
    // Verificar que el controller esté realmente inicializado
    if (!cameraController!.value.isInitialized) {
      debugPrint('⚠️ Controller no está inicializado - esperando...');
      await Future.delayed(Duration(milliseconds: 100));
      if (!cameraController!.value.isInitialized) {
        debugPrint('❌ Controller sigue sin inicializarse');
        return;
      }
    }
    
    try {
      debugPrint('🎬 Iniciando image stream optimizado...');
      await cameraController!.startImageStream((CameraImage image) {
        // *** CONTROL DE VELOCIDAD MUY AGRESIVO PARA EVITAR BLOQUEOS ***
        final now = DateTime.now();
        if (_lastFrameProcessTime != null) {
          final elapsedMs = now.difference(_lastFrameProcessTime!).inMilliseconds;
          
          // Solo procesar 1 frame cada 500ms (2 FPS) para evitar bloqueos
          if (elapsedMs < 500) {
            return;
          }
        }
        
        // *** PROCESAMIENTO COMPLETAMENTE ASÍNCRONO ***
        if (!isProcessingFrame && isDetectionEnabled) {
          _lastFrameProcessTime = now;
          
          // Ejecutar en microtask para no bloquear el stream
          Future.microtask(() async {
            await _processImageForBallDetectionOptimized(image);
          });
        }
      });
    } catch (e) {
      debugPrint('❌ Error al iniciar image stream: $e');
    }
  }

  /// Sistema híbrido: Color detection rápida + ML Kit precisa en paralelo
  Future<void> _processImageForBallDetectionOptimized(CameraImage image) async {
    if (isProcessingFrame) return; // Evitar procesamiento concurrente
    
    isProcessingFrame = true;
    
    try {
      _updateFpsCounter();
      
      // *** DETECCIÓN RÁPIDA POR COLOR (SIEMPRE) ***
      BallDetection? colorDetection;
      BallDetection? mlKitDetection;
      
      // 1. DETECCIÓN ULTRA-RÁPIDA POR COLOR (hilo principal)
      if (_useColorDetectionFallback) {
        try {
          final processedImage = await compute(_convertCameraImageToImageUltraFast, image);
          if (processedImage != null) {
            colorDetection = await compute(_detectBasketballUltraFast, processedImage);
          }
        } catch (e) {
          debugPrint('⚠️ Error en detección por color: $e');
        }
      }
      
      // 2. DETECCIÓN ML KIT EN HILO SEPARADO (solo cada 3 frames para no sobrecargar)
      if (_useMLKitAnalysis && _poseDetectionService.isInitialized && 
          _totalDetectionsCount % 3 == 0) { // Solo cada 3 frames
        
        // Ejecutar ML Kit en compute (hilo separado) sin bloquear
        Future.microtask(() async {
          try {
            final basketballAnalysis = await compute(_processMLKitDetection, image);
            
            if (basketballAnalysis != null && basketballAnalysis.ballDetection.ballDetected) {
              final ballResult = basketballAnalysis.ballDetection;
              
              final mlKitBall = BallDetection(
                center: ballResult.ballPosition ?? Offset.zero,
                radius: ballResult.ballSize?.width ?? 20.0,
                confidence: ballResult.confidence,
                source: "ml_kit",
              );
              
              // Combinar detecciones si ambas existen
              _combineDetections(colorDetection, mlKitBall);
            }
          } catch (e) {
            debugPrint('⚠️ Error en ML Kit (hilo separado): $e');
          }
        });
      }
      
      // Usar detección por color inmediatamente (sin esperar ML Kit)
      if (colorDetection != null) {
        _totalDetectionsCount++;
        _lastDetectionTime = DateTime.now();
        detectedBall = colorDetection;
        debugPrint('🎯 Detección color #$_totalDetectionsCount (${colorDetection.confidence.toStringAsFixed(2)})');
        
        // *** DEBUG: Verificar que detectedBall se está actualizando ***
        _debugFrameCount++;
        if (_debugMode) {
          debugPrint('🔍 DEBUG: detectedBall actualizado -> Center: (${detectedBall!.center.dx.toStringAsFixed(1)}, ${detectedBall!.center.dy.toStringAsFixed(1)}), Radius: ${detectedBall!.radius.toStringAsFixed(1)}, Source: ${detectedBall!.source}');
        }
      } else {
        detectedBall = null;
        
        // *** DEBUG: Verificar cuando no hay detección ***
        if (_debugMode && _debugFrameCount % 60 == 0) { // Cada 2 segundos aprox
          debugPrint('🔍 DEBUG: No hay detección - Frame #$_debugFrameCount');
        }
      }
      
      // Verificar detección de tiros con sensor Arduino
      _checkArduinoShotDetection();
      
      // *** DEBUG: Verificar llamada a notifyListeners ***
      if (_debugMode && detectedBall != null) {
        debugPrint('🔔 DEBUG: Llamando notifyListeners() - detectedBall existe: ${detectedBall != null}');
      }
      
      // Notificar cambios de forma asíncrona
      WidgetsBinding.instance.addPostFrameCallback((_) {
        safeNotifyListeners();
      });
      
      // *** SISTEMA DE DETECCIÓN DE TIROS FALLIDOS ***
      if (colorDetection != null) {
        _analyzeTrajectoryForMissedShots(colorDetection);
      }
      
      // Verificar sistema híbrido: Arduino + Visión
      _updateFpsCounter();
      
    } catch (e) {
      debugPrint('❌ Error en procesamiento híbrido: $e');
    } finally {
      isProcessingFrame = false;
    }
  }
  
  /// Combinar detecciones de color y ML Kit para mayor precisión
  void _combineDetections(BallDetection? colorDetection, BallDetection? mlKitDetection) {
    if (colorDetection == null && mlKitDetection == null) return;
    
    // Si ambas detectan, usar la más confiable
    if (colorDetection != null && mlKitDetection != null) {
      final combinedConfidence = (colorDetection.confidence + mlKitDetection.confidence) / 2;
      final avgCenter = Offset(
        (colorDetection.center.dx + mlKitDetection.center.dx) / 2,
        (colorDetection.center.dy + mlKitDetection.center.dy) / 2,
      );
      
      detectedBall = BallDetection(
        center: avgCenter,
        radius: (colorDetection.radius + mlKitDetection.radius) / 2,
        confidence: combinedConfidence,
        source: "hybrid",
      );
      
      debugPrint('🎯 Detección híbrida: confianza ${combinedConfidence.toStringAsFixed(2)}');
    } else if (mlKitDetection != null && mlKitDetection.confidence > 0.7) {
      // Solo usar ML Kit si tiene alta confianza
      detectedBall = mlKitDetection;
      debugPrint('🤖 ML Kit prevalece: confianza ${mlKitDetection.confidence.toStringAsFixed(2)}');
    }
    // Si no, mantener la detección por color que ya está asignada
  }
  
  /// Verificar detección de tiros con sensor Arduino
  void _checkArduinoShotDetection() {
    if (_bluetoothViewModel.shotDetected) {
      debugPrint('🎯 TIRO DETECTADO POR ARDUINO! Confirmando con visión...');
      
      // Si hay detección visual, es un tiro confirmado
      if (detectedBall != null) {
        debugPrint('✅ Tiro confirmado: Arduino + Visión');
        _handleShotDetected(true, ShotDetectionType.sensor);
      } else {
        debugPrint('⚠️ Arduino detectó tiro pero sin confirmación visual');
        // Aún así registrar el tiro (Arduino es confiable)
        _handleShotDetected(true, ShotDetectionType.sensor);
      }
    }
  }

  void toggleDetection() {
    isDetectionEnabled = !isDetectionEnabled;
    notifyListeners();
    
    if (isDetectionEnabled) {
      // Usar Future para evitar problemas de sincronización
      Future.microtask(() async {
        await _startImageStream();
      });
    }
  }

  /// Versión híbrida: ML Kit primero, color como fallback
  Future<void> _processImageForBallDetectionFast(CameraImage image) async {
    try {
      // *** MEDIR RENDIMIENTO ***
      _updateFpsCounter();
      
      BallDetection? ballDetection;
      
      // *** OPCIÓN 1: DETECCIÓN ML KIT (PREFERIDA) ***
      if (_useMLKitAnalysis && _poseDetectionService.isInitialized) {
        try {
          final basketballAnalysis = await _poseDetectionService.analyzeBasketballFrame(image);
          
          if (basketballAnalysis != null && basketballAnalysis.ballDetection.ballDetected) {
            final ballResult = basketballAnalysis.ballDetection;
            
            // Convertir BallDetectionResult a BallDetection
            ballDetection = BallDetection(
              center: ballResult.ballPosition ?? Offset.zero,
              radius: ballResult.ballSize?.width ?? 20.0,
              confidence: ballResult.confidence,
              source: "ml_kit",
            );
            
            debugPrint('🎯 ML Kit: Pelota detectada en (${ballDetection.center.dx.toInt()}, ${ballDetection.center.dy.toInt()}) - Confianza: ${(ballDetection.confidence * 100).toStringAsFixed(1)}%');
          }
        } catch (e) {
          debugPrint('⚠️ Error en detección ML Kit: $e');
        }
      }
      
      // *** OPCIÓN 2: DETECCIÓN POR COLOR (FALLBACK) ***
      if (ballDetection == null && _useColorDetectionFallback) {
        try {
          // Procesar con la versión optimizada de color
          final processedImage = await compute(_convertCameraImageToImageFast, image);
          ballDetection = await compute(_detectBasketballFast, processedImage);
          
          if (ballDetection != null) {
            debugPrint('🎨 Color: Pelota detectada en (${ballDetection.center.dx.toInt()}, ${ballDetection.center.dy.toInt()}) - Confianza: ${(ballDetection.confidence * 100).toStringAsFixed(1)}%');
          }
        } catch (e) {
          debugPrint('⚠️ Error en detección por color: $e');
        }
      }
      
      // *** FILTRAR DETECCIONES FUERA DEL ÁREA VISIBLE ***
      BallDetection? filteredDetection;
      if (ballDetection != null) {
        filteredDetection = _filterDetectionToVisibleArea(ballDetection, image);
      }
      
      // *** CONTAR DETECCIONES ***
      if (filteredDetection != null) {
        _totalDetectionsCount++;
        _lastDetectionTime = DateTime.now();
        
        final detectionType = _useMLKitAnalysis && _poseDetectionService.isInitialized ? "ML Kit" : "Color";
        debugPrint('🎯 Detección #$_totalDetectionsCount ($detectionType) - FPS: ${_currentDetectionFps.toStringAsFixed(1)}');
      }
      
      // Filtrado temporal MUCHO MÁS PERMISIVO (igual que antes)
      if (filteredDetection != null) {
        // Solo verificar que la detección no sea completamente errática
        if (_detectionBuffer.isNotEmpty) {
          final lastDetection = _detectionBuffer.last;
          
          if (lastDetection != null) {
            final dx = filteredDetection.center.dx - lastDetection.center.dx;
            final dy = filteredDetection.center.dy - lastDetection.center.dy;
            final distance = sqrt(dx * dx + dy * dy);
            
            // Solo rechazar si el salto es EXTREMADAMENTE grande
            if (distance > 200) { // Muy permisivo
              debugPrint('⚠️ Detección rechazada por salto extremo: ${distance.toStringAsFixed(1)}px');
              _detectionBuffer.add(null);
              notifyListeners();
              isProcessingFrame = false;
              return;
            }
          }
        }
      }
      
      // Añadir detección actual
      _detectionBuffer.add(filteredDetection);
      detectedBall = filteredDetection;
      
      _detectBasketballMotion();
      
      notifyListeners();
    } catch (e) {
      debugPrint('Image processing error: $e');
    } finally {
      isProcessingFrame = false;
    }
  }

  /// *** MÉTODO ACTUALIZADO PARA IMAGEN ESTIRADA SIN CROP ***
  BallDetection? _filterDetectionToVisibleArea(BallDetection detection, CameraImage image) {
    // Con BoxFit.fill, la imagen completa se estira para llenar toda la pantalla
    // No hay crop, solo escalado, por lo que toda la imagen es visible
    
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    
    // Toda la imagen es visible - no hay área cortada
    final visibleLeft = 0.0;
    final visibleRight = imageWidth;
    final visibleTop = 0.0;
    final visibleBottom = imageHeight;
    
    // Verificar si la detección está dentro de los límites de la imagen
    final ballX = detection.center.dx;
    final ballY = detection.center.dy;
    
    if (ballX >= visibleLeft && ballX <= visibleRight && 
        ballY >= visibleTop && ballY <= visibleBottom) {
      debugPrint('✅ Detección dentro de la imagen: (${ballX.toInt()}, ${ballY.toInt()})');
      debugPrint('📦 Imagen completa: ${imageWidth.toInt()}x${imageHeight.toInt()}');
      return detection;
    } else {
      debugPrint('🚫 Detección fuera de la imagen: (${ballX.toInt()}, ${ballY.toInt()}) - ignorando');
      debugPrint('📦 Límites de imagen: 0,0 - ${imageWidth.toInt()},${imageHeight.toInt()}');
      return null;
    }
  }

  void _detectBasketballMotion() {
    // *** NUEVO SISTEMA COMPLETO DE ANÁLISIS DE TRAYECTORIA ***
    
    final now = DateTime.now();
    
    // Si hay detección actual, agregar al buffer de trayectoria
    if (detectedBall != null) {
      _addTrajectoryPoint(detectedBall!, now);
    }
    
    // Limpiar puntos antiguos del buffer
    _cleanOldTrajectoryPoints(now);
    
    // Analizar trayectoria actual
    _analyzeCurrentTrajectory();
    
    // Actualizar fase del tiro
    _updateShotPhase();
    
    // Detectar si hay un intento de tiro
    _detectShotAttempt();
  }

  /// *** AGREGAR PUNTO A LA TRAYECTORIA ***
  void _addTrajectoryPoint(BallDetection ball, DateTime timestamp) {
    // Calcular velocidad si hay puntos previos
    double velocity = 0.0;
    Offset velocityVector = Offset.zero;
    
    if (_trajectoryBuffer.isNotEmpty) {
      final lastPoint = _trajectoryBuffer.last;
      final timeDiff = timestamp.difference(lastPoint.timestamp).inMilliseconds / 1000.0;
      
      if (timeDiff > 0) {
        final displacement = ball.center - lastPoint.position;
        velocity = displacement.distance / timeDiff;
        velocityVector = displacement / timeDiff;
      }
    }
    
    final trajectoryPoint = TrajectoryPoint(
      position: ball.center,
      timestamp: timestamp,
      velocity: velocity,
      velocityVector: velocityVector,
    );
    
    _trajectoryBuffer.add(trajectoryPoint);
    
    // Limitar el tamaño del buffer
    if (_trajectoryBuffer.length > _maxTrajectoryPoints) {
      _trajectoryBuffer.removeAt(0);
    }
    
    debugPrint('📍 Punto de trayectoria agregado: (${ball.center.dx.toInt()}, ${ball.center.dy.toInt()}) - Velocidad: ${velocity.toStringAsFixed(1)} px/s');
  }

  /// *** LIMPIAR PUNTOS ANTIGUOS ***
  void _cleanOldTrajectoryPoints(DateTime now) {
    _trajectoryBuffer.removeWhere((point) {
      return now.difference(point.timestamp).inSeconds > 3;
    });
  }

  /// *** ANALIZAR TRAYECTORIA ACTUAL ***
  void _analyzeCurrentTrajectory() {
    if (_trajectoryBuffer.length < 5) {
      _currentShotAnalysis = null;
      return;
    }
    
    // Análisis de la trayectoria
    final isShotAttempt = _detectShotPattern();
    
    if (isShotAttempt) {
      final analysis = _performDetailedShotAnalysis();
      _currentShotAnalysis = analysis;
      
      if (analysis.isShotAttempt) {
        debugPrint('🏀 ¡TIRO DETECTADO!');
        debugPrint('   📐 Ángulo de release: ${analysis.releaseAngle.toStringAsFixed(1)}°');
        debugPrint('   🚀 Velocidad: ${analysis.releaseVelocity.toStringAsFixed(1)} px/s');
        debugPrint('   🎯 Predicción: ${analysis.isPredictedMake ? "ACIERTO" : "FALLO"}');
        debugPrint('   📊 Confianza: ${(analysis.confidence * 100).toStringAsFixed(1)}%');
        
        if (analysis.predictedLandingPoint != null) {
          debugPrint('   📍 Punto estimado: (${analysis.predictedLandingPoint!.dx.toInt()}, ${analysis.predictedLandingPoint!.dy.toInt()})');
        }
      }
    }
  }

  /// *** DETECTAR PATRÓN DE TIRO ***
  bool _detectShotPattern() {
    if (_trajectoryBuffer.length < 8) return false;
    
    // Analizar últimos 8-15 puntos para detectar movimiento parabólico
    final recentPoints = _trajectoryBuffer.length > 15 
        ? _trajectoryBuffer.sublist(_trajectoryBuffer.length - 15)
        : _trajectoryBuffer;
    
    // 1. Verificar si hay suficiente movimiento vertical
    final yPositions = recentPoints.map((p) => p.position.dy).toList();
    final minY = yPositions.reduce(min);
    final maxY = yPositions.reduce(max);
    final verticalRange = maxY - minY;
    
    if (verticalRange < 30) return false; // Muy poco movimiento vertical
    
    // 2. Verificar velocidad significativa
    final avgVelocity = recentPoints.map((p) => p.velocity).reduce((a, b) => a + b) / recentPoints.length;
    if (avgVelocity < 50) return false; // Muy lento
    
    // 3. Buscar patrón parabólico (sube y luego baja)
    bool hasAscent = false;
    bool hasDescent = false;
    
    // Encontrar el punto más alto
    int peakIndex = -1;
    for (int i = 0; i < yPositions.length; i++) {
      if (yPositions[i] == minY) {
        peakIndex = i;
        break;
      }
    }
    
    if (peakIndex > 2 && peakIndex < yPositions.length - 2) {
      // Verificar ascenso antes del pico
      for (int i = 1; i < peakIndex; i++) {
        if (yPositions[i] <= yPositions[i-1]) {
          hasAscent = true;
          break;
        }
      }
      
      // Verificar descenso después del pico
      for (int i = peakIndex + 1; i < yPositions.length; i++) {
        if (yPositions[i] >= yPositions[i-1]) {
          hasDescent = true;
          break;
        }
      }
    }
    
    return hasAscent || hasDescent || avgVelocity > 100; // Criterio más permisivo
  }

  /// *** ANÁLISIS DETALLADO DEL TIRO ***
  ShotAnalysis _performDetailedShotAnalysis() {
    final trajectory = List<TrajectoryPoint>.from(_trajectoryBuffer);
    
    // Encontrar punto de release (velocidad máxima o cambio de dirección)
    int releaseIndex = _findReleasePoint(trajectory);
    final releasePoint = trajectory[releaseIndex].position;
    
    // Calcular ángulo y velocidad de release
    final releaseAngle = _calculateReleaseAngle(trajectory, releaseIndex);
    final releaseVelocity = trajectory[releaseIndex].velocity;
    
    // Predecir trayectoria usando física
    final prediction = _predictTrajectory(releasePoint, trajectory[releaseIndex].velocityVector);
    
    // Verificar si pasará por la zona de la canasta
    bool isPredictedMake = false;
    if (_basketZone != null && prediction != null) {
      isPredictedMake = _basketZone!.isNearBasket(prediction);
    }
    
    // Calcular confianza basada en la calidad de los datos
    final confidence = _calculateAnalysisConfidence(trajectory, releaseVelocity);
    
    return ShotAnalysis(
      trajectory: trajectory,
      isShotAttempt: true,
      isMake: isPredictedMake,
      shotQuality: confidence,
      confidence: confidence,
      releaseAngle: releaseAngle,
      releaseVelocity: releaseVelocity,
      releasePoint: releasePoint,
      predictedLandingPoint: prediction,
      phase: _currentShotPhase,
      isPredictedMake: isPredictedMake,
    );
  }

  /// *** ENCONTRAR PUNTO DE RELEASE ***
  int _findReleasePoint(List<TrajectoryPoint> trajectory) {
    if (trajectory.length < 3) return 0;
    
    // Buscar el punto con mayor velocidad en la primera mitad de la trayectoria
    int maxVelocityIndex = 0;
    double maxVelocity = 0;
    
    final searchRange = min(trajectory.length, trajectory.length ~/ 2 + 5);
    
    for (int i = 0; i < searchRange; i++) {
      if (trajectory[i].velocity > maxVelocity) {
        maxVelocity = trajectory[i].velocity;
        maxVelocityIndex = i;
      }
    }
    
    return maxVelocityIndex;
  }

  /// *** CALCULAR ÁNGULO DE RELEASE ***
  double _calculateReleaseAngle(List<TrajectoryPoint> trajectory, int releaseIndex) {
    if (releaseIndex >= trajectory.length - 1) return 45.0;
    
    final releasePoint = trajectory[releaseIndex];
    final velocityVector = releasePoint.velocityVector;
    
    // Calcular ángulo respecto al horizonte
    final angle = atan2(-velocityVector.dy, velocityVector.dx.abs()) * 180 / pi;
    return angle.clamp(0, 90);
  }

  /// *** PREDECIR TRAYECTORIA USANDO FÍSICA ***
  Offset? _predictTrajectory(Offset releasePoint, Offset initialVelocity) {
    // Simulación física simple (projectile motion)
    const gravity = 980.0; // píxeles/s² (ajustado para resolución de imagen)
    const timeStep = 0.05; // 50ms steps
    const maxTime = 3.0; // máximo 3 segundos de vuelo
    
    double x = releasePoint.dx;
    double y = releasePoint.dy;
    double vx = initialVelocity.dx;
    double vy = initialVelocity.dy;
    
    for (double t = 0; t < maxTime; t += timeStep) {
      x += vx * timeStep;
      y += vy * timeStep;
      vy += gravity * timeStep; // Gravedad hacia abajo (Y positivo)
      
      // Si la pelota bajó del punto de release considerablemente, esa es la predicción
      if (y > releasePoint.dy + 100) {
        return Offset(x, y);
      }
    }
    
    return Offset(x, y);
  }

  /// *** CALCULAR CONFIANZA DEL ANÁLISIS ***
  double _calculateAnalysisConfidence(List<TrajectoryPoint> trajectory, double releaseVelocity) {
    // Factores que afectan la confianza:
    // 1. Número de puntos en la trayectoria
    // 2. Consistencia de la velocidad
    // 3. Calidad de la detección
    
    final pointsScore = min(1.0, trajectory.length / 15.0);
    final velocityScore = min(1.0, releaseVelocity / 200.0);
    final consistencyScore = _calculateVelocityConsistency(trajectory);
    
    return (pointsScore + velocityScore + consistencyScore) / 3.0;
  }

  /// *** CALCULAR CONSISTENCIA DE VELOCIDAD ***
  double _calculateVelocityConsistency(List<TrajectoryPoint> trajectory) {
    if (trajectory.length < 3) return 0.0;
    
    final velocities = trajectory.map((p) => p.velocity).toList();
    final avgVelocity = velocities.reduce((a, b) => a + b) / velocities.length;
    
    // Calcular desviación estándar
    final variance = velocities.map((v) => pow(v - avgVelocity, 2)).reduce((a, b) => a + b) / velocities.length;
    final stdDev = sqrt(variance);
    
    // Menor desviación = mayor consistencia
    return max(0.0, 1.0 - (stdDev / avgVelocity));
  }

  /// *** ACTUALIZAR FASE DEL TIRO ***
  void _updateShotPhase() {
    if (_trajectoryBuffer.isEmpty) {
      _currentShotPhase = ShotPhase.noShot;
      return;
    }
    
    final recentVelocity = _trajectoryBuffer.length > 5 
        ? _trajectoryBuffer.sublist(_trajectoryBuffer.length - 5).map((p) => p.velocity).reduce((a, b) => a + b) / 5
        : _trajectoryBuffer.last.velocity;
    
    if (recentVelocity > 100) {
      _currentShotPhase = ShotPhase.flight;
    } else if (recentVelocity > 50) {
      _currentShotPhase = ShotPhase.release;
    } else if (_trajectoryBuffer.length > 3) {
      _currentShotPhase = ShotPhase.preparation;
    } else {
      _currentShotPhase = ShotPhase.noShot;
    }
  }

  /// *** DETECTAR INTENTO DE TIRO ***
  void _detectShotAttempt() {
    if (_currentShotAnalysis != null && _currentShotAnalysis!.isShotAttempt) {
      // Verificar si es un nuevo tiro (evitar múltiples detecciones)
      final timeSinceLastShot = _lastShotDetectionTime != null 
          ? DateTime.now().difference(_lastShotDetectionTime!).inSeconds 
          : 999;
      
      if (timeSinceLastShot > 3) {
        final isSuccessful = _currentShotAnalysis!.isPredictedMake;
        _handleShotDetected(isSuccessful, ShotDetectionType.camera);
      }
    }
  }

  /// *** MÉTODO PARA DEBUG VISUAL ***
  void enableVisualDebug() {
    debugPrint('🔧 Debug visual habilitado - Los logs mostrarán detalles de detección');
  }
  
  void disableVisualDebug() {
    debugPrint('🔧 Debug visual deshabilitado');
  }
  
  /// *** OBTENER ESTADÍSTICAS DE DETECCIÓN PARA DEBUG ***
  String getDetectionDebugInfo() {
    final info = StringBuffer();
    info.writeln('=== DEBUG DETECCIÓN DE PELOTA ===');
    info.writeln('Detección habilitada: $isDetectionEnabled');
    info.writeln('Procesando frame: $isProcessingFrame');
    info.writeln('Última detección: ${detectedBall != null ? "SÍ" : "NO"}');
    
    if (detectedBall != null) {
      info.writeln('Centro: (${detectedBall!.center.dx.toInt()}, ${detectedBall!.center.dy.toInt()})');
      info.writeln('Radio: ${detectedBall!.radius.toStringAsFixed(1)}');
      info.writeln('Confianza: ${(detectedBall!.confidence * 100).toStringAsFixed(1)}%');
    }
    
    // *** INFORMACIÓN DE TRAYECTORIA ***
    info.writeln('\n=== ANÁLISIS DE TRAYECTORIA ===');
    info.writeln('Puntos en buffer: ${_trajectoryBuffer.length}');
    info.writeln('Fase actual: $_currentShotPhase');
    info.writeln('Tracking activo: $_isTrajectoryTracking');
    
    if (_currentShotAnalysis != null) {
      final analysis = _currentShotAnalysis!;
      info.writeln('\n--- ANÁLISIS ACTUAL ---');
      info.writeln('Es intento de tiro: ${analysis.isShotAttempt}');
      info.writeln('Predicción: ${analysis.isPredictedMake ? "ACIERTO" : "FALLO"}');
      info.writeln('Ángulo: ${analysis.releaseAngle.toStringAsFixed(1)}°');
      info.writeln('Velocidad: ${analysis.releaseVelocity.toStringAsFixed(1)} px/s');
      info.writeln('Confianza: ${(analysis.confidence * 100).toStringAsFixed(1)}%');
    }
    
    // *** INFORMACIÓN DE ZONA DE CANASTA ***
    if (_basketZone != null) {
      info.writeln('\n--- ZONA DE CANASTA ---');
      info.writeln('Centro: (${_basketZone!.center.dx.toInt()}, ${_basketZone!.center.dy.toInt()})');
      info.writeln('Radio: ${_basketZone!.radius.toStringAsFixed(1)}');
    } else {
      info.writeln('\n--- ZONA DE CANASTA: NO CALIBRADA ---');
    }
    
    info.writeln('\n--- ESTADÍSTICAS ---');
    info.writeln('Tiros exitosos: $_successfulShots');
    info.writeln('Tiros totales: $_totalShots');
    info.writeln('FPS de detección: ${_currentDetectionFps.toStringAsFixed(1)}');
    
    return info.toString();
  }

  /// *** MÉTODOS PARA CALIBRACIÓN DE CANASTA ***
  
  /// Iniciar calibración de la zona de canasta
  void startBasketCalibration() {
    _isCalibrating = true;
    _basketCenter = null;
    debugPrint('🎯 Calibración de canasta iniciada - Toca la pantalla donde está el aro');
    notifyListeners();
  }
  
  /// Finalizar calibración de la zona de canasta
  void finishBasketCalibration() {
    if (_basketCenter != null) {
      _basketZone = BasketZone(
        center: _basketCenter!,
        radius: _basketRadius,
        rimHeight: _basketRimHeight,
      );
      debugPrint('✅ Zona de canasta calibrada: ${_basketCenter}');
    }
    _isCalibrating = false;
    notifyListeners();
  }
  
  /// Establecer centro de la canasta (llamado desde la UI)
  void setBasketCenter(Offset center) {
    _basketCenter = center;
    debugPrint('🎯 Centro de canasta establecido: $center');
    notifyListeners();
  }
  
  /// Ajustar radio de la zona de canasta
  void adjustBasketRadius(double radius) {
    _basketRadius = radius.clamp(30.0, 150.0);
    if (_basketCenter != null) {
      _basketZone = BasketZone(
        center: _basketCenter!,
        radius: _basketRadius,
        rimHeight: _basketRimHeight,
      );
    }
    debugPrint('📏 Radio de canasta ajustado: $_basketRadius');
    notifyListeners();
  }
  
  /// Activar/desactivar tracking de trayectoria
  void toggleTrajectoryTracking() {
    _isTrajectoryTracking = !_isTrajectoryTracking;
    
    if (!_isTrajectoryTracking) {
      _trajectoryBuffer.clear();
      _currentShotAnalysis = null;
      _currentShotPhase = ShotPhase.noShot;
    }
    
    debugPrint('📈 Tracking de trayectoria: ${_isTrajectoryTracking ? "ACTIVADO" : "DESACTIVADO"}');
    notifyListeners();
  }
  
  /// Obtener información detallada de la trayectoria actual
  String getTrajectoryAnalysisInfo() {
    final info = StringBuffer();
    info.writeln('=== ANÁLISIS DE TRAYECTORIA DETALLADO ===');
    
    if (_trajectoryBuffer.isEmpty) {
      info.writeln('No hay datos de trayectoria');
      return info.toString();
    }
    
    info.writeln('Puntos registrados: ${_trajectoryBuffer.length}');
    info.writeln('Tiempo total: ${_trajectoryBuffer.last.timestamp.difference(_trajectoryBuffer.first.timestamp).inMilliseconds}ms');
    
    // Estadísticas de velocidad
    final velocities = _trajectoryBuffer.map((p) => p.velocity).toList();
    final avgVelocity = velocities.isNotEmpty 
        ? velocities.reduce((a, b) => a + b) / velocities.length 
        : 0.0;
    final maxVelocity = velocities.isNotEmpty 
        ? velocities.reduce(max) 
        : 0.0;
    
    info.writeln('Velocidad promedio: ${avgVelocity.toStringAsFixed(1)} px/s');
    info.writeln('Velocidad máxima: ${maxVelocity.toStringAsFixed(1)} px/s');
    
    // Rango de movimiento
    if (_trajectoryBuffer.length > 1) {
      final xPositions = _trajectoryBuffer.map((p) => p.position.dx).toList();
      final yPositions = _trajectoryBuffer.map((p) => p.position.dy).toList();
      
      final xRange = xPositions.reduce(max) - xPositions.reduce(min);
      final yRange = yPositions.reduce(max) - yPositions.reduce(min);
      
      info.writeln('Rango horizontal: ${xRange.toStringAsFixed(1)} px');
      info.writeln('Rango vertical: ${yRange.toStringAsFixed(1)} px');
    }
    
    if (_currentShotAnalysis != null) {
      final analysis = _currentShotAnalysis!;
      info.writeln('\n--- PREDICCIÓN FÍSICA ---');
      info.writeln('Ángulo de lanzamiento: ${analysis.releaseAngle.toStringAsFixed(1)}°');
      info.writeln('Velocidad inicial: ${analysis.releaseVelocity.toStringAsFixed(1)} px/s');
      if (analysis.predictedLandingPoint != null) {
        info.writeln('Punto de aterrizaje: (${analysis.predictedLandingPoint!.dx.toInt()}, ${analysis.predictedLandingPoint!.dy.toInt()})');
      }
      if (_basketZone != null && analysis.predictedLandingPoint != null) {
        final distance = (analysis.predictedLandingPoint! - _basketZone!.center).distance;
        info.writeln('Distancia al aro: ${distance.toStringAsFixed(1)} px');
      }
    }
    
    return info.toString();
  }

  /// Simular un tiro para testing del sistema de análisis
  void simulateTrajectoryShot() {
    debugPrint('🧪 Simulando trayectoria de tiro para testing...');
    
    // Crear una trayectoria simulada parabólica
    _trajectoryBuffer.clear();
    final now = DateTime.now();
    
    // Puntos de una trayectoria de tiro simulada
    final startPoint = Offset(100, 400);
    final peakPoint = Offset(300, 200);
    final endPoint = Offset(500, 450);
    
    // Generar puntos intermedios
    for (int i = 0; i < 30; i++) {
      final t = i / 29.0; // 0 a 1
      
      // Interpolación parabólica
      final x = startPoint.dx + (endPoint.dx - startPoint.dx) * t;
      final y = _parabolicInterpolation(startPoint.dy, peakPoint.dy, endPoint.dy, t);
      
      final timestamp = now.add(Duration(milliseconds: i * 100));
      final position = Offset(x, y);
      
      // Calcular velocidad simulada
      double velocity = 100 + 50 * sin(t * pi);
      Offset velocityVector = i > 0 
          ? (position - _trajectoryBuffer.last.position) / 0.1
          : Offset(200, -150);
      
      _trajectoryBuffer.add(TrajectoryPoint(
        position: position,
        timestamp: timestamp,
        velocity: velocity,
        velocityVector: velocityVector,
      ));
    }
    
    debugPrint('✅ Trayectoria simulada generada con ${_trajectoryBuffer.length} puntos');
    
    // Analizar la trayectoria simulada
    _analyzeCurrentTrajectory();
    
    notifyListeners();
  }
  
  /// Interpolación parabólica para simulación
  double _parabolicInterpolation(double start, double peak, double end, double t) {
    // Curva parabólica que pasa por los tres puntos
    if (t <= 0.5) {
      // Primera mitad: de start a peak
      final localT = t * 2;
      return start + (peak - start) * (2 * localT - localT * localT);
    } else {
      // Segunda mitad: de peak a end
      final localT = (t - 0.5) * 2;
      return peak + (end - peak) * (localT * localT);
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
      
      // Guardar la referencia al archivo actual
      currentRecordingFile = XFile(videoPath);
      
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
    
    // Verificar que el controller esté realmente inicializado
    if (!cameraController!.value.isInitialized) {
      debugPrint('⚠️ Controller de cámara no está inicializado para grabación');
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
    
    // Verificar que el controller esté realmente inicializado
    if (!cameraController!.value.isInitialized) {
      debugPrint('⚠️ Controller de cámara no está inicializado para nuevo segmento');
      return;
    }
    
    // Verificar que la cámara no esté ya grabando
    if (cameraController!.value.isRecordingVideo) {
      debugPrint('⚠️ La cámara ya está grabando, deteniendo primero...');
      try {
        await cameraController!.stopVideoRecording();
        await Future.delayed(Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('⚠️ Error al detener grabación previa: $e');
      }
    }
    
    try {
      // Generar path único para este segmento
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = await _sessionRepository.getNewVideoFilePath();
      _currentRecordingPath = _currentRecordingPath!.replaceAll('.mp4', '_segment_${_segmentCounter}_$timestamp.mp4');
      
      debugPrint('🎥 Iniciando segmento #$_segmentCounter: $_currentRecordingPath');
      
      // Iniciar grabación con verificación adicional
      await cameraController!.startVideoRecording();
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

  /// Conversión de imagen optimizada para mayor velocidad
  static img.Image? _convertCameraImageToImageFast(CameraImage cameraImage) {
    try {
      // Reducir la resolución para procesamiento más rápido
      final originalWidth = cameraImage.width;
      final originalHeight = cameraImage.height;
      
      // Procesar a la mitad de resolución para 4x más velocidad
      final width = originalWidth ~/ 2;
      final height = originalHeight ~/ 2;
      
      if (Platform.isAndroid) {
        // Android usa YUV - versión optimizada
        final yuvImage = img.Image(width: width, height: height);
        
        final yBuffer = cameraImage.planes[0].bytes;
        final yRowStride = cameraImage.planes[0].bytesPerRow;
        final yPixelStride = cameraImage.planes[0].bytesPerPixel ?? 1;
        
        final uBuffer = cameraImage.planes[1].bytes;
        final uRowStride = cameraImage.planes[1].bytesPerRow;
        final uPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;
        final vBuffer = cameraImage.planes[2].bytes;
        final vRowStride = cameraImage.planes[2].bytesPerRow;
        final vPixelStride = cameraImage.planes[2].bytesPerPixel ?? 1;
        
        // Procesar cada 2 píxeles para mayor velocidad
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final origH = h * 2;
            final origW = w * 2;
            
            final yIndex = origH * yRowStride + origW * yPixelStride;
            final uvh = origH ~/ 2;
            final uvw = origW ~/ 2;
            final uIndex = uvh * uRowStride + uvw * uPixelStride;
            final vIndex = uvh * vRowStride + uvw * vPixelStride;
            
            if (yIndex < yBuffer.length && 
                uIndex < uBuffer.length && 
                vIndex < vBuffer.length) {
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
        // iOS usa BGRA - versión optimizada
        final bgra = img.Image(width: width, height: height);
        
        final buffer = cameraImage.planes[0].bytes;
        final rowStride = cameraImage.planes[0].bytesPerRow;
        final pixelStride = cameraImage.planes[0].bytesPerPixel ?? 4;
        
        // Procesar cada 2 píxeles para mayor velocidad
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final origH = h * 2;
            final origW = w * 2;
            final index = origH * rowStride + origW * pixelStride;
            
            if (index + 3 < buffer.length) {
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

  /// Detección de baloncesto SIMPLIFICADA y más efectiva
  static BallDetection? _detectBasketballFast(img.Image? image) {
    if (image == null) return null;
    
    final width = image.width;
    final height = image.height;
    
    debugPrint('🔍 === DETECCIÓN SIMPLIFICADA ===');
    debugPrint('📐 Imagen: ${width}x${height}');
    
    // *** PASO 1: ENCONTRAR PÍXELES NARANJAS/MARRONES DE FORMA SIMPLE ***
    final candidatePixels = <PixelPoint>[];
    int totalPixels = 0;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        totalPixels++;
        
        // Detección de color MÁS SIMPLE y PERMISIVA
        if (_isBasketballColorSimple(r, g, b)) {
          candidatePixels.add(PixelPoint(x, y));
        }
      }
    }
    
    debugPrint('🎨 Píxeles candidatos: ${candidatePixels.length} de $totalPixels (${(candidatePixels.length / totalPixels * 100).toStringAsFixed(1)}%)');
    
    if (candidatePixels.length < 10) {
      debugPrint('❌ Muy pocos píxeles candidatos (${candidatePixels.length} < 10)');
      return null;
    }
    
    // *** PASO 2: AGRUPAR PÍXELES CERCANOS ***
    final clusters = _findSimpleClusters(candidatePixels);
    debugPrint('🔗 Clusters encontrados: ${clusters.length}');
    
    if (clusters.isEmpty) {
      debugPrint('❌ No se encontraron clusters');
      return null;
    }
    
    // *** PASO 3: EVALUAR CADA CLUSTER CON CRITERIOS SIMPLES ***
    BallDetection? bestBall;
    double bestScore = 0;
    
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      debugPrint('🔍 Evaluando cluster #$i con ${cluster.length} píxeles');
      
      final ball = _evaluateClusterSimple(cluster);
      
      if (ball != null) {
        final score = ball.confidence;
        debugPrint('✅ Cluster #$i válido - Score: ${score.toStringAsFixed(3)}');
        debugPrint('   Centro: (${ball.center.dx.toInt()}, ${ball.center.dy.toInt()})');
        debugPrint('   Radio: ${ball.radius.toStringAsFixed(1)}');
        
        if (score > bestScore) {
          bestScore = score;
          bestBall = ball;
        }
      } else {
        debugPrint('❌ Cluster #$i rechazado');
      }
    }
    
    if (bestBall != null) {
      debugPrint('🎯 ¡PELOTA DETECTADA!');
      debugPrint('   Centro final: (${bestBall.center.dx.toInt()}, ${bestBall.center.dy.toInt()})');
      debugPrint('   Radio final: ${bestBall.radius.toStringAsFixed(1)}');
      debugPrint('   Confianza final: ${(bestBall.confidence * 100).toStringAsFixed(1)}%');
    } else {
      debugPrint('❌ Ningún cluster pasó la validación');
    }
    
    debugPrint('🔍 === FIN DETECCIÓN ===\n');
    
    return bestBall;
  }

  /// NUEVA función de detección de color SIMPLE y PERMISIVA
  static bool _isBasketballColorSimple(int r, int g, int b) {
    // CRITERIO 1: NARANJA BÁSICO (muy permisivo)
    // R > G > B y suficiente intensidad
    if (r > g && g > b && r > 60 && g > 20 && (r - b) > 15) {
      return true;
    }
    
    // CRITERIO 2: MARRÓN/CUERO (para pelotas más oscuras)
    // Colores marrones/tierra
    if (r >= 70 && r <= 180 && 
        g >= 40 && g <= 140 && 
        b >= 20 && b <= 100 && 
        r > b && g > b && 
        (r - b) > 10) {
      return true;
    }
    
    // CRITERIO 3: ROJO-NARANJA (ciertas iluminaciones)
    // Más rojo pero con algo de naranja
    if (r > 100 && g > 30 && g < r * 0.8 && b < g && (r - g) > 20) {
      return true;
    }
    
    // CRITERIO 4: VERIFICACIÓN HSV SIMPLE
    final total = r + g + b;
    if (total > 120) { // No muy oscuro
      final rRatio = r / total;
      final gRatio = g / total;
      final bRatio = b / total;
      
      // Debe tener más rojo que azul, y balance entre rojo y verde
      if (rRatio > 0.35 && bRatio < 0.3 && rRatio > bRatio && gRatio > bRatio) {
        return true;
      }
    }
    
    return false;
  }

  /// Función SIMPLE de clustering
  static List<List<PixelPoint>> _findSimpleClusters(List<PixelPoint> points) {
    if (points.isEmpty) return [];
    
    final visited = List.filled(points.length, false);
    final clusters = <List<PixelPoint>>[];
    
    for (int i = 0; i < points.length; i++) {
      if (visited[i]) continue;
      
      final cluster = <PixelPoint>[];
      final queue = <int>[i];
      
      while (queue.isNotEmpty && cluster.length < 3000) {
        final currentIndex = queue.removeAt(0);
        if (visited[currentIndex]) continue;
        
        visited[currentIndex] = true;
        cluster.add(points[currentIndex]);
        
        // Buscar vecinos cercanos (radio de 20 píxeles)
        final currentPoint = points[currentIndex];
        for (int j = 0; j < points.length; j++) {
          if (visited[j]) continue;
          
          final neighbor = points[j];
          final dx = currentPoint.x - neighbor.x;
          final dy = currentPoint.y - neighbor.y;
          final distance = sqrt(dx * dx + dy * dy);
          
          if (distance <= 20) { // Radio generoso
            queue.add(j);
          }
        }
      }
      
      // Solo mantener clusters con tamaño mínimo
      if (cluster.length >= 8) { // Muy permisivo
        clusters.add(cluster);
      }
    }
    
    // Ordenar por tamaño (más grandes primero)
    clusters.sort((a, b) => b.length.compareTo(a.length));
    
    return clusters.take(5).toList(); // Máximo 5 clusters
  }

  /// Evaluación SIMPLE de cluster
  static BallDetection? _evaluateClusterSimple(List<PixelPoint> cluster) {
    if (cluster.length < 8) return null;
    
    // Calcular centro de masa
    double sumX = 0, sumY = 0;
    int minX = cluster[0].x, maxX = cluster[0].x;
    int minY = cluster[0].y, maxY = cluster[0].y;
    
    for (final point in cluster) {
      sumX += point.x;
      sumY += point.y;
      minX = min(minX, point.x);
      maxX = max(maxX, point.x);
      minY = min(minY, point.y);
      maxY = max(maxY, point.y);
    }
    
    final centerX = sumX / cluster.length;
    final centerY = sumY / cluster.length;
    final center = Offset(centerX, centerY);
    
    final width = maxX - minX + 1;
    final height = maxY - minY + 1;
    
    // VERIFICACIONES SIMPLES
    
    // 1. Tamaño razonable
    if (cluster.length < 8 || cluster.length > 5000) {
      debugPrint('   ❌ Tamaño inválido: ${cluster.length}');
      return null;
    }
    
    // 2. Forma no muy alargada (muy permisivo)
    final aspectRatio = max(width, height) / min(width, height);
    if (aspectRatio > 5.0) { // Muy permisivo
      debugPrint('   ❌ Muy alargado: ${aspectRatio.toStringAsFixed(2)}');
      return null;
    }
    
    // 3. Densidad básica
    final boundingArea = width * height;
    final density = cluster.length / boundingArea;
    if (density < 0.1) { // Muy permisivo
      debugPrint('   ❌ Densidad muy baja: ${(density * 100).toStringAsFixed(1)}%');
      return null;
    }
    
    // CALCULAR SCORE SIMPLE
    final radius = sqrt(cluster.length / pi);
    
    // Score basado en tamaño (favorece pelotas de tamaño medio)
    double sizeScore;
    if (cluster.length >= 30 && cluster.length <= 800) {
      sizeScore = 1.0;
    } else if (cluster.length >= 15 && cluster.length <= 1500) {
      sizeScore = 0.7;
    } else {
      sizeScore = 0.4;
    }
    
    // Score basado en forma (favorece formas más cuadradas)
    final shapeScore = min(1.0, 3.0 / aspectRatio);
    
    // Score basado en densidad
    final densityScore = min(1.0, density * 5);
    
    // Score final (muy permisivo)
    final finalScore = (sizeScore * 0.4 + shapeScore * 0.3 + densityScore * 0.3);
    
    // Umbral MUY permisivo
    if (finalScore < 0.25) {
      debugPrint('   ❌ Score insuficiente: ${finalScore.toStringAsFixed(3)}');
      return null;
    }
    
    debugPrint('   ✅ Válido - Tamaño: ${cluster.length}, Forma: ${aspectRatio.toStringAsFixed(2)}, Densidad: ${(density*100).toStringAsFixed(1)}%, Score: ${finalScore.toStringAsFixed(3)}');
    
    return BallDetection(
      center: center,
      radius: radius,
      confidence: finalScore,
      source: "color",
    );
  }

  @override
  void dispose() {
    // Desuscribirse de las actualizaciones del sensor
    _bluetoothViewModel.removeListener(_handleSensorUpdate);
    
    // Detener la grabación continua
    _stopContinuousRecording();
    
    // Liberar recursos del detector ML Kit
    _poseDetectionService.dispose();
    
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

  /// *** NUEVO MÉTODO PARA MEDIR FPS ***
  void _updateFpsCounter() {
    _processedFramesCount++;
    
    final now = DateTime.now();
    if (_fpsCounterStartTime == null) {
      _fpsCounterStartTime = now;
      return;
    }
    
    // Calcular FPS cada 30 frames procesados
    if (_processedFramesCount % 30 == 0) {
      final elapsed = now.difference(_fpsCounterStartTime!).inMilliseconds;
      if (elapsed > 0) {
        _currentDetectionFps = (30 * 1000) / elapsed;
        debugPrint('📊 FPS de Detección: ${_currentDetectionFps.toStringAsFixed(1)}');
      }
      _fpsCounterStartTime = now;
    }
  }

  /// *** NUEVO MÉTODO PARA OBTENER ESTADÍSTICAS COMPLETAS ***
  String getPerformanceStats() {
    final now = DateTime.now();
    final info = StringBuffer();
    info.writeln('=== ESTADÍSTICAS DE RENDIMIENTO ===');
    info.writeln('FPS de Detección: ${_currentDetectionFps.toStringAsFixed(1)}');
    info.writeln('Target FPS: $_targetFps');
    info.writeln('Frames Procesados: $_processedFramesCount');
    info.writeln('Detecciones Totales: $_totalDetectionsCount');
    
    if (_lastDetectionTime != null) {
      final timeSinceLastDetection = now.difference(_lastDetectionTime!).inSeconds;
      info.writeln('Última Detección: hace ${timeSinceLastDetection}s');
    }
    
    info.writeln('Detección Habilitada: $isDetectionEnabled');
    info.writeln('Procesando Frame: $isProcessingFrame');
    info.writeln('Buffer de Detecciones: ${_detectionBuffer.length}');
    
    return info.toString();
  }

  /// *** NUEVOS MÉTODOS PARA CONTROL DE DETECCIÓN ***
  
  /// Cambiar tipo de detección
  void toggleDetectionType() {
    if (_useMLKitAnalysis) {
      _useColorDetectionFallback = !_useColorDetectionFallback;
      
      final detectionType = _useColorDetectionFallback ? "Color (Fallback)" : "ML Kit";
      debugPrint('🔄 Tipo de detección cambiado a: $detectionType');
      
      notifyListeners();
    } else {
      debugPrint('⚠️ ML Kit no disponible, usando solo detección por color');
    }
  }
  
  /// Forzar uso solo de detección por color
  void forceColorDetection() {
    _useColorDetectionFallback = true;
    debugPrint('🎨 Forzando detección por color');
    notifyListeners();
  }
  
  /// Forzar uso solo de ML Kit (si está disponible)
  void forceMLKitDetection() {
    if (_useMLKitAnalysis) {
      _useColorDetectionFallback = false;
      debugPrint('🤖 Forzando detección ML Kit');
    } else {
      debugPrint('❌ ML Kit no disponible');
    }
    notifyListeners();
  }
  
  /// Obtener tipo de detección actual
  String getCurrentDetectionType() {
    if (_useMLKitAnalysis) {
      return _useColorDetectionFallback ? "Color (Fallback)" : "ML Kit";
    } else {
      return "Color";
    }
  }
  
  /// Obtener información del detector
  String getDetectorInfo() {
    final info = StringBuffer();
    info.writeln('=== INFORMACIÓN DEL DETECTOR ===');
    info.writeln('ML Kit Disponible: $_useMLKitAnalysis');
    info.writeln('Usando Fallback Color: $_useColorDetectionFallback');
    info.writeln('Tipo Actual: ${getCurrentDetectionType()}');
    
    if (_poseDetectionService.isInitialized) {
      info.writeln('Detector Inicializado: SÍ');
      info.writeln('Estado: Funcionando');
    } else {
      info.writeln('Detector Inicializado: NO');
    }
    
    return info.toString();
  }

  // *** MÉTODOS DE CONFIGURACIÓN PARA DIFERENTES TIPOS DE DETECCIÓN ***

  /// Habilitar detección ML Kit (método principal)
  void enableMLKitDetection() {
    _useMLKitAnalysis = true;
    debugPrint('🤖 ML Kit habilitado como método principal');
    
    // Verificar estado del backend
    _checkBackendHealth();
    
    notifyListeners();
  }

  /// Deshabilitar detección ML Kit
  void disableMLKitDetection() {
    _useMLKitAnalysis = false;
    debugPrint('🤖 ML Kit deshabilitado');
    notifyListeners();
  }

  /// Habilitar detección por color (fallback)
  void enableColorDetection() {
    _useColorDetectionFallback = true;
    _useMLKitAnalysis = false;
    debugPrint('🎨 Detección por color habilitada como método principal');
    notifyListeners();
  }

  /// Deshabilitar toda detección visual (solo Arduino)
  void disableVisualDetection() {
    _useMLKitAnalysis = false;
    _useColorDetectionFallback = false;
    isDetectionEnabled = false;
    debugPrint('📡 Solo detección Arduino habilitada');
    notifyListeners();
  }

  /// Configurar método híbrido con fallbacks
  void enableHybridDetection() {
    _useMLKitAnalysis = true;
    _useColorDetectionFallback = true;
    debugPrint('🔄 Detección híbrida habilitada (ML Kit -> Color)');
    
    // Verificar disponibilidad del backend
    _checkBackendHealth();
    
    notifyListeners();
  }

  /// Obtener estado actual de los métodos de detección
  Map<String, bool> getDetectionMethodsStatus() {
    return {
      'ml_kit': _useMLKitAnalysis && _poseDetectionService.isInitialized,
      'color': _useColorDetectionFallback,
      'arduino': true, // Siempre disponible via Bluetooth
      'backend_healthy': _backendHealthy,
    };
  }

  /// Obtener método de detección actual activo
  String getCurrentActiveMethod() {
    if (_useMLKitAnalysis && _poseDetectionService.isInitialized) {
      return 'ML Kit';
    } else if (_useColorDetectionFallback) {
      return 'Detección Color';
    } else {
      return 'Solo Arduino';
    }
  }

  /// Restablecer configuración a valores por defecto
  void resetDetectionConfiguration() {
    // Configuración híbrida por defecto
    _useMLKitAnalysis = true;
    _useColorDetectionFallback = true;
    isDetectionEnabled = true;
    
    debugPrint('🔄 Configuración de detección restablecida a valores por defecto');
    
    // Verificar backend
    _checkBackendHealth();
    
    notifyListeners();
  }

  /// Activar debug visual avanzado para ver detecciones
  void enableAdvancedVisualDebug() {
    debugPrint('🔍 Debug visual avanzado activado');
    notifyListeners();
  }

  /// Método público para inicializar la cámara
  Future<void> initializeCamera() async {
    // Evitar múltiples inicializaciones concurrentes
    if (_isInitializing) {
      debugPrint('⚠️ Inicialización ya en progreso - ignorando llamada');
      return;
    }
    
    if (isInitialized) {
      debugPrint('⚠️ Cámara ya inicializada - ignorando llamada');
      return;
    }
    
    // Posponer la inicialización para evitar setState durante build
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeCamera();
    });
  }

  /// Conversión de imagen ULTRA optimizada (máxima velocidad)
  static img.Image? _convertCameraImageToImageUltraFast(CameraImage cameraImage) {
    try {
      // Procesar solo a 1/4 de resolución para máxima velocidad
      final width = cameraImage.width ~/ 4;
      final height = cameraImage.height ~/ 4;
      
      if (Platform.isAndroid) {
        // Android YUV - versión ultra-simplificada
        final yuvImage = img.Image(width: width, height: height);
        final yBuffer = cameraImage.planes[0].bytes;
        final yRowStride = cameraImage.planes[0].bytesPerRow;
        
        // Procesar cada 4 píxeles para máxima velocidad (muestreo muy agresivo)
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final origH = h * 4;
            final origW = w * 4;
            final yIndex = origH * yRowStride + origW;
            
            if (yIndex < yBuffer.length) {
              final y = yBuffer[yIndex];
              // Solo usar luminancia, ignorar UV para velocidad
              yuvImage.setPixelRgba(w, h, y, y, y, 255);
            }
          }
        }
        return yuvImage;
      } else {
        // iOS BGRA - versión ultra-simplificada
        final bgra = img.Image(width: width, height: height);
        final buffer = cameraImage.planes[0].bytes;
        final rowStride = cameraImage.planes[0].bytesPerRow;
        
        // Procesar cada 4 píxeles
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final origH = h * 4;
            final origW = w * 4;
            final index = origH * rowStride + origW * 4;
            
            if (index + 3 < buffer.length) {
              final b = buffer[index];
              final g = buffer[index + 1];
              final r = buffer[index + 2];
              bgra.setPixelRgba(w, h, r, g, b, 255);
            }
          }
        }
        return bgra;
      }
    } catch (e) {
      debugPrint('Error conversión ultra-rápida: $e');
      return null;
    }
  }

  /// Detección de basketball ULTRA simplificada (solo buscar naranjas)
  static BallDetection? _detectBasketballUltraFast(img.Image? image) {
    if (image == null) return null;
    
    final width = image.width;
    final height = image.height;
    
    // Solo buscar píxeles que sean claramente naranjas
    int orangePixels = 0;
    double sumX = 0, sumY = 0;
    
    // Muestreo muy agresivo - solo cada 2 píxeles
    for (int y = 0; y < height; y += 2) {
      for (int x = 0; x < width; x += 2) {
        final pixel = image.getPixelSafe(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Detección ultra-simple: solo naranja brillante
        if (r > 120 && g > 60 && g < 120 && b < 80 && r > g && g > b) {
          orangePixels++;
          sumX += x * 4; // Escalar de vuelta a resolución original
          sumY += y * 4;
        }
      }
    }
    
    // Si hay suficientes píxeles naranjas, crear detección
    if (orangePixels >= 5) { // Muy permisivo
      final centerX = sumX / orangePixels;
      final centerY = sumY / orangePixels;
      final radius = orangePixels / 3.0; // Radio estimado simple
      
      return BallDetection(
        center: Offset(centerX, centerY),
        radius: radius,
        confidence: (orangePixels / 50.0).clamp(0.0, 1.0), // Confianza basada en cantidad
        source: "ultra_fast_color",
      );
    }
    
    return null;
  }

  /// Procesar ML Kit en hilo separado (función estática para compute)
  static Future<BasketballAnalysis?> _processMLKitDetection(CameraImage image) async {
    try {
      // Crear instancia del servicio ML Kit
      final poseService = PoseDetectionService();
      
      // Solo procesar si está inicializado
      if (!poseService.isInitialized) {
        return null;
      }
      
      // Analizar frame con ML Kit
      return await poseService.analyzeBasketballFrame(image);
    } catch (e) {
      debugPrint('❌ Error en procesamiento ML Kit: $e');
      return null;
    }
  }

  /// Analizar trayectoria de la pelota para detectar tiros fallidos
  void _analyzeTrajectoryForMissedShots(BallDetection ball) {
    final now = DateTime.now();
    
    // Agregar pelota a la trayectoria
    _ballTrajectory.add(ball);
    _lastBallDetectionTime = now;
    
    // Mantener solo los últimos 15 puntos para análisis
    if (_ballTrajectory.length > 15) {
      _ballTrajectory.removeAt(0);
    }
    
    // Analizar movimiento vertical
    final currentHeight = ball.center.dy;
    
    if (_ballTrajectory.length >= 2) {
      final heightDifference = _lastBallHeight - currentHeight; // Positivo = subiendo
      
      // Detectar movimiento ascendente (posible inicio de tiro)
      if (heightDifference > HEIGHT_THRESHOLD) {
        _consecutiveAscendingFrames++;
        _consecutiveDescendingFrames = 0;
        
        // ¿Es un posible tiro?
        if (_consecutiveAscendingFrames >= SHOT_DETECTION_THRESHOLD && !_isPotentialShot) {
          _isPotentialShot = true;
          debugPrint('🏀 POSIBLE TIRO DETECTADO - Pelota subiendo por ${_consecutiveAscendingFrames} frames');
        }
      }
      // Detectar movimiento descendente
      else if (heightDifference < -HEIGHT_THRESHOLD) {
        _consecutiveDescendingFrames++;
        _consecutiveAscendingFrames = 0;
        
        // ¿Es un fallo? (estaba subiendo, ahora baja sin acierto del Arduino)
        if (_isPotentialShot && _consecutiveDescendingFrames >= MISS_DETECTION_THRESHOLD) {
          // Verificar que no hay acierto reciente del Arduino
          if (!_bluetoothViewModel.shotDetected) {
            _isPotentialShot = false;
            debugPrint('🚫 TIRO FALLIDO DETECTADO - Pelota bajando por ${_consecutiveDescendingFrames} frames sin acierto del Arduino');
            _handleShotDetected(false, ShotDetectionType.camera); // Registrar como fallo
          }
        }
      }
      // Movimiento horizontal o pequeño (reset counters)
      else {
        if (_consecutiveAscendingFrames > 0) _consecutiveAscendingFrames--;
        if (_consecutiveDescendingFrames > 0) _consecutiveDescendingFrames--;
      }
    }
    
    _lastBallHeight = currentHeight;
    
    // Reset si no hay detección por mucho tiempo
    if (_lastBallDetectionTime != null && 
        now.difference(_lastBallDetectionTime!) > Duration(seconds: 3)) {
      _resetTrajectoryTracking();
    }
  }
  
  /// Resetear tracking de trayectoria
  void _resetTrajectoryTracking() {
    _ballTrajectory.clear();
    _isPotentialShot = false;
    _consecutiveAscendingFrames = 0;
    _consecutiveDescendingFrames = 0;
    _lastBallHeight = 0.0;
    debugPrint('🔄 Reset trajectory tracking');
  }

  void safeNotifyListeners() {
    try {
      if (hasListeners) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ Error en notifyListeners: $e');
    }
  }

  // *** GETTERS PARA DEBUG ***
  String get debugInfo {
    final now = DateTime.now();
    final timeSinceLastDetection = _lastDetectionTime != null 
        ? now.difference(_lastDetectionTime!).inMilliseconds 
        : -1;
    
    return """
    🔍 DEBUG INFO:
    • Frames procesados: $_debugFrameCount
    • Detecciones totales: $_totalDetectionsCount
    • FPS detección: ${_currentDetectionFps.toStringAsFixed(1)}
    • Última detección: ${timeSinceLastDetection}ms atrás
    • detectedBall: ${detectedBall != null ? 'SÍ' : 'NO'}
    • Método actual: $_currentDetectionMethod
    • ML Kit inicializado: ${_poseDetectionService.isInitialized}
    • Color fallback: $_useColorDetectionFallback
    • Detección habilitada: $isDetectionEnabled
    • Stream activo: ${cameraController?.value.isStreamingImages ?? false}
    """;
  }
  
  bool get isDebugMode => _debugMode;
  
  void toggleDebugMode() {
    _debugMode = !_debugMode;
    safeNotifyListeners();
  }
}

class _ConnectedComponent {
  final List<PixelPoint> pixels = [];
}