import 'dart:typed_data';
import 'dart:ui';
import 'dart:math' show atan2, pi;
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:camera/camera.dart';

/// Fases de un tiro de basketball
enum ShootingPhase {
  noShot,
  preparation,
  release,
  followThrough,
  completed
}

/// Resultado del análisis de pose de basketball
class BasketballPoseAnalysis {
  final bool isPersonDetected;
  final ShootingPhase shootingPhase;
  final double rightElbowAngle;
  final double leftElbowAngle;
  final double kneeFlexion;
  final double formScore;
  final String formFeedback;
  final double confidence;
  final Map<PoseLandmarkType, PoseLandmark?> landmarks;
  final bool isShootingPose;
  final Offset? ballReleasePoint;

  BasketballPoseAnalysis({
    required this.isPersonDetected,
    required this.shootingPhase,
    required this.rightElbowAngle,
    required this.leftElbowAngle,
    required this.kneeFlexion,
    required this.formScore,
    required this.formFeedback,
    required this.confidence,
    required this.landmarks,
    required this.isShootingPose,
    this.ballReleasePoint,
  });
}

/// Resultado de detección de pelota
class BallDetectionResult {
  final bool ballDetected;
  final Offset? ballPosition;
  final Size? ballSize;
  final double confidence;
  final bool ballInMotion;
  final Offset? velocity;

  BallDetectionResult({
    required this.ballDetected,
    this.ballPosition,
    this.ballSize,
    required this.confidence,
    required this.ballInMotion,
    this.velocity,
  });
}

/// Análisis completo combinando pose y pelota
class BasketballAnalysis {
  final BasketballPoseAnalysis? poseAnalysis;
  final BallDetectionResult ballDetection;
  final bool shotAttemptDetected;
  final bool ballReleasedFromHands;
  final double overallConfidence;

  BasketballAnalysis({
    this.poseAnalysis,
    required this.ballDetection,
    required this.shotAttemptDetected,
    required this.ballReleasedFromHands,
    required this.overallConfidence,
  });
}

/// Evaluación de la forma del tiro
class FormEvaluation {
  final double score;
  final String feedback;

  FormEvaluation({required this.score, required this.feedback});
}

/// Servicio principal para detección de basketball usando Google ML Kit
class PoseDetectionService {
  static final PoseDetectionService _instance = PoseDetectionService._internal();
  factory PoseDetectionService() => _instance;
  PoseDetectionService._internal();

  PoseDetector? _poseDetector;
  ObjectDetector? _objectDetector;
  bool _isInitialized = false;

  // Buffer para tracking de pelotas
  final List<Offset> _ballPositionHistory = [];
  Offset? _lastBallPosition;
  DateTime? _lastBallDetectionTime;

  /// Inicializar ambos detectores
  Future<bool> initialize() async {
    try {
      debugPrint('🔄 Inicializando ML Kit en plataforma: ${Platform.operatingSystem}');
      
      // Configurar detector de poses
      final poseOptions = PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode: PoseDetectionMode.stream,
      );
      _poseDetector = PoseDetector(options: poseOptions);

      // Configurar detector de objetos para pelotas deportivas
      final objectOptions = ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      );
      _objectDetector = ObjectDetector(options: objectOptions);

      _isInitialized = true;
      debugPrint('✅ ML Kit Basketball Detection inicializado en ${Platform.operatingSystem}');
      debugPrint('📱 Pose Detector: ${_poseDetector != null}');
      debugPrint('⚽ Object Detector: ${_objectDetector != null}');
      return true;
    } catch (e) {
      debugPrint('❌ Error inicializando Basketball Detection: $e');
      return false;
    }
  }

  /// Verificar si está inicializado
  bool get isInitialized => _isInitialized;

  /// Análisis completo de basketball en tiempo real
  Future<BasketballAnalysis?> analyzeBasketballFrame(CameraImage cameraImage) async {
    if (!_isInitialized || _poseDetector == null || _objectDetector == null) {
      debugPrint('❌ ML Kit no inicializado correctamente');
      return null;
    }

    try {
      debugPrint('🔍 Procesando frame ${cameraImage.width}x${cameraImage.height} formato: ${cameraImage.format.group}');
      
      return await compute(_processFrameInIsolate, {
        'cameraImage': cameraImage,
        'ballPositionHistory': _ballPositionHistory,
        'lastBallPosition': _lastBallPosition,
        'lastBallDetectionTime': _lastBallDetectionTime,
      });
    } catch (e) {
      debugPrint('❌ Error en análisis de basketball: $e');
      return null;
    }
  }

  static Future<BasketballAnalysis?> _processFrameInIsolate(Map<String, dynamic> params) async {
    final cameraImage = params['cameraImage'] as CameraImage;
    
    try {
      final inputImage = _convertCameraImage(cameraImage);
      if (inputImage == null) return null;

      final poseDetector = PoseDetector(options: PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode: PoseDetectionMode.stream,
      ));

      final objectDetector = ObjectDetector(options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ));

      final results = await Future.wait([
        _detectPose(inputImage, poseDetector),
        _detectBall(inputImage, objectDetector, params),
      ]);

      await poseDetector.close();
      await objectDetector.close();

      final poseAnalysis = results[0] as BasketballPoseAnalysis?;
      final ballDetection = results[1] as BallDetectionResult;

      final shotAttemptDetected = _analyzeShotAttempt(poseAnalysis, ballDetection);
      final ballReleasedFromHands = _analyzeBallRelease(poseAnalysis, ballDetection);
      final overallConfidence = _calculateOverallConfidence(poseAnalysis, ballDetection);

      return BasketballAnalysis(
        poseAnalysis: poseAnalysis,
        ballDetection: ballDetection,
        shotAttemptDetected: shotAttemptDetected,
        ballReleasedFromHands: ballReleasedFromHands,
        overallConfidence: overallConfidence,
      );
    } catch (e) {
      debugPrint('❌ Error en isolate: $e');
      return null;
    }
  }

  /// Detectar poses
  static Future<BasketballPoseAnalysis?> _detectPose(InputImage inputImage, PoseDetector poseDetector) async {
    try {
      debugPrint('🕺 Iniciando detección de poses...');
      final poses = await poseDetector.processImage(inputImage);
      
      debugPrint('📊 Poses detectadas: ${poses.length}');
      
      if (poses.isEmpty) {
        debugPrint('❌ No se detectaron poses');
        return null;
      }

      final pose = poses.first;
      debugPrint('✅ Pose detectada con ${pose.landmarks.length} landmarks');
      return _analyzeBasketballPose(pose);
    } catch (e) {
      debugPrint('❌ Error en detección de poses: $e');
      return null;
    }
  }

  /// Detectar pelota usando detección de objetos
  static Future<BallDetectionResult> _detectBall(InputImage inputImage, ObjectDetector objectDetector, Map<String, dynamic> params) async {
    try {
      debugPrint('⚽ Iniciando detección de objetos...');
      final objects = await objectDetector.processImage(inputImage);
      
      debugPrint('📦 Objetos detectados: ${objects.length}');
      
      // Buscar objetos que podrían ser una pelota deportiva
      for (final detectedObject in objects) {
        debugPrint('🔍 Objeto detectado con ${detectedObject.labels.length} etiquetas');
        for (final label in detectedObject.labels) {
          debugPrint('🏷️ Etiqueta: ${label.text} (confianza: ${label.confidence})');
          if (_isSportsObject(label.text)) {
            debugPrint('🏀 ¡Pelota deportiva encontrada!');
            return _createBallDetectionResult(detectedObject, label.confidence, params);
          }
        }
      }

      // Si no encuentra objetos clasificados, usar detección de forma circular
      debugPrint('🔄 Intentando detección por forma...');
      return _detectBallByShape(objects, params);
      
    } catch (e) {
      debugPrint('❌ Error en detección de pelota: $e');
      return BallDetectionResult(
        ballDetected: false,
        confidence: 0.0,
        ballInMotion: false,
      );
    }
  }

  /// Verificar si el objeto detectado es deportivo
  static bool _isSportsObject(String label) {
    final sportsLabels = ['sports ball', 'ball', 'basketball', 'sphere'];
    return sportsLabels.any((sports) => 
      label.toLowerCase().contains(sports.toLowerCase()));
  }

  /// Crear resultado de detección de pelota
  static BallDetectionResult _createBallDetectionResult(DetectedObject object, double confidence, Map<String, dynamic> params) {
    final rect = object.boundingBox;
    final center = Offset(
      rect.left + rect.width / 2,
      rect.top + rect.height / 2,
    );
    
    final ballPositionHistory = params['ballPositionHistory'] as List<Offset>;
    final lastBallPosition = params['lastBallPosition'] as Offset?;
    final lastBallDetectionTime = params['lastBallDetectionTime'] as DateTime?;
    
    Offset? velocity;
    bool ballInMotion = false;
    
    if (lastBallPosition != null && lastBallDetectionTime != null) {
      final timeDiff = DateTime.now().difference(lastBallDetectionTime).inMilliseconds;
      if (timeDiff > 0) {
        final dx = center.dx - lastBallPosition.dx;
        final dy = center.dy - lastBallPosition.dy;
        velocity = Offset(dx / timeDiff * 1000, dy / timeDiff * 1000);
        ballInMotion = velocity.distance > 10;
      }
    }

    return BallDetectionResult(
      ballDetected: true,
      ballPosition: center,
      ballSize: Size(rect.width, rect.height),
      confidence: confidence,
      ballInMotion: ballInMotion,
      velocity: velocity,
    );
  }

  /// Detectar pelota por forma cuando no hay clasificación
  static BallDetectionResult _detectBallByShape(List<DetectedObject> objects, Map<String, dynamic> params) {
    for (final object in objects) {
      final rect = object.boundingBox;
      final aspectRatio = rect.width / rect.height;
      
      // Buscar objetos aproximadamente circulares
      if (aspectRatio > 0.7 && aspectRatio < 1.3) {
        return _createBallDetectionResult(object, 0.6, params);
      }
    }

    return BallDetectionResult(
      ballDetected: false,
      confidence: 0.0,
      ballInMotion: false,
    );
  }

  /// Analizar pose específicamente para basketball
  static BasketballPoseAnalysis _analyzeBasketballPose(Pose pose) {
    final landmarks = pose.landmarks;
    
    // Puntos clave para análisis de tiro
    final rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final rightHip = landmarks[PoseLandmarkType.rightHip];
    final rightKnee = landmarks[PoseLandmarkType.rightKnee];

    // Calcular ángulos
    final rightElbowAngle = _calculateAngle(
      rightShoulder?.x ?? 0, rightShoulder?.y ?? 0,
      rightElbow?.x ?? 0, rightElbow?.y ?? 0,
      rightWrist?.x ?? 0, rightWrist?.y ?? 0,
    );

    final leftElbowAngle = _calculateAngle(
      leftShoulder?.x ?? 0, leftShoulder?.y ?? 0,
      leftElbow?.x ?? 0, leftElbow?.y ?? 0,
      leftWrist?.x ?? 0, leftWrist?.y ?? 0,
    );

    final rightKneeAngle = _calculateAngle(
      rightHip?.x ?? 0, rightHip?.y ?? 0,
      rightKnee?.x ?? 0, rightKnee?.y ?? 0,
      rightKnee?.x ?? 0, (rightKnee?.y ?? 0) + 100,
    );

    // Detectar fase del tiro
    final shootingPhase = _detectShootingPhase(
      rightWrist, leftWrist, rightElbow, leftElbow
    );

    // Evaluar si es pose de tiro
    final isShootingPose = _isShootingPose(
      rightElbow, rightWrist, leftElbow, leftWrist
    );

    // Calcular punto de liberación de pelota
    final ballReleasePoint = _calculateBallReleasePoint(
      rightWrist, leftWrist
    );

    // Evaluar forma del tiro
    final formEvaluation = _evaluateShootingForm(
      rightElbowAngle, leftElbowAngle, rightKneeAngle
    );

    // Calcular confianza general
    final confidence = landmarks.values
        .where((l) => l != null)
        .map((l) => l!.likelihood)
        .reduce((a, b) => a + b) / landmarks.length;

    return BasketballPoseAnalysis(
      isPersonDetected: true,
      shootingPhase: shootingPhase,
      rightElbowAngle: rightElbowAngle,
      leftElbowAngle: leftElbowAngle,
      kneeFlexion: rightKneeAngle,
      formScore: formEvaluation.score,
      formFeedback: formEvaluation.feedback,
      confidence: confidence,
      landmarks: landmarks,
      isShootingPose: isShootingPose,
      ballReleasePoint: ballReleasePoint,
    );
  }

  /// Detectar si es una pose de tiro
  static bool _isShootingPose(
    PoseLandmark? rightElbow,
    PoseLandmark? rightWrist,
    PoseLandmark? leftElbow,
    PoseLandmark? leftWrist,
  ) {
    if (rightElbow == null || rightWrist == null) return false;

    // La muñeca derecha debe estar elevada
    final rightArmElevated = rightWrist.y < rightElbow.y - 30;
    
    // El codo debe estar en posición adecuada
    final elbowPosition = rightElbow.y < rightWrist.y + 50;

    return rightArmElevated && elbowPosition;
  }

  /// Calcular punto de liberación de la pelota
  static Offset? _calculateBallReleasePoint(
    PoseLandmark? rightWrist,
    PoseLandmark? leftWrist,
  ) {
    if (rightWrist == null) return null;

    // Punto promedio entre ambas muñecas o solo la derecha
    if (leftWrist != null) {
      return Offset(
        (rightWrist.x + leftWrist.x) / 2,
        (rightWrist.y + leftWrist.y) / 2,
      );
    }

    return Offset(rightWrist.x, rightWrist.y);
  }

  /// Analizar si hay intento de tiro
  static bool _analyzeShotAttempt(
    BasketballPoseAnalysis? poseAnalysis,
    BallDetectionResult ballDetection,
  ) {
    if (poseAnalysis == null) return false;

    return poseAnalysis.isShootingPose && 
           (poseAnalysis.shootingPhase == ShootingPhase.release ||
            poseAnalysis.shootingPhase == ShootingPhase.followThrough);
  }

  /// Analizar si la pelota se liberó de las manos
  static bool _analyzeBallRelease(
    BasketballPoseAnalysis? poseAnalysis,
    BallDetectionResult ballDetection,
  ) {
    if (poseAnalysis == null || 
        poseAnalysis.ballReleasePoint == null ||
        !ballDetection.ballDetected ||
        ballDetection.ballPosition == null) {
      return false;
    }

    final releasePoint = poseAnalysis.ballReleasePoint!;
    final ballPosition = ballDetection.ballPosition!;

    // Calcular distancia entre manos y pelota
    final distance = (releasePoint - ballPosition).distance;

    // Si la pelota está lejos de las manos y en movimiento
    return distance > 50 && ballDetection.ballInMotion;
  }

  /// Calcular confianza general
  static double _calculateOverallConfidence(
    BasketballPoseAnalysis? poseAnalysis,
    BallDetectionResult ballDetection,
  ) {
    final poseConfidence = poseAnalysis?.confidence ?? 0.0;
    final ballConfidence = ballDetection.confidence;

    return (poseConfidence + ballConfidence) / 2;
  }

  /// Calcular ángulo entre tres puntos
  static double _calculateAngle(double x1, double y1, double x2, double y2, double x3, double y3) {
    final double angle1 = atan2(y1 - y2, x1 - x2);
    final double angle2 = atan2(y3 - y2, x3 - x2);
    double angle = (angle2 - angle1).abs();
    
    if (angle > pi) {
      angle = 2 * pi - angle;
    }
    
    return angle * 180 / pi;
  }

  /// Detectar fase del tiro
  static ShootingPhase _detectShootingPhase(
    PoseLandmark? rightWrist,
    PoseLandmark? leftWrist,
    PoseLandmark? rightElbow,
    PoseLandmark? leftElbow,
  ) {
    if (rightWrist == null || rightElbow == null) {
      return ShootingPhase.noShot;
    }

    final rightWristHeight = rightWrist.y;
    final rightElbowHeight = rightElbow.y;

    // Lógica de detección de fases
    if (rightWristHeight < rightElbowHeight - 40) {
      return ShootingPhase.release;
    } else if (rightWristHeight < rightElbowHeight - 20) {
      return ShootingPhase.preparation;
    } else if (rightWristHeight > rightElbowHeight + 20) {
      return ShootingPhase.followThrough;
    }

    return ShootingPhase.preparation;
  }

  /// Evaluar forma del tiro
  static FormEvaluation _evaluateShootingForm(
    double rightElbowAngle,
    double leftElbowAngle,
    double kneeFlexion,
  ) {
    double score = 0.0;
    List<String> feedback = [];

    // Evaluar ángulo del codo (ideal: 90°)
    if (rightElbowAngle >= 80 && rightElbowAngle <= 100) {
      score += 0.4;
      feedback.add("Excelente ángulo de codo");
    } else {
      feedback.add("Ajusta el ángulo del codo");
    }

    // Evaluar flexión de rodillas
    if (kneeFlexion >= 160 && kneeFlexion <= 180) {
      score += 0.3;
      feedback.add("Buena postura de piernas");
    } else {
      feedback.add("Flexiona más las rodillas");
    }

    // Evaluar simetría
    final asymmetry = (rightElbowAngle - leftElbowAngle).abs();
    if (asymmetry <= 20) {
      score += 0.3;
      feedback.add("Buena simetría");
    } else {
      feedback.add("Mejora la simetría del tiro");
    }

    return FormEvaluation(
      score: score,
      feedback: feedback.join(", "),
    );
  }

  /// Convertir CameraImage a InputImage
  static InputImage? _convertCameraImage(CameraImage cameraImage) {
    try {
      debugPrint('🖼️ Convirtiendo imagen: ${cameraImage.width}x${cameraImage.height}, formato: ${cameraImage.format.group}, planes: ${cameraImage.planes.length}');
      
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        cameraImage.width.toDouble(), 
        cameraImage.height.toDouble()
      );

      const InputImageRotation imageRotation = InputImageRotation.rotation0deg;
      
      // Usar formato correcto según la plataforma
      final InputImageFormat inputImageFormat = Platform.isIOS 
          ? InputImageFormat.bgra8888 
          : InputImageFormat.nv21;

      debugPrint('🔧 Formato ML Kit: $inputImageFormat, plataforma: ${Platform.operatingSystem}');

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );
      
      debugPrint('✅ InputImage creada exitosamente');
      return inputImage;
    } catch (e) {
      debugPrint('❌ Error convirtiendo imagen: $e');
      return null;
    }
  }

  /// Liberar recursos
  Future<void> dispose() async {
    await _poseDetector?.close();
    await _objectDetector?.close();
    _isInitialized = false;
  }
} 