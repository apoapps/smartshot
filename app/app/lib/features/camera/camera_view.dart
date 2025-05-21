import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'camera_view_model.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inicializar la cámara cuando se crea el widget
    Provider.of<CameraViewModel>(context, listen: false).initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
                  child: CustomPaint(
                    painter: BallDetectionPainter(
                      ballDetection: cameraViewModel.detectedBall!,
                      previewSize: _getPreviewSize(cameraViewModel),
                      screenSize: MediaQuery.of(context).size,
                      isMirrored: cameraViewModel.cameraController!.description.lensDirection 
                          == CameraLensDirection.front,
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

class BallDetectionPainter extends CustomPainter {
  final BallDetection ballDetection;
  final Size previewSize;
  final Size screenSize;
  final bool isMirrored;

  BallDetectionPainter({
    required this.ballDetection,
    required this.previewSize,
    required this.screenSize,
    this.isMirrored = false,
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
    
    // Draw tracking lines
    final trackingPaint = Paint()
      ..color = Colors.green.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    // Horizontal line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      trackingPaint,
    );
    
    // Vertical line
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      trackingPaint,
    );
    
    // Draw outer glow
    final outerGlowPaint = Paint()
      ..color = Colors.green.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      scaledRadius * 1.3,
      outerGlowPaint,
    );
    
    // Draw detection circle
    final circlePaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      scaledRadius,
      circlePaint,
    );
    
    // Draw center point
    final centerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      8.0,
      centerPaint,
    );
    
    // Draw border around center point
    final centerBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      8.0,
      centerBorderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
