import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// Modelos de datos para el análisis
class ShotDetection {
  final int frame;
  final double timestamp;
  final bool isMake;
  final double confidence;
  final double shotQuality;

  ShotDetection({
    required this.frame,
    required this.timestamp,
    required this.isMake,
    required this.confidence,
    required this.shotQuality,
  });

  factory ShotDetection.fromJson(Map<String, dynamic> json) {
    return ShotDetection(
      frame: json['frame'] ?? 0,
      timestamp: (json['timestamp'] ?? 0.0).toDouble(),
      isMake: json['is_make'] ?? false,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      shotQuality: (json['shot_quality'] ?? 0.0).toDouble(),
    );
  }
}

class AnalysisResult {
  final String analysisId;
  final String status;
  final List<ShotDetection> shotsDetected;
  final AnalysisSummary summary;

  AnalysisResult({
    required this.analysisId,
    required this.status,
    required this.shotsDetected,
    required this.summary,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    return AnalysisResult(
      analysisId: json['analysis_id'] ?? '',
      status: json['status'] ?? 'unknown',
      shotsDetected: (json['shots_detected'] as List<dynamic>?)
          ?.map((shot) => ShotDetection.fromJson(shot))
          .toList() ?? [],
      summary: AnalysisSummary.fromJson(json['summary'] ?? {}),
    );
  }
}

class AnalysisSummary {
  final int totalShots;
  final int makes;
  final int misses;
  final double avgShotQuality;

  AnalysisSummary({
    required this.totalShots,
    required this.makes,
    required this.misses,
    required this.avgShotQuality,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> json) {
    return AnalysisSummary(
      totalShots: json['total_shots'] ?? 0,
      makes: json['makes'] ?? 0,
      misses: json['misses'] ?? 0,
      avgShotQuality: (json['avg_shot_quality'] ?? 0.0).toDouble(),
    );
  }

  double get shootingPercentage => 
      totalShots > 0 ? (makes / totalShots) * 100 : 0.0;
}

class FrameAnalysis {
  final String analysisId;
  final double timestamp;
  final List<Detection> detections;
  final PoseData? poseData;
  final ShotAnalysis? shotAnalysis;

  FrameAnalysis({
    required this.analysisId,
    required this.timestamp,
    required this.detections,
    this.poseData,
    this.shotAnalysis,
  });

  factory FrameAnalysis.fromJson(Map<String, dynamic> json) {
    return FrameAnalysis(
      analysisId: json['analysis_id'] ?? '',
      timestamp: (json['timestamp'] ?? 0.0).toDouble(),
      detections: (json['detections'] as List<dynamic>?)
          ?.map((det) => Detection.fromJson(det))
          .toList() ?? [],
      poseData: json['pose_data'] != null 
          ? PoseData.fromJson(json['pose_data']) 
          : null,
      shotAnalysis: json['shot_analysis'] != null 
          ? ShotAnalysis.fromJson(json['shot_analysis']) 
          : null,
    );
  }
}

class Detection {
  final int classId;
  final String className;
  final double confidence;
  final BoundingBox bbox;
  final Point center;

  Detection({
    required this.classId,
    required this.className,
    required this.confidence,
    required this.bbox,
    required this.center,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      classId: json['class_id'] ?? 0,
      className: json['class_name'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      bbox: BoundingBox.fromJson(json['bbox'] ?? {}),
      center: Point.fromJson(json['center'] ?? {}),
    );
  }
}

class BoundingBox {
  final int x;
  final int y;
  final int width;
  final int height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
    );
  }
}

class Point {
  final int x;
  final int y;

  Point({
    required this.x,
    required this.y,
  });

  factory Point.fromJson(Map<String, dynamic> json) {
    return Point(
      x: json['x'] ?? 0,
      y: json['y'] ?? 0,
    );
  }
}

class PoseData {
  final bool hasPerson;
  final List<List<double>>? keypoints;
  final ShootingAngles? angles;

  PoseData({
    required this.hasPerson,
    this.keypoints,
    this.angles,
  });

  factory PoseData.fromJson(Map<String, dynamic> json) {
    return PoseData(
      hasPerson: json['has_person'] ?? false,
      keypoints: json['keypoints'] != null 
          ? (json['keypoints'] as List<dynamic>)
              .map((kp) => (kp as List<dynamic>)
                  .map((coord) => (coord as num).toDouble())
                  .toList())
              .toList()
          : null,
      angles: json['angles'] != null 
          ? ShootingAngles.fromJson(json['angles']) 
          : null,
    );
  }
}

class ShootingAngles {
  final double elbowAngle;
  final double kneeAngle;
  final double shootingFormScore;

  ShootingAngles({
    required this.elbowAngle,
    required this.kneeAngle,
    required this.shootingFormScore,
  });

  factory ShootingAngles.fromJson(Map<String, dynamic> json) {
    return ShootingAngles(
      elbowAngle: (json['elbow_angle'] ?? 0.0).toDouble(),
      kneeAngle: (json['knee_angle'] ?? 0.0).toDouble(),
      shootingFormScore: (json['shooting_form_score'] ?? 0.0).toDouble(),
    );
  }
}

class ShotAnalysis {
  final bool isShotAttempt;
  final bool isMake;
  final double confidence;
  final double shotQuality;

  ShotAnalysis({
    required this.isShotAttempt,
    required this.isMake,
    required this.confidence,
    required this.shotQuality,
  });

  factory ShotAnalysis.fromJson(Map<String, dynamic> json) {
    return ShotAnalysis(
      isShotAttempt: json['is_shot_attempt'] ?? false,
      isMake: json['is_make'] ?? false,
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      shotQuality: (json['shot_quality'] ?? 0.0).toDouble(),
    );
  }
}

/// Servicio principal para análisis de baloncesto
class BasketballAnalysisService {
  static const String baseUrl = 'http://localhost:5001';
  static const Duration timeoutDuration = Duration(seconds: 30);
  final Uuid _uuid = const Uuid();

  /// Verificar que el backend esté funcionando
  Future<bool> isBackendHealthy() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'healthy' && data['initialized'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('🔴 Backend health check failed: $e');
      return false;
    }
  }

  /// Analizar un frame individual
  Future<FrameAnalysis?> analyzeFrame(Uint8List imageBytes) async {
    try {
      // Convertir imagen a base64
      final base64Image = base64Encode(imageBytes);
      final analysisId = _uuid.v4();

      final response = await http.post(
        Uri.parse('$baseUrl/analyze_frame'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image': base64Image,
          'analysis_id': analysisId,
        }),
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] != null) {
          debugPrint('🔴 Frame analysis error: ${data['error']}');
          return null;
        }
        return FrameAnalysis.fromJson(data);
      } else {
        debugPrint('🔴 Frame analysis failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('🔴 Frame analysis exception: $e');
      return null;
    }
  }

  /// Analizar video completo (sube archivo y devuelve ID de análisis)
  Future<String?> analyzeVideo(File videoFile) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/analyze_video'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('video', videoFile.path),
      );

      final streamedResponse = await request.send().timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] != null) {
          debugPrint('🔴 Video analysis error: ${data['error']}');
          return null;
        }
        return data['analysis_id'];
      } else {
        debugPrint('🔴 Video analysis failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('🔴 Video analysis exception: $e');
      return null;
    }
  }

  /// Obtener resultado de análisis por ID
  Future<AnalysisResult?> getAnalysisResult(String analysisId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analysis_result/$analysisId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeoutDuration);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['error'] != null) {
          debugPrint('🔴 Analysis result error: ${data['error']}');
          return null;
        }
        return AnalysisResult.fromJson(data);
      } else {
        debugPrint('🔴 Get analysis result failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('🔴 Get analysis result exception: $e');
      return null;
    }
  }

  /// Polling para esperar resultado completo
  Future<AnalysisResult?> waitForAnalysisResult(
    String analysisId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration maxWaitTime = const Duration(minutes: 5),
  }) async {
    final startTime = DateTime.now();
    
    while (DateTime.now().difference(startTime) < maxWaitTime) {
      final result = await getAnalysisResult(analysisId);
      
      if (result != null) {
        if (result.status == 'completed') {
          return result;
        } else if (result.status == 'error') {
          debugPrint('🔴 Analysis failed for ID: $analysisId');
          return null;
        }
        // Status 'processing' -> continuar polling
      }
      
      await Future.delayed(pollInterval);
    }
    
    debugPrint('⏰ Analysis timeout for ID: $analysisId');
    return null;
  }
}

/// Singleton para acceso global
class AnalysisService {
  static final AnalysisService _instance = AnalysisService._internal();
  factory AnalysisService() => _instance;
  AnalysisService._internal();

  final BasketballAnalysisService _service = BasketballAnalysisService();

  /// Métodos delegados
  Future<bool> isHealthy() => _service.isBackendHealthy();
  Future<FrameAnalysis?> analyzeFrame(Uint8List imageBytes) => 
      _service.analyzeFrame(imageBytes);
  Future<String?> analyzeVideo(File videoFile) => 
      _service.analyzeVideo(videoFile);
  Future<AnalysisResult?> getAnalysisResult(String analysisId) => 
      _service.getAnalysisResult(analysisId);
  Future<AnalysisResult?> waitForAnalysisResult(String analysisId) => 
      _service.waitForAnalysisResult(analysisId);
} 