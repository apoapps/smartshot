import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';

/// Resultado de detección de baloncesto
class BasketballDetection {
  final Offset center;
  final double radius;
  final double confidence;
  final Rect boundingBox;
  final DateTime timestamp;

  BasketballDetection({
    required this.center,
    required this.radius,
    required this.confidence,
    required this.boundingBox,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Detector de baloncesto usando análisis de color (sin TFLite)
class BasketballDetector {
  bool _isInitialized = false;
  
  // Configuración de detección por color
  static const double _confidenceThreshold = 0.3;
  static const int _minPixelCount = 20;
  static const int _maxPixelCount = 2000;

  /// Inicializar el detector (solo marca como inicializado)
  Future<bool> initialize() async {
    debugPrint('🎨 Inicializando detector de baloncesto por color...');
    _isInitialized = true;
    debugPrint('✅ Detector por color inicializado correctamente');
    return true;
  }

  /// Detectar baloncesto en una imagen de cámara usando análisis de color
  Future<List<BasketballDetection>> detectInCameraImage(CameraImage cameraImage) async {
    if (!_isInitialized) {
      return [];
    }

    try {
      // Convertir CameraImage a img.Image
      final processedImage = await _convertCameraImageToImage(cameraImage);
      if (processedImage == null) return [];

      // Detectar usando análisis de color
      return await detectInImage(processedImage);
    } catch (e) {
      debugPrint('❌ Error en detección por color: $e');
      return [];
    }
  }

  /// Detectar baloncesto en bytes de imagen
  Future<List<BasketballDetection>> detectInImageBytes(Uint8List imageBytes) async {
    if (!_isInitialized) {
      return [];
    }

    try {
      // Decodificar imagen desde bytes
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        debugPrint('❌ No se pudo decodificar la imagen desde bytes');
        return [];
      }

      return await detectInImage(image);
    } catch (e) {
      debugPrint('❌ Error en detección con bytes: $e');
      return [];
    }
  }

  /// Detectar baloncesto usando análisis de color
  Future<List<BasketballDetection>> detectInImage(img.Image image) async {
    if (!_isInitialized) {
      return [];
    }

    try {
      // Encontrar píxeles candidatos de color naranja/marrón
      final candidatePixels = <Offset>[];
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixelSafe(x, y);
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          
          if (_isBasketballColor(r, g, b)) {
            candidatePixels.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
      }

      if (candidatePixels.length < _minPixelCount) {
        return [];
      }

      // Agrupar píxeles cercanos
      final clusters = _clusterPixels(candidatePixels);
      
      // Convertir clusters a detecciones
      final detections = <BasketballDetection>[];
      for (final cluster in clusters) {
        if (cluster.length >= _minPixelCount && cluster.length <= _maxPixelCount) {
          final detection = _clusterToDetection(cluster);
          if (detection.confidence >= _confidenceThreshold) {
            detections.add(detection);
          }
        }
      }

      return detections;
    } catch (e) {
      debugPrint('❌ Error en detección de imagen: $e');
      return [];
    }
  }

  /// Verificar si un píxel tiene color de baloncesto
  bool _isBasketballColor(int r, int g, int b) {
    // Color naranja típico del baloncesto
    if (r > 100 && g > 50 && b < 80 && r > g && g > b) {
      return true;
    }
    
    // Color marrón/cuero
    if (r >= 70 && r <= 180 && 
        g >= 40 && g <= 140 && 
        b >= 20 && b <= 100 && 
        r > b && g > b) {
      return true;
    }
    
    return false;
  }

  /// Agrupar píxeles cercanos en clusters
  List<List<Offset>> _clusterPixels(List<Offset> pixels) {
    final clusters = <List<Offset>>[];
    final visited = Set<int>();
    
    for (int i = 0; i < pixels.length; i++) {
      if (visited.contains(i)) continue;
      
      final cluster = <Offset>[];
      final queue = <int>[i];
      
      while (queue.isNotEmpty) {
        final currentIndex = queue.removeAt(0);
        if (visited.contains(currentIndex)) continue;
        
        visited.add(currentIndex);
        cluster.add(pixels[currentIndex]);
        
        // Buscar píxeles vecinos
        for (int j = 0; j < pixels.length; j++) {
          if (visited.contains(j)) continue;
          
          final distance = (pixels[currentIndex] - pixels[j]).distance;
          if (distance <= 15.0) { // Radio de agrupación
            queue.add(j);
          }
        }
      }
      
      if (cluster.length >= _minPixelCount) {
        clusters.add(cluster);
      }
    }
    
    return clusters;
  }

  /// Convertir cluster de píxeles a detección
  BasketballDetection _clusterToDetection(List<Offset> cluster) {
    // Calcular centro
    double sumX = 0, sumY = 0;
    double minX = cluster.first.dx, maxX = cluster.first.dx;
    double minY = cluster.first.dy, maxY = cluster.first.dy;
    
    for (final point in cluster) {
      sumX += point.dx;
      sumY += point.dy;
      minX = min(minX, point.dx);
      maxX = max(maxX, point.dx);
      minY = min(minY, point.dy);
      maxY = max(maxY, point.dy);
    }
    
    final center = Offset(sumX / cluster.length, sumY / cluster.length);
    final width = maxX - minX;
    final height = maxY - minY;
    final radius = sqrt(cluster.length / pi);
    
    // Calcular confianza basada en forma y tamaño
    final aspectRatio = max(width, height) / min(width, height);
    final sizeScore = min(1.0, cluster.length / 500.0);
    final shapeScore = max(0.0, 1.0 - (aspectRatio - 1.0) / 2.0);
    final confidence = (sizeScore + shapeScore) / 2.0;
    
    final boundingBox = Rect.fromLTWH(minX, minY, width, height);
    
    return BasketballDetection(
      center: center,
      radius: radius,
      confidence: confidence,
      boundingBox: boundingBox,
    );
  }

  /// Convertir CameraImage a img.Image
  Future<img.Image?> _convertCameraImageToImage(CameraImage cameraImage) async {
    try {
      img.Image? image;
      
      if (cameraImage.format.group == ImageFormatGroup.yuv420) {
        // Android YUV420
        image = _convertYUV420ToImage(cameraImage);
      } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
        // iOS BGRA8888
        image = _convertBGRA8888ToImage(cameraImage);
      }
      
      return image;
    } catch (e) {
      debugPrint('❌ Error al convertir CameraImage: $e');
      return null;
    }
  }

  /// Convertir YUV420 a img.Image (Android)
  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    
    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;
    
    final image = img.Image(width: width, height: height);
    
    for (int h = 0; h < height; h++) {
      for (int w = 0; w < width; w++) {
        final yIndex = h * width + w;
        final uvIndex = (h ~/ 2) * (width ~/ 2) + (w ~/ 2);
        
        if (yIndex < yBuffer.length && uvIndex < uBuffer.length && uvIndex < vBuffer.length) {
          final y = yBuffer[yIndex];
          final u = uBuffer[uvIndex];
          final v = vBuffer[uvIndex];
          
          // Conversión YUV a RGB
          int r = (y + 1.402 * (v - 128)).round().clamp(0, 255);
          int g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
          int b = (y + 1.772 * (u - 128)).round().clamp(0, 255);
          
          image.setPixelRgba(w, h, r, g, b, 255);
        }
      }
    }
    
    return image;
  }

  /// Convertir BGRA8888 a img.Image (iOS)
  img.Image? _convertBGRA8888ToImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;
    final buffer = cameraImage.planes[0].bytes;
    
    final image = img.Image(width: width, height: height);
    
    for (int h = 0; h < height; h++) {
      for (int w = 0; w < width; w++) {
        final index = (h * width + w) * 4;
        
        if (index + 3 < buffer.length) {
          final b = buffer[index];
          final g = buffer[index + 1];
          final r = buffer[index + 2];
          final a = buffer[index + 3];
          
          image.setPixelRgba(w, h, r, g, b, a);
        }
      }
    }
    
    return image;
  }

  /// Verificar si el detector está inicializado
  bool get isInitialized => _isInitialized;

  /// Liberar recursos
  void dispose() {
    _isInitialized = false;
    debugPrint('🗑️ Detector de baloncesto por color liberado');
  }
} 