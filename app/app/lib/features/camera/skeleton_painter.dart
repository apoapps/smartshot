import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import '../shared/analysis/pose_detection_service.dart';

class SkeletonPainter extends CustomPainter {
  final BasketballPoseAnalysis? poseAnalysis;
  final bool ballDetected;
  final Offset? ballPosition;
  final Size imageSize;

  SkeletonPainter({
    this.poseAnalysis,
    this.ballDetected = false,
    this.ballPosition,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (poseAnalysis?.landmarks == null) return;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    _drawSkeleton(canvas, poseAnalysis!.landmarks, scaleX, scaleY);

    if (ballDetected && ballPosition != null) {
      _drawBallDetectionIndicator(canvas, size, ballPosition!, scaleX, scaleY);
    }
  }

  void _drawSkeleton(Canvas canvas, Map<PoseLandmarkType, PoseLandmark?> landmarks, double scaleX, double scaleY) {
    final bonePaint = Paint()
      ..color = Colors.cyan.withOpacity(0.8)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;

    final shootingJointPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    // Conexiones del esqueleto usando palos
    final connections = [
      // Torso
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      
      // Brazos izquierdo
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftPinky],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftIndex],
      [PoseLandmarkType.leftWrist, PoseLandmarkType.leftThumb],
      
      // Brazo derecho (destacar si está en pose de tiro)
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightPinky],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightIndex],
      [PoseLandmarkType.rightWrist, PoseLandmarkType.rightThumb],
      
      // Piernas
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel],
      [PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex],
      
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel],
      [PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex],
      
      // Cabeza
      [PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner],
      [PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner],
      [PoseLandmarkType.leftEye, PoseLandmarkType.leftEar],
      [PoseLandmarkType.rightEye, PoseLandmarkType.rightEar],
    ];

    // Dibujar conexiones (palos del esqueleto)
    for (final connection in connections) {
      final point1 = landmarks[connection[0]];
      final point2 = landmarks[connection[1]];

      if (point1 != null && point2 != null) {
        final start = Offset(point1.x * scaleX, point1.y * scaleY);
        final end = Offset(point2.x * scaleX, point2.y * scaleY);
        
        // Usar color especial para brazo derecho si está en pose de tiro
        Paint currentPaint = bonePaint;
        if (poseAnalysis!.isShootingPose && 
            (connection.contains(PoseLandmarkType.rightShoulder) ||
             connection.contains(PoseLandmarkType.rightElbow) ||
             connection.contains(PoseLandmarkType.rightWrist))) {
          currentPaint = Paint()
            ..color = Colors.orange.withOpacity(0.9)
            ..strokeWidth = 5.0
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
        }
        
        canvas.drawLine(start, end, currentPaint);
      }
    }

    // Dibujar articulaciones (puntos)
    for (final entry in landmarks.entries) {
      final landmark = entry.value;
      if (landmark != null) {
        final point = Offset(landmark.x * scaleX, landmark.y * scaleY);
        
        // Usar color especial para articulaciones del brazo de tiro
        Paint currentJointPaint = jointPaint;
        if (poseAnalysis!.isShootingPose && 
            (entry.key == PoseLandmarkType.rightShoulder ||
             entry.key == PoseLandmarkType.rightElbow ||
             entry.key == PoseLandmarkType.rightWrist)) {
          currentJointPaint = shootingJointPaint;
        }
        
        canvas.drawCircle(point, 6, currentJointPaint);
        
        // Borde blanco para mejor visibilidad
        canvas.drawCircle(point, 6, Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
      }
    }

    // Indicador de pose de tiro
    if (poseAnalysis!.isShootingPose) {
      _drawShootingIndicator(canvas, landmarks, scaleX, scaleY);
    }
  }

  void _drawShootingIndicator(Canvas canvas, Map<PoseLandmarkType, PoseLandmark?> landmarks, double scaleX, double scaleY) {
    final rightWrist = landmarks[PoseLandmarkType.rightWrist];
    if (rightWrist != null) {
      final shootingPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      final center = Offset(rightWrist.x * scaleX, rightWrist.y * scaleY);
      
      // Círculo animado alrededor de la muñeca
      canvas.drawCircle(center, 20, shootingPaint);
      canvas.drawCircle(center, 25, Paint()
        ..color = Colors.orange.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0);

      // Texto indicador
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'POSE DE TIRO',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                offset: Offset(1.0, 1.0),
                blurRadius: 2.0,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, center.dy - 50),
      );
    }
  }

  void _drawBallDetectionIndicator(Canvas canvas, Size size, Offset ballPos, double scaleX, double scaleY) {
    final indicatorPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final ballCenter = Offset(ballPos.dx, ballPos.dy);
    
    // Círculo de detección de pelota más prominente
    canvas.drawCircle(ballCenter, 12, indicatorPaint);
    canvas.drawCircle(ballCenter, 12, borderPaint);

    // Indicador de texto en la parte superior
    final rect = Rect.fromLTWH(size.width / 2 - 80, 50, 160, 35);
    final backgroundPaint = Paint()
      ..color = Colors.green.withOpacity(0.9);

    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(18)), backgroundPaint);

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🏀 PELOTA DETECTADA',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(rect.left + (rect.width - textPainter.width) / 2, rect.top + 10),
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
} 