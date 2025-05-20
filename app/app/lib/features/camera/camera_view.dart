import 'dart:typed_data';

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
            return const Center(child: Text('La cámara no está inicializada'));
          }

          return Stack(
            children: [
              // Vista de la cámara
             ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraPreview(cameraViewModel.cameraController!),
                ),
              
              
              // Capa para dibujar la detección
              if (cameraViewModel.detectedBall != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: BallDetectionPainter(
                      ballDetection: cameraViewModel.detectedBall!,
                      previewSize: Size(
                        cameraViewModel.cameraController!.value.previewSize!.height,
                        cameraViewModel.cameraController!.value.previewSize!.width,
                      ),
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
                    FloatingActionButton(
                      onPressed: cameraViewModel.switchCamera,
                      heroTag: 'switchCamera',
                      child: const Icon(Icons.flip_camera_ios),
                    ),
                    
                    // Botón para activar/desactivar detección
                    FloatingActionButton(
                      onPressed: cameraViewModel.toggleDetection,
                      heroTag: 'toggleDetection',
                      backgroundColor: cameraViewModel.isDetectionEnabled
                          ? Colors.green
                          : Colors.red,
                      child: Icon(
                        cameraViewModel.isDetectionEnabled
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Información de detección
              if (cameraViewModel.detectedBall != null)
                Positioned(
                  top: 20,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Balón detectado',
                          style: TextStyle(
                            color: Colors.green.shade300,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Confianza: ${(cameraViewModel.detectedBall!.confidence * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Tamaño: ${cameraViewModel.detectedBall!.radius.toStringAsFixed(1)} px',
                          style: const TextStyle(color: Colors.white),
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
    // Calcular factores de escala para adaptar coordenadas
    final double scaleX = size.width / previewSize.width;
    final double scaleY = size.height / previewSize.height;
    
    // Calcular centro ajustado
    double centerX = ballDetection.center.dx * scaleX;
    double centerY = ballDetection.center.dy * scaleY;
    
    // Ajustar para cámara frontal (espejo)
    if (isMirrored) {
      centerX = size.width - centerX;
    }
    
    // Calcular radio ajustado a la escala
    final scaledRadius = ballDetection.radius * (scaleX + scaleY) / 2;
    
    // Dibujar círculo alrededor del balón
    final paintCircle = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      scaledRadius,
      paintCircle,
    );
    
    // Dibujar punto central
    final paintCenter = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill
      ..strokeWidth = 8.0;
    
    canvas.drawCircle(
      Offset(centerX, centerY),
      8.0,
      paintCenter,
    );
    
    // Mostrar coordenadas
    final textPainter = TextPainter(
      text: TextSpan(
        text: '(${centerX.toInt()}, ${centerY.toInt()})',
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              blurRadius: 3.0,
              color: Colors.black,
              offset: Offset(1.0, 1.0),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(centerX + 15, centerY - 15),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
