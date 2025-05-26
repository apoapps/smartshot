import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'camera_view_model.dart';

/// Painter personalizado para dibujar análisis de trayectoria de tiro
class TrajectoryPainter extends CustomPainter {
  final List<TrajectoryPoint> trajectoryPoints;
  final ShotAnalysis? shotAnalysis;
  final BasketZone? basketZone;
  final BallDetection? currentBall;
  final ShotPhase shotPhase;
  final Size imageSize;
  final bool showPrediction;
  final bool showTrajectory;
  final bool showBasketZone;

  TrajectoryPainter({
    required this.trajectoryPoints,
    this.shotAnalysis,
    this.basketZone,
    this.currentBall,
    required this.shotPhase,
    required this.imageSize,
    this.showPrediction = true,
    this.showTrajectory = true,
    this.showBasketZone = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Calcular factor de escala para adaptar coordenadas de imagen a pantalla
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    // 1. Dibujar zona de canasta
    if (showBasketZone && basketZone != null) {
      _drawBasketZone(canvas, basketZone!, scaleX, scaleY);
    }

    // 2. Dibujar trayectoria histórica
    if (showTrajectory && trajectoryPoints.isNotEmpty) {
      _drawTrajectoryPath(canvas, trajectoryPoints, scaleX, scaleY);
    }

    // 3. Dibujar predicción de trayectoria
    if (showPrediction && shotAnalysis != null) {
      _drawTrajectoryPrediction(canvas, shotAnalysis!, scaleX, scaleY);
    }

    // 4. Dibujar pelota actual
    if (currentBall != null) {
      _drawCurrentBall(canvas, currentBall!, scaleX, scaleY);
    }

    // 5. Dibujar información de análisis
    if (shotAnalysis != null) {
      _drawAnalysisInfo(canvas, size, shotAnalysis!);
    }

    // 6. Dibujar indicador de fase del tiro
    _drawShotPhaseIndicator(canvas, size, shotPhase);
  }

  /// Dibujar zona de la canasta
  void _drawBasketZone(Canvas canvas, BasketZone zone, double scaleX, double scaleY) {
    final center = Offset(
      zone.center.dx * scaleX,
      zone.center.dy * scaleY,
    );
    final radius = zone.radius * min(scaleX, scaleY);

    // Círculo principal de la zona de canasta
    final zonePaint = Paint()
      ..color = Colors.orange.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, zonePaint);

    // Borde de la zona
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, borderPaint);

    // Aro de la canasta (círculo más pequeño)
    final rimPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius * 0.3, rimPaint);

    // Etiqueta
    final labelPainter = TextPainter(
      text: TextSpan(
        text: 'CANASTA',
        style: TextStyle(
          color: Colors.orange,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + radius + 5),
    );
  }

  /// Dibujar trayectoria histórica con degradado de color
  void _drawTrajectoryPath(Canvas canvas, List<TrajectoryPoint> points, double scaleX, double scaleY) {
    if (points.length < 2) return;

    // Convertir puntos a coordenadas de pantalla
    final screenPoints = points.map((point) => Offset(
      point.position.dx * scaleX,
      point.position.dy * scaleY,
    )).toList();

    // Dibujar línea de trayectoria con degradado
    for (int i = 0; i < screenPoints.length - 1; i++) {
      final progress = i / (screenPoints.length - 1);
      final opacity = lerpDouble(0.3, 1.0, progress) ?? 1.0;
      final thickness = lerpDouble(1.0, 4.0, progress) ?? 2.0;

      final paint = Paint()
        ..color = Colors.blue.withOpacity(opacity)
        ..strokeWidth = thickness
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(screenPoints[i], screenPoints[i + 1], paint);
    }

    // Dibujar puntos de la trayectoria
    for (int i = 0; i < screenPoints.length; i++) {
      final progress = i / (screenPoints.length - 1);
      final opacity = lerpDouble(0.5, 1.0, progress) ?? 1.0;
      final size = lerpDouble(2.0, 6.0, progress) ?? 4.0;

      final pointPaint = Paint()
        ..color = _getVelocityColor(points[i].velocity).withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(screenPoints[i], size, pointPaint);
    }
  }

  /// Dibujar predicción de trayectoria usando física
  void _drawTrajectoryPrediction(Canvas canvas, ShotAnalysis analysis, double scaleX, double scaleY) {
    if (analysis.predictedLandingPoint == null) return;

    final releasePoint = Offset(
      analysis.releasePoint.dx * scaleX,
      analysis.releasePoint.dy * scaleY,
    );
    
    final landingPoint = Offset(
      analysis.predictedLandingPoint!.dx * scaleX,
      analysis.predictedLandingPoint!.dy * scaleY,
    );

    // Generar curva parabólica de predicción
    final predictionPoints = _generateParabolicCurve(
      releasePoint,
      landingPoint,
      analysis.releaseAngle,
    );

    // Dibujar curva de predicción
    if (predictionPoints.length > 1) {
      final path = Path();
      path.moveTo(predictionPoints.first.dx, predictionPoints.first.dy);
      
      for (int i = 1; i < predictionPoints.length; i++) {
        path.lineTo(predictionPoints[i].dx, predictionPoints[i].dy);
      }

      final predictionPaint = Paint()
        ..color = analysis.isPredictedMake ? Colors.green : Colors.red
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Añadir efecto de línea punteada
      _drawDashedPath(canvas, path, predictionPaint, dashLength: 10.0);
    }

    // Dibujar punto de aterrizaje predicho
    final landingPaint = Paint()
      ..color = analysis.isPredictedMake ? Colors.green : Colors.red
      ..style = PaintingStyle.fill;

    canvas.drawCircle(landingPoint, 8, landingPaint);

    // Dibujar X o ✓ en el punto de aterrizaje
    final symbolPainter = TextPainter(
      text: TextSpan(
        text: analysis.isPredictedMake ? '✓' : '✗',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    symbolPainter.layout();
    symbolPainter.paint(
      canvas,
      Offset(
        landingPoint.dx - symbolPainter.width / 2,
        landingPoint.dy - symbolPainter.height / 2,
      ),
    );
  }

  /// Dibujar pelota actual con efectos
  void _drawCurrentBall(Canvas canvas, BallDetection ball, double scaleX, double scaleY) {
    final center = Offset(
      ball.center.dx * scaleX,
      ball.center.dy * scaleY,
    );
    final radius = ball.radius * min(scaleX, scaleY);

    // Círculo principal
    final ballPaint = Paint()
      ..color = Colors.orange.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, ballPaint);

    // Borde
    final borderPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, radius, borderPaint);

    // Punto central
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 3, centerPaint);

    // Indicador de confianza
    final confidenceText = '${(ball.confidence * 100).toStringAsFixed(0)}%';
    final confidencePainter = TextPainter(
      text: TextSpan(
        text: confidenceText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Colors.black,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    confidencePainter.layout();
    confidencePainter.paint(
      canvas,
      Offset(
        center.dx - confidencePainter.width / 2,
        center.dy + radius + 5,
      ),
    );
  }

  /// Dibujar información de análisis en tiempo real
  void _drawAnalysisInfo(Canvas canvas, Size size, ShotAnalysis analysis) {
    final infoText = [
      'Ángulo: ${analysis.releaseAngle.toStringAsFixed(1)}°',
      'Velocidad: ${analysis.releaseVelocity.toStringAsFixed(0)} px/s',
      'Predicción: ${analysis.isPredictedMake ? "ACIERTO" : "FALLO"}',
      'Confianza: ${(analysis.confidence * 100).toStringAsFixed(0)}%',
    ];

    const padding = 16.0;
    const lineHeight = 20.0;
    final backgroundHeight = infoText.length * lineHeight + padding * 2;

    // Fondo semitransparente
    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.7);

    final backgroundRect = Rect.fromLTWH(
      padding,
      size.height - backgroundHeight - padding,
      200,
      backgroundHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, Radius.circular(8)),
      backgroundPaint,
    );

    // Texto de información
    for (int i = 0; i < infoText.length; i++) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: infoText[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          padding + 8,
          size.height - backgroundHeight - padding + 8 + i * lineHeight,
        ),
      );
    }
  }

  /// Dibujar indicador de fase del tiro
  void _drawShotPhaseIndicator(Canvas canvas, Size size, ShotPhase phase) {
    final phaseText = _getShotPhaseText(phase);
    final phaseColor = _getShotPhaseColor(phase);

    final phasePainter = TextPainter(
      text: TextSpan(
        text: phaseText,
        style: TextStyle(
          color: phaseColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 3,
              color: Colors.black,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    phasePainter.layout();
    phasePainter.paint(
      canvas,
      Offset(
        size.width - phasePainter.width - 16,
        16,
      ),
    );
  }

  /// Obtener color basado en velocidad
  Color _getVelocityColor(double velocity) {
    if (velocity < 50) return Colors.green;
    if (velocity < 100) return Colors.yellow;
    if (velocity < 150) return Colors.orange;
    return Colors.red;
  }

  /// Generar curva parabólica para predicción
  List<Offset> _generateParabolicCurve(Offset start, Offset end, double angle) {
    final points = <Offset>[];
    const numPoints = 20;

    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;
      
      // Interpolación parabólica simple
      final x = start.dx + (end.dx - start.dx) * t;
      final y = start.dy + (end.dy - start.dy) * t + 
                sin(t * pi) * (end.dx - start.dx) * 0.2 * sin(angle * pi / 180);
      
      points.add(Offset(x, y));
    }

    return points;
  }

  /// Dibujar línea punteada
  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {double dashLength = 5.0}) {
    final pathMetrics = path.computeMetrics();
    
    for (final pathMetric in pathMetrics) {
      double distance = 0.0;
      bool drawDash = true;
      
      while (distance < pathMetric.length) {
        final remainingLength = pathMetric.length - distance;
        final segmentLength = min(dashLength, remainingLength);
        
        if (drawDash) {
          final extractedPath = pathMetric.extractPath(distance, distance + segmentLength);
          canvas.drawPath(extractedPath, paint);
        }
        
        distance += segmentLength;
        drawDash = !drawDash;
      }
    }
  }

  /// Obtener texto de fase del tiro
  String _getShotPhaseText(ShotPhase phase) {
    switch (phase) {
      case ShotPhase.noShot:
        return 'SIN TIRO';
      case ShotPhase.preparation:
        return 'PREPARACIÓN';
      case ShotPhase.release:
        return 'LANZAMIENTO';
      case ShotPhase.flight:
        return 'EN VUELO';
      case ShotPhase.landing:
        return 'ATERRIZAJE';
    }
  }

  /// Obtener color de fase del tiro
  Color _getShotPhaseColor(ShotPhase phase) {
    switch (phase) {
      case ShotPhase.noShot:
        return Colors.grey;
      case ShotPhase.preparation:
        return Colors.yellow;
      case ShotPhase.release:
        return Colors.orange;
      case ShotPhase.flight:
        return Colors.blue;
      case ShotPhase.landing:
        return Colors.green;
    }
  }

  @override
  bool shouldRepaint(TrajectoryPainter oldDelegate) {
    return trajectoryPoints != oldDelegate.trajectoryPoints ||
           shotAnalysis != oldDelegate.shotAnalysis ||
           basketZone != oldDelegate.basketZone ||
           currentBall != oldDelegate.currentBall ||
           shotPhase != oldDelegate.shotPhase;
  }
} 