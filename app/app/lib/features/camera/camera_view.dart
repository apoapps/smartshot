import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'camera_view_model.dart';
import 'package:app/features/shared/watch/watch_view_model.dart';

class CameraView extends StatefulWidget {
  final bool isBackground;
  final double backgroundOpacity;
  
  const CameraView({
    super.key,
    this.isBackground = false,
    this.backgroundOpacity = 0.3,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Animación para el indicador de detección
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.repeat(reverse: true);

    // Inicializar cámara
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cameraVM = Provider.of<CameraViewModel>(context, listen: false);
      cameraVM.initialize();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CameraViewModel>(
      builder: (context, cameraVM, child) {
        if (cameraVM.isInitializing) {
          return _buildLoadingView();
        }

        if (cameraVM.errorMessage != null) {
          return _buildErrorView(cameraVM.errorMessage!);
        }

        if (!cameraVM.isInitialized || cameraVM.cameraController == null) {
          return _buildLoadingView();
        }

        if (widget.isBackground) {
          return _buildBackgroundCameraView(cameraVM);
        }

        return _buildCameraView(cameraVM);
      },
    );
  }

  Widget _buildLoadingView() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Inicializando cámara y ML Kit...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Error: $error',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final cameraVM = Provider.of<CameraViewModel>(
                  context, 
                  listen: false
                );
                cameraVM.initialize();
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundCameraView(CameraViewModel cameraVM) {
    // Usar FittedBox para preview + overlay de detección sin estirar
    final previewSize = cameraVM.cameraController!.value.previewSize;
    return Stack(
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: 1,
              height: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(cameraVM.cameraController!),
                  if (cameraVM.currentDetection != null)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => CustomPaint(
                        painter: BallDetectionOverlay(
                          detection: cameraVM.currentDetection!,
                          detectionHistory: cameraVM.detectionHistory,
                          cameraSize: previewSize ?? Size.zero,
                          screenSize: Size(previewSize?.width ?? 0, previewSize?.height ?? 0),
                          pulseValue: _pulseAnimation.value,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(1.0 - widget.backgroundOpacity),
          ),
        ),
      ],
    );
  }

  Widget _buildCameraView(CameraViewModel cameraVM) {
    final screenSize = MediaQuery.of(context).size;
    
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Vista de cámara
          Positioned(
            child: CameraPreview(cameraVM.cameraController!),
          ),

          // Overlay de detección de pelota
          if (cameraVM.currentDetection != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: BallDetectionOverlay(
                      detection: cameraVM.currentDetection!,
                      detectionHistory: cameraVM.detectionHistory,
                      cameraSize: cameraVM.cameraController!.value.previewSize ?? Size.zero,
                      screenSize: screenSize,
                      pulseValue: _pulseAnimation.value,
                    ),
                  );
                },
              ),
            ),

          // Panel de estado superior
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cameraVM.currentDetection != null 
                      ? Colors.green 
                      : Colors.grey,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    cameraVM.currentDetection != null 
                        ? Icons.sports_basketball 
                        : Icons.search,
                    color: cameraVM.currentDetection != null 
                        ? Colors.green 
                        : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cameraVM.currentDetection != null 
                              ? '🏀 PELOTA DETECTADA'
                              : '🔍 BUSCANDO PELOTA...',
                          style: TextStyle(
                            color: cameraVM.currentDetection != null 
                                ? Colors.green 
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (cameraVM.currentDetection != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Confianza: ${(cameraVM.currentDetection!.confidence * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Panel de métricas inferior
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric(
                    'FRAMES',
                    cameraVM.totalFrames.toString(),
                    Icons.videocam,
                    Colors.cyan,
                  ),
                  _buildMetric(
                    'DETECTADOS',
                    cameraVM.detectedFrames.toString(),
                    Icons.visibility,
                    Colors.green,
                  ),
                  _buildMetric(
                    'PRECISIÓN',
                    '${(cameraVM.detectionRate * 100).toStringAsFixed(1)}%',
                    Icons.percent,
                    Colors.orange,
                  ),
                  _buildMetric(
                    'HISTORIAL',
                    cameraVM.detectionHistory.length.toString(),
                    Icons.timeline,
                    Colors.purple,
                  ),
                ],
              ),
            ),
          ),

          // Overlay para mostrar encestado desde Apple Watch
          Consumer<WatchViewModel>(
            builder: (context, watchVM, child) {
              if (watchVM.shotDetected) {
                return Positioned.fill(
                  child: Stack(
                    children: [
                      // Overlay translúcido
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Center(
                          child: Text(
                            '¡Encestado!',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Botón para simular detección (solo en modo debug)
                      Positioned(
                        right: 20,
                        bottom: 100,
                        child: FloatingActionButton(
                          backgroundColor: Colors.orange,
                          onPressed: () => watchVM.simulateShotDetection(),
                          mini: true,
                          child: const Icon(Icons.sports_basketball),
                        ),
                      ),
                    ],
                  ),
                );
              }
              
              // Botón para simular detección (solo visible cuando no hay detección)
              return Positioned(
                right: 20,
                bottom: 100,
                child: FloatingActionButton(
                  backgroundColor: Colors.orange.withOpacity(0.7),
                  onPressed: () => watchVM.simulateShotDetection(),
                  mini: true,
                  child: const Icon(Icons.sports_basketball),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 8,
          ),
        ),
      ],
    );
  }
}

/// Painter personalizado para dibujar la detección de pelota
class BallDetectionOverlay extends CustomPainter {
  final BallDetection detection;
  final List<BallDetection> detectionHistory;
  final Size cameraSize;
  final Size screenSize;
  final double pulseValue;

  BallDetectionOverlay({
    required this.detection,
    required this.detectionHistory,
    required this.cameraSize,
    required this.screenSize,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    debugPrint('🐶 BallDetectionOverlay.paint: size=${size}, cameraSize=${cameraSize}, center=${detection.center}');
    final scaleX = size.width / cameraSize.width;
    final scaleY = size.height / cameraSize.height;

    // Dibujar trayectoria
    _drawTrajectory(canvas, scaleX, scaleY);
    
    // Dibujar detección actual
    _drawDetectionCircle(canvas, scaleX, scaleY);
    
    // Dibujar texto de posición
    _drawPositionText(canvas, scaleX, scaleY);
  }

  void _drawTrajectory(Canvas canvas, double scaleX, double scaleY) {
    if (detectionHistory.length < 2) return;

    final trajectoryPaint = Paint()
      ..color = Colors.cyan.withOpacity(0.7)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool isFirst = true;

    for (final detection in detectionHistory) {
      final center = Offset(
        detection.center.dx * scaleX,
        detection.center.dy * scaleY,
      );

      if (isFirst) {
        path.moveTo(center.dx, center.dy);
        isFirst = false;
      } else {
        path.lineTo(center.dx, center.dy);
      }

      // Dibujar puntos pequeños en la trayectoria
      canvas.drawCircle(
        center,
        3,
        Paint()..color = Colors.cyan.withOpacity(0.5),
      );
    }

    canvas.drawPath(path, trajectoryPaint);
  }

  void _drawDetectionCircle(Canvas canvas, double scaleX, double scaleY) {
    final center = Offset(
      detection.center.dx * scaleX,
      detection.center.dy * scaleY,
    );
    final radius = detection.radius * ((scaleX + scaleY) / 2);

    // Círculo de seguimiento con efecto de neón
    final paint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(center, radius, paint);

    // Punto central pulsante
    final pulsePaint = Paint()
      ..color = Colors.yellow.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 8 * pulseValue, pulsePaint);
  }

  void _drawPositionText(Canvas canvas, double scaleX, double scaleY) {
    final center = Offset(
      detection.center.dx * scaleX,
      detection.center.dy * scaleY,
    );
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Pelota detectada\n${(detection.confidence * 100).toStringAsFixed(1)}%',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 4,
              offset: const Offset(2, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy + 30),
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
} 