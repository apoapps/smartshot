import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para SystemChrome
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'camera_view_model.dart';
import 'trajectory_painter.dart';

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
      backgroundColor: Colors.black,
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

          return _buildResponsiveCameraLayout(cameraViewModel);
        },
      ),
    );
  }

  Widget _buildResponsiveCameraLayout(CameraViewModel cameraViewModel) {
    final screenSize = MediaQuery.of(context).size;
    
    return Stack(
      children: [
        // *** CÁMARA FORZADA A LLENAR 100% DE LA PANTALLA ***
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.fill, // Esto fuerza que llene toda la pantalla aunque se comprima
            child: SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: _buildCameraPreview(cameraViewModel),
            ),
          ),
        ),
        
        // *** OVERLAY LAYERS DIRECTAMENTE EN EL STACK PRINCIPAL ***
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
                    screenSize: screenSize,
                    isMirrored: cameraViewModel.cameraController!.description.lensDirection 
                        == CameraLensDirection.front,
                    pulseValue: _pulseController.value,
                  ),
                );
              },
            ),
          ),
        
        // Target frame overlay
        Positioned.fill(
          child: CustomPaint(
            painter: TargetFramePainter(
              containerSize: screenSize,
              isActive: cameraViewModel.isDetectionEnabled,
            ),
          ),
        ),
        
        // *** UI ELEMENTS OVERLAY CON TAMAÑOS REDUCIDOS ***
        SafeArea(
          child: Stack(
            children: [
              // Indicador de detección más pequeño
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cameraViewModel.isDetectionEnabled ? 
                            (cameraViewModel.detectedBall != null ? 
                              '🏀 DETECTADO' : 'Buscando...') : 
                            'Desactivado',
                          style: TextStyle(
                            color: cameraViewModel.isDetectionEnabled ? 
                              (cameraViewModel.detectedBall != null ? 
                                Colors.green.shade400 :  
                                Colors.white70) : 
                              Colors.red.shade300,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        // *** MOSTRAR TIPO DE DETECCIÓN ***
                        if (cameraViewModel.isDetectionEnabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cameraViewModel.getCurrentDetectionType().contains('TFLite') ? 
                                Colors.blue.shade700 : Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              cameraViewModel.getCurrentDetectionType(),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              
              // FPS Indicator más pequeño
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cameraViewModel.currentDetectionFps >= 15 ? 
                        Colors.green : 
                        (cameraViewModel.currentDetectionFps >= 8 ? 
                          Colors.orange : Colors.red),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '📊',
                        style: TextStyle(fontSize: 10),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${cameraViewModel.currentDetectionFps.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: cameraViewModel.currentDetectionFps >= 15 ? 
                            Colors.green.shade400 : 
                            (cameraViewModel.currentDetectionFps >= 8 ? 
                              Colors.orange.shade400 : Colors.red.shade400),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Información de detección más compacta
              if (cameraViewModel.detectedBall != null)
                Positioned(
                  top: 50,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.shade400,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sports_basketball,
                              color: Colors.orange.shade400,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Detectado',
                              style: TextStyle(
                                color: Colors.green.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          'Conf',
                          '${(cameraViewModel.detectedBall!.confidence * 100).toStringAsFixed(0)}%',
                          fontSize: 10,
                        ),
                        _buildInfoRow(
                          'Pos',
                          '(${cameraViewModel.detectedBall!.center.dx.toInt()}, ${cameraViewModel.detectedBall!.center.dy.toInt()})',
                          fontSize: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              
              // *** PANEL DE DEBUG INFO ***
              if (cameraViewModel.isDebugMode)
                Positioned(
                  bottom: 120,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.shade400,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.bug_report,
                              color: Colors.blue.shade400,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'DEBUG INFO',
                              style: TextStyle(
                                color: Colors.blue.shade400,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          child: Text(
                            cameraViewModel.debugInfo,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Panel de controles en la parte inferior más compacto
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Botón para cambiar de cámara
                      if (cameraViewModel.cameras.length > 1)
                        _buildCompactButton(
                          icon: Icons.flip_camera_ios,
                          onPressed: cameraViewModel.switchCamera,
                          color: Colors.white54,
                        ),
                      
                      // *** NUEVO BOTÓN PARA CAMBIAR TIPO DE DETECCIÓN ***
                      _buildCompactButton(
                        icon: cameraViewModel.getCurrentDetectionType().contains('TFLite') ? 
                          Icons.psychology : Icons.palette,
                        onPressed: () {
                          cameraViewModel.toggleDetectionType();
                          
                          // Mostrar información del cambio
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    cameraViewModel.getCurrentDetectionType().contains('TFLite') ? 
                                      Icons.psychology : Icons.palette,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Detección: ${cameraViewModel.getCurrentDetectionType()}',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              backgroundColor: cameraViewModel.getCurrentDetectionType().contains('TFLite') ? 
                                Colors.blue.shade700 : Colors.orange.shade700,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        color: cameraViewModel.getCurrentDetectionType().contains('TFLite') ? 
                          Colors.blue.withOpacity(0.7) : Colors.orange.withOpacity(0.7),
                      ),
                      
                      // *** NUEVO BOTÓN PARA DEBUG ***
                      _buildCompactButton(
                        icon: Icons.bug_report,
                        onPressed: () {
                          cameraViewModel.toggleDebugMode();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Debug ${cameraViewModel.isDebugMode ? 'ACTIVADO' : 'DESACTIVADO'}',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              backgroundColor: cameraViewModel.isDebugMode ? 
                                Colors.green.shade700 : Colors.grey.shade700,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        color: cameraViewModel.isDebugMode ? 
                          Colors.green.withOpacity(0.7) : Colors.grey.withOpacity(0.5),
                      ),
                      
                      // Botón para activar/desactivar detección
                      _buildCompactButton(
                        icon: cameraViewModel.isDetectionEnabled
                            ? Icons.visibility
                            : Icons.visibility_off,
                        onPressed: cameraViewModel.toggleDetection,
                        color: cameraViewModel.isDetectionEnabled
                            ? Colors.green.withOpacity(0.7)
                            : Colors.red.withOpacity(0.7),
                      ),
                      
                      // Botón de debug más pequeño
                      _buildCompactButton(
                        icon: Icons.bug_report,
                        onPressed: () {
                          debugPrint('=== DEBUG INFO ===');
                          debugPrint(cameraViewModel.getPerformanceStats());
                          debugPrint(cameraViewModel.getBufferDebugInfo());
                          debugPrint('==================');
                        },
                        color: Colors.blue.withOpacity(0.7),
                        size: 40,
                      ),
                      
                      // *** NUEVO BOTÓN DE DEBUG ESPECÍFICO PARA DETECCIÓN ***
                      _buildCompactButton(
                        icon: Icons.search,
                        onPressed: () {
                          debugPrint('🔍 === DEBUG DETECCIÓN PELOTA ===');
                          debugPrint(cameraViewModel.getDetectionDebugInfo());
                          
                          // Mostrar también en pantalla
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Debug info impreso en consola. Revisa los logs.',
                                style: TextStyle(color: Colors.white),
                              ),
                              backgroundColor: Colors.orange.shade700,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        color: Colors.orange.withOpacity(0.7),
                        size: 40,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    double size = 48,
  }) {
    return Container(
      width: size,
      height: size,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: color,
        elevation: 2,
        child: Icon(
          icon,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value, {double fontSize = 12}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
              fontSize: fontSize,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCameraPreview(CameraViewModel viewModel) {
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
      return const Size(640, 480); // Tamaño por defecto
    }
    
    final previewSize = viewModel.cameraController!.value.previewSize!;
    
    // *** RESPETAR ORIENTACIÓN NATURAL DE LA CÁMARA ***
    debugPrint('📱 Preview Size natural: ${previewSize.width}x${previewSize.height}');
    return previewSize;
  }
}

class TargetFramePainter extends CustomPainter {
  final Size containerSize;
  final bool isActive;
  
  TargetFramePainter({
    required this.containerSize,
    required this.isActive,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive) return;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.15; // Más pequeño
    
    // Draw subtle target frame
    final framePaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Outer circle
    canvas.drawCircle(center, radius, framePaint);
    
    // Center crosshair más sutil
    final crosshairPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    
    // Horizontal line
    canvas.drawLine(
      Offset(center.dx - 10, center.dy),
      Offset(center.dx + 10, center.dy),
      crosshairPaint,
    );
    
    // Vertical line
    canvas.drawLine(
      Offset(center.dx, center.dy - 10),
      Offset(center.dx, center.dy + 10),
      crosshairPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    debugPrint('🎨 Painting - Canvas: ${size.width}x${size.height}, Preview: ${previewSize.width}x${previewSize.height}, Screen: ${screenSize.width}x${screenSize.height}');
    debugPrint('🎯 Ball position original: (${ballDetection.center.dx}, ${ballDetection.center.dy})');
    
    // *** TRANSFORMACIÓN PARA IMAGEN ESTIRADA QUE LLENA TODA LA PANTALLA ***
    // Con BoxFit.fill, la imagen se estira para llenar completamente la pantalla
    
    // Transformación directa - la imagen se estira/comprime para coincidir con la pantalla
    final scaleX = screenSize.width / previewSize.width;
    final scaleY = screenSize.height / previewSize.height;
    
    // Transformar coordenadas directamente (sin offset porque no hay crop)
    double centerX = ballDetection.center.dx * scaleX;
    double centerY = ballDetection.center.dy * scaleY;
    
    // Ajustar para cámara frontal (espejo horizontal únicamente)
    if (isMirrored) {
      centerX = screenSize.width - centerX;
    }
    
    // *** VERIFICAR QUE LA DETECCIÓN ESTÉ DENTRO DE LA PANTALLA ***
    if (centerX < 0 || centerX > screenSize.width || 
        centerY < 0 || centerY > screenSize.height) {
      debugPrint('🚫 Detección fuera de la pantalla - ignorando');
      return; // No dibujar si está fuera de la pantalla
    }
    
    final scaledRadius = ballDetection.radius * math.min(scaleX, scaleY);
    
    debugPrint('🎨 Scale: X=${scaleX.toStringAsFixed(2)}, Y=${scaleY.toStringAsFixed(2)} (stretch/compress)');
    debugPrint('🎨 Transformed: (${centerX.toStringAsFixed(1)}, ${centerY.toStringAsFixed(1)}), radius: ${scaledRadius.toStringAsFixed(1)}');
    
    // Draw tracking box más compacto
    final trackingPaint = Paint()
      ..color = Colors.green.withOpacity(0.4 + (pulseValue * 0.4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final boxSize = math.max(scaledRadius * 2.2, 40.0);
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: boxSize,
      height: boxSize,
    );
    
    // Draw tracking box with rounded corners
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(boxSize * 0.1)),
      trackingPaint,
    );
    
    // Draw corner marks más pequeños
    final cornerPaint = Paint()
      ..color = Colors.green.withOpacity(0.7 + (pulseValue * 0.3))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
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
    
    // Draw outer glow más sutil
    final pulseRadius = math.max(scaledRadius * (1.1 + pulseValue * 0.3), 15.0);
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
      ..color = Colors.green.withOpacity(0.8 + (pulseValue * 0.2))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    final circleRadius = math.max(scaledRadius, 12.0);
    canvas.drawCircle(
      Offset(centerX, centerY),
      circleRadius,
      circlePaint,
    );
    
    // Draw center point más pequeño pero visible
    final centerPaint = Paint()
      ..color = Colors.red.withOpacity(0.9 + (pulseValue * 0.1))
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      5.0 + (pulseValue * 3.0),
      centerPaint,
    );
    
    // Draw border around center point
    final centerBorderPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      5.0 + (pulseValue * 3.0),
      centerBorderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
