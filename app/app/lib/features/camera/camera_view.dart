import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'camera_view_model.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inicializar la cámara cuando se crea el widget
    Provider.of<CameraViewModel>(context, listen: false).initializeCamera();
    
    // Create animation controller for the tracking effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cameraVM = Provider.of<CameraViewModel>(context, listen: false);
    
    // Gestionar el ciclo de vida de la cámara
    if (cameraVM.cameraController == null || !cameraVM.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // Liberar recursos cuando la app está inactiva
      cameraVM.cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Reinicializar cuando la app vuelve a estar activa
      cameraVM.initializeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<CameraViewModel>(
        builder: (context, cameraViewModel, child) {
          if (cameraViewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (cameraViewModel.errorMessage != null) {
            return Center(child: Text(cameraViewModel.errorMessage!));
          }

          if (!cameraViewModel.isInitialized || cameraViewModel.cameraController == null) {
            return const Center(child: Text('Camera not initialized'));
          }

          return Stack(
            children: [
              // Vista de la cámara
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildCameraPreview(cameraViewModel),
              ),
              
              // Capa para dibujar la detección
              if (cameraViewModel.detectedBall != null)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: BallDetectionPainter(
                          ballDetection: cameraViewModel.detectedBall!,
                          previewSize: _getPreviewSize(cameraViewModel),
                          screenSize: MediaQuery.of(context).size,
                          isMirrored: cameraViewModel.cameraController!.description.lensDirection 
                              == CameraLensDirection.front,
                          pulseValue: _pulseController.value,
                        ),
                      );
                    },
                  ),
                ),
              
              // Target frame overlay for better visualization
              Positioned.fill(
                child: CustomPaint(
                  painter: TargetFramePainter(
                    screenSize: MediaQuery.of(context).size,
                    isActive: cameraViewModel.isDetectionEnabled,
                  ),
                ),
              ),
              
              // Panel de controles
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Botón para cambiar de cámara
                    // En macOS, podrías querer verificar si hay múltiples cámaras disponibles
                    if (cameraViewModel.cameras.length > 1)
                      FloatingActionButton(
                        onPressed: cameraViewModel.switchCamera,
                        heroTag: 'switchCamera',
                        backgroundColor: Colors.black54,
                        child: const Icon(Icons.flip_camera_ios, color: Colors.white),
                      ),
                    
                    // Botón para activar/desactivar detección
                    FloatingActionButton(
                      onPressed: cameraViewModel.toggleDetection,
                      heroTag: 'toggleDetection',
                      backgroundColor: cameraViewModel.isDetectionEnabled
                          ? Colors.green.withOpacity(0.7)
                          : Colors.red.withOpacity(0.7),
                      child: Icon(
                        cameraViewModel.isDetectionEnabled
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Indicador de detección
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black87.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      cameraViewModel.isDetectionEnabled ? 
                        'Ball Detection Active' : 
                        'Ball Detection Disabled',
                      style: TextStyle(
                        color: cameraViewModel.isDetectionEnabled ? 
                          Colors.green.shade300 : 
                          Colors.red.shade300,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Información de detección
              if (cameraViewModel.detectedBall != null)
                Positioned(
                  top: 60,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.green.withOpacity(0.7),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.sports_basketball,
                              color: Colors.orange.shade300,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Basketball Detected',
                              style: TextStyle(
                                color: Colors.green.shade300,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'Confidence',
                          '${(cameraViewModel.detectedBall!.confidence * 100).toStringAsFixed(1)}%',
                          icon: Icons.verified,
                        ),
                        _buildInfoRow(
                          'Size',
                          '${cameraViewModel.detectedBall!.radius.toStringAsFixed(1)} px',
                          icon: Icons.radio_button_checked,
                        ),
                        _buildInfoRow(
                          'Position',
                          '(${cameraViewModel.detectedBall!.center.dx.toInt()}, ${cameraViewModel.detectedBall!.center.dy.toInt()})',
                          icon: Icons.gps_fixed,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: Colors.white70,
              size: 16,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview(CameraViewModel viewModel) {
    // En macOS, es posible que necesitemos manejar la orientación de forma diferente
    try {
      return CameraPreview(viewModel.cameraController!);
    } catch (e) {
      return Center(
        child: Text('Camera preview error: $e', 
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
  }
  
  Size _getPreviewSize(CameraViewModel viewModel) {
    if (viewModel.cameraController == null || 
        viewModel.cameraController!.value.previewSize == null) {
      return const Size(16, 9); // Tamaño predeterminado si no hay información
    }
    
    return Size(
      viewModel.cameraController!.value.previewSize!.height,
      viewModel.cameraController!.value.previewSize!.width,
    );
  }
}

class TargetFramePainter extends CustomPainter {
  final Size screenSize;
  final bool isActive;
  
  TargetFramePainter({
    required this.screenSize,
    required this.isActive,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive) return;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.3;
    
    // Draw subtle target frame
    final framePaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Outer circle
    canvas.drawCircle(center, radius, framePaint);
    
    // Center crosshair
    final crosshairPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - 15, center.dy),
      Offset(center.dx + 15, center.dy),
      crosshairPaint,
    );
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - 15),
      Offset(center.dx, center.dy + 15),
      crosshairPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class BallDetectionPainter extends CustomPainter {
  final BallDetection ballDetection;
  final Size previewSize;
  final Size screenSize;
  final bool isMirrored;
  final double pulseValue;

  BallDetectionPainter({
    required this.ballDetection,
    required this.previewSize,
    required this.screenSize,
    this.isMirrored = false,
    this.pulseValue = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale factors to adapt coordinates
    final double scaleX = size.width / previewSize.width;
    final double scaleY = size.height / previewSize.height;
    
    // Calculate adjusted center
    double centerX = ballDetection.center.dx * scaleX;
    double centerY = ballDetection.center.dy * scaleY;
    
    // Adjust for front camera (mirror)
    if (isMirrored) {
      centerX = size.width - centerX;
    }
    
    // Calculate scaled radius
    final scaledRadius = ballDetection.radius * (scaleX + scaleY) / 2;
    
    // Draw tracking lines - animated opacity based on pulse value
    final trackingPaint = Paint()
      ..color = Colors.green.withOpacity(0.2 + (pulseValue * 0.4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Tracking box
    final boxSize = scaledRadius * 2.2;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: boxSize,
      height: boxSize,
    );
    
    // Draw tracking box with rounded corners
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(boxSize * 0.2)),
      trackingPaint,
    );
    
    // Draw corner marks for better tracking visualization
    final cornerPaint = Paint()
      ..color = Colors.green.withOpacity(0.3 + (pulseValue * 0.7))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final cornerSize = boxSize * 0.15;
    
    // Top-left corner
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + cornerSize, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left, rect.top + cornerSize),
      cornerPaint,
    );
    
    // Top-right corner
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right - cornerSize, rect.top),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.top + cornerSize),
      cornerPaint,
    );
    
    // Bottom-left corner
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + cornerSize, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left, rect.bottom - cornerSize),
      cornerPaint,
    );
    
    // Bottom-right corner
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right - cornerSize, rect.bottom),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right, rect.bottom - cornerSize),
      cornerPaint,
    );
    
    // Draw outer glow with animated size
    final pulseRadius = scaledRadius * (1.0 + pulseValue * 0.3);
    final outerGlowPaint = Paint()
      ..color = Colors.green.withOpacity(0.1 + (0.15 * pulseValue))
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      pulseRadius,
      outerGlowPaint,
    );
    
    // Draw detection circle
    final circlePaint = Paint()
      ..color = Colors.green.withOpacity(0.5 + (pulseValue * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      scaledRadius,
      circlePaint,
    );
    
    // Draw center point
    final centerPaint = Paint()
      ..color = Colors.red.withOpacity(0.7 + (pulseValue * 0.3))
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      5.0 + (pulseValue * 3.0), // Animated size
      centerPaint,
    );
    
    // Draw border around center point
    final centerBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5 + (pulseValue * 0.5))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      5.0 + (pulseValue * 3.0), // Match animated size
      centerBorderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
