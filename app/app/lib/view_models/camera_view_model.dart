import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class BallDetection {
  final Offset center;
  final double radius;
  final double confidence;

  BallDetection({
    required this.center,
    required this.radius,
    required this.confidence,
  });
}

class CameraViewModel extends ChangeNotifier {
  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  bool isInitialized = false;
  bool isLoading = false;
  String? errorMessage;
  
  // Variables para la detección del balón
  bool isProcessingFrame = false;
  BallDetection? detectedBall;
  bool isDetectionEnabled = true;
  
  // Almacenar el último frame procesado como imagen
  Uint8List? lastProcessedFrame;

  Future<void> initializeCamera() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Obtener cámaras disponibles
      cameras = await availableCameras();
      
      if (cameras.isEmpty) {
        errorMessage = "No se encontraron cámaras disponibles";
        isLoading = false;
        notifyListeners();
        return;
      }

      // Inicializar con la cámara trasera por defecto
      final rearCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      cameraController = CameraController(
        rearCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );

      // Inicializar la cámara
      await cameraController!.initialize();
      isInitialized = true;
      isLoading = false;

      // Comenzar procesamiento de frames
      _startImageStream();
      
      notifyListeners();
    } catch (e) {
      errorMessage = "Error al inicializar la cámara: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  void switchCamera() async {
    if (cameras.length < 2 || cameraController == null) return;

    isLoading = true;
    notifyListeners();

    // Obtener dirección actual
    final currentDirection = cameraController!.description.lensDirection;
    // Cambiar a la dirección opuesta
    final newDirection = currentDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // Encontrar la cámara con la nueva dirección
    final newCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == newDirection,
      orElse: () => cameras.first,
    );

    // Deshacer el controlador actual
    await cameraController!.dispose();

    // Crear un nuevo controlador con la nueva cámara
    cameraController = CameraController(
      newCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid 
          ? ImageFormatGroup.yuv420 
          : ImageFormatGroup.bgra8888,
    );

    try {
      await cameraController!.initialize();
      
      // Reiniciar procesamiento de frames
      _startImageStream();
      
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = "Error al cambiar la cámara: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  void _startImageStream() {
    if (!isInitialized || cameraController == null) return;
    
    cameraController!.startImageStream((CameraImage image) {
      if (!isProcessingFrame && isDetectionEnabled) {
        isProcessingFrame = true;
        _processImageForBallDetection(image);
      }
    });
  }

  void toggleDetection() {
    isDetectionEnabled = !isDetectionEnabled;
    notifyListeners();
    
    if (isDetectionEnabled) {
      _startImageStream();
    }
  }

  Future<void> _processImageForBallDetection(CameraImage image) async {
    try {
      // Convertir imagen de cámara a formato adecuado
      final processedImage = await compute(_convertCameraImageToImage, image);
      
      // Detectar balón usando procesamiento de color (como en MATLAB)
      final ballDetection = await compute(_detectBasketball, processedImage);
      
      detectedBall = ballDetection;
      
      // Guarda el último frame procesado
      if (processedImage != null) {
        final pngBytes = img.encodePng(processedImage);
        lastProcessedFrame = Uint8List.fromList(pngBytes);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error en procesamiento de imagen: $e');
    } finally {
      isProcessingFrame = false;
    }
  }

  static img.Image? _convertCameraImageToImage(CameraImage cameraImage) {
    try {
      if (Platform.isAndroid) {
        // Android usa YUV
        final width = cameraImage.width;
        final height = cameraImage.height;
        
        final yuvImage = img.Image(width: width, height: height);
        
        // Plano Y
        final yBuffer = cameraImage.planes[0].bytes;
        final yRowStride = cameraImage.planes[0].bytesPerRow;
        final yPixelStride = cameraImage.planes[0].bytesPerPixel ?? 1;
        
        // Planos U y V
        final uBuffer = cameraImage.planes[1].bytes;
        final uRowStride = cameraImage.planes[1].bytesPerRow;
        final uPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;
        final vBuffer = cameraImage.planes[2].bytes;
        final vRowStride = cameraImage.planes[2].bytesPerRow;
        final vPixelStride = cameraImage.planes[2].bytesPerPixel ?? 1;
        
        // Convertir YUV a RGB
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final yIndex = h * yRowStride + w * yPixelStride;
            // Los planos U y V tienen la mitad de la resolución
            final uvh = h ~/ 2;
            final uvw = w ~/ 2;
            final uIndex = uvh * uRowStride + uvw * uPixelStride;
            final vIndex = uvh * vRowStride + uvw * vPixelStride;
            
            if (yIndex < yBuffer.length && 
                uIndex < uBuffer.length && 
                vIndex < vBuffer.length) {
              // YUV a RGB
              final y = yBuffer[yIndex];
              final u = uBuffer[uIndex];
              final v = vBuffer[vIndex];
              
              int r = (y + 1.402 * (v - 128)).round().clamp(0, 255);
              int g = (y - 0.344136 * (u - 128) - 0.714136 * (v - 128)).round().clamp(0, 255);
              int b = (y + 1.772 * (u - 128)).round().clamp(0, 255);
              
              yuvImage.setPixelRgba(w, h, r, g, b, 255);
            }
          }
        }
        
        return yuvImage;
      } else {
        // iOS usa BGRA
        final width = cameraImage.width;
        final height = cameraImage.height;
        final bgra = img.Image(width: width, height: height);
        
        final buffer = cameraImage.planes[0].bytes;
        final rowStride = cameraImage.planes[0].bytesPerRow;
        final pixelStride = cameraImage.planes[0].bytesPerPixel ?? 4;
        
        for (int h = 0; h < height; h++) {
          for (int w = 0; w < width; w++) {
            final index = h * rowStride + w * pixelStride;
            if (index + 3 < buffer.length) {
              // BGRA a RGBA
              final b = buffer[index];
              final g = buffer[index + 1];
              final r = buffer[index + 2];
              final a = buffer[index + 3];
              
              bgra.setPixelRgba(w, h, r, g, b, a);
            }
          }
        }
        
        return bgra;
      }
    } catch (e) {
      debugPrint('Error al convertir imagen: $e');
      return null;
    }
  }

  static BallDetection? _detectBasketball(img.Image? image) {
    if (image == null) return null;
    
    // Implementación similar al algoritmo de MATLAB proporcionado
    final width = image.width;
    final height = image.height;
    
    // Umbral ampliado para detección de color naranja (incluyendo tonos más rojizos y amarillentos)
    const hueMin = 0.0;    // Ahora incluye rojos (antes 0.01)
    const hueMax = 0.17;   // Ampliar hacia amarillo (antes 0.15)
    const satMin = 0.35;   // Menos saturación requerida (antes 0.5)
    const valMin = 0.3;    // Funciona en condiciones de menor luz (antes 0.4)
    
    // Crear una máscara binaria para los píxeles de color naranja
    final orangeMask = List.generate(
      height, 
      (_) => List.filled(width, false),
    );
    
    // Número de píxeles naranjas
    int orangePixelCount = 0;
    
    // Detectar píxeles naranjas
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Extraer los componentes RGB usando el nuevo método de la v4.5.4
        final r = image.getPixelSafe(x, y).r.toInt();
        final g = image.getPixelSafe(x, y).g.toInt();
        final b = image.getPixelSafe(x, y).b.toInt();
        
        // Convertir a HSV
        final hsv = _rgbToHsv(r, g, b);
        final h = hsv[0];
        final s = hsv[1];
        final v = hsv[2];
        
        // Verificar si el color está en el rango de naranja (considerando que h=0 es rojo)
        if (((h >= hueMin && h <= hueMax) || (h >= 0.95 && h <= 1.0)) && (s > satMin) && (v > valMin)) {
          orangeMask[y][x] = true;
          orangePixelCount++;
        }
      }
    }
    
    // Si no hay suficientes píxeles naranjas, no se detecta un balón
    // Reducir el umbral para detectar objetos más pequeños
    if (orangePixelCount < 300) return null;  // Antes 500
    
    // Aplicar operaciones morfológicas (simular cierre morfológico)
    _applyDilation(orangeMask, 6);  // Dilatar un poco más (antes 5)
    _applyErosion(orangeMask, 3);
    
    // Encontrar componentes conectados y seleccionar el más circular
    final components = _findConnectedComponents(orangeMask);
    
    BallDetection? bestBall;
    double bestCircularity = 0;
    
    for (final component in components) {
      if (component.pixels.length < 200) continue;  // Menor umbral para objetos pequeños (antes 400)
      
      // Calcular propiedades
      final properties = _calculateRegionProperties(component);
      final circularity = properties['circularity'] ?? 0;
      final radius = properties['radius'] ?? 0;
      
      // Filtrar por forma y tamaño con umbrales menos estrictos
      if (circularity > 0.70 && radius >= 15 && radius <= 200 && 
          circularity > bestCircularity) {  // Antes 0.88, 20 y 150
        bestCircularity = circularity;
        bestBall = BallDetection(
          center: properties['center'] ?? Offset.zero,
          radius: radius,
          confidence: circularity,
        );
      }
    }
    
    return bestBall;
  }
  
  static List<double> _rgbToHsv(int r, int g, int b) {
    // Normalizar RGB [0-255] a [0-1]
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    
    final cmax = [rf, gf, bf].reduce(max);
    final cmin = [rf, gf, bf].reduce(min);
    final delta = cmax - cmin;
    
    // Calcular matiz
    double h = 0.0;
    if (delta != 0) {
      if (cmax == rf) {
        h = (((gf - bf) / delta) % 6) / 6;
      } else if (cmax == gf) {
        h = (((bf - rf) / delta) + 2) / 6;
      } else {
        h = (((rf - gf) / delta) + 4) / 6;
      }
    }
    
    if (h < 0) h += 1.0;
    
    // Calcular saturación
    final s = cmax == 0 ? 0.0 : delta / cmax;
    
    // Valor
    final v = cmax;
    
    return [h, s, v];
  }
  
  static void _applyDilation(List<List<bool>> mask, int size) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(
      height, 
      (y) => List.from(mask[y]),
    );
    
    final radius = size ~/ 2;
    
    for (int y = radius; y < height - radius; y++) {
      for (int x = radius; x < width - radius; x++) {
        if (!mask[y][x]) continue;
        
        // Aplicar dilatación
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              result[y + dy][x + dx] = true;
            }
          }
        }
      }
    }
    
    // Copiar resultado de vuelta a la máscara original
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        mask[y][x] = result[y][x];
      }
    }
  }
  
  static void _applyErosion(List<List<bool>> mask, int size) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(
      height, 
      (y) => List.from(mask[y]),
    );
    
    final radius = size ~/ 2;
    
    for (int y = radius; y < height - radius; y++) {
      for (int x = radius; x < width - radius; x++) {
        // Verificar si todos los píxeles en el vecindario son true
        bool allTrue = true;
        
        for (int dy = -radius; dy <= radius && allTrue; dy++) {
          for (int dx = -radius; dx <= radius && allTrue; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              if (!mask[y + dy][x + dx]) {
                allTrue = false;
                break;
              }
            }
          }
        }
        
        result[y][x] = allTrue;
      }
    }
    
    // Copiar resultado de vuelta a la máscara original
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        mask[y][x] = result[y][x];
      }
    }
  }
  
  static List<_ConnectedComponent> _findConnectedComponents(List<List<bool>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final visited = List.generate(
      height, 
      (_) => List.filled(width, false),
    );
    
    final components = <_ConnectedComponent>[];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (mask[y][x] && !visited[y][x]) {
          final component = _ConnectedComponent();
          _floodFill(mask, visited, x, y, component);
          components.add(component);
        }
      }
    }
    
    return components;
  }
  
  static void _floodFill(
    List<List<bool>> mask, 
    List<List<bool>> visited, 
    int x, 
    int y, 
    _ConnectedComponent component
  ) {
    final height = mask.length;
    final width = mask[0].length;
    
    // Pila para DFS (evitar desbordamiento de pila)
    final stack = <Point<int>>[];
    stack.add(Point(x, y));
    
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final px = point.x;
      final py = point.y;
      
      if (px < 0 || py < 0 || px >= width || py >= height) continue;
      if (!mask[py][px] || visited[py][px]) continue;
      
      visited[py][px] = true;
      component.pixels.add(Point(px, py));
      
      // Añadir vecinos a la pila
      stack.add(Point(px + 1, py));
      stack.add(Point(px - 1, py));
      stack.add(Point(px, py + 1));
      stack.add(Point(px, py - 1));
    }
  }
  
  static Map<String, dynamic> _calculateRegionProperties(_ConnectedComponent component) {
    if (component.pixels.isEmpty) {
      return {'center': Offset.zero, 'radius': 0, 'circularity': 0};
    }
    
    // Calcular centro
    double sumX = 0;
    double sumY = 0;
    
    for (final pixel in component.pixels) {
      sumX += pixel.x;
      sumY += pixel.y;
    }
    
    final centerX = sumX / component.pixels.length;
    final centerY = sumY / component.pixels.length;
    final center = Offset(centerX, centerY);
    
    // Calcular radio (distancia media al centro)
    double sumDist = 0;
    for (final pixel in component.pixels) {
      final dx = pixel.x - centerX;
      final dy = pixel.y - centerY;
      sumDist += sqrt(dx * dx + dy * dy);
    }
    
    final avgRadius = sumDist / component.pixels.length;
    
    // Calcular circularidad
    double sumDeviation = 0;
    for (final pixel in component.pixels) {
      final dx = pixel.x - centerX;
      final dy = pixel.y - centerY;
      final dist = sqrt(dx * dx + dy * dy);
      sumDeviation += (dist - avgRadius).abs();
    }
    
    final avgDeviation = sumDeviation / component.pixels.length;
    
    // Calcular circularidad (1 = círculo perfecto, menor = menos circular)
    final circularity = 1 - (avgDeviation / avgRadius);
    
    return {
      'center': center,
      'radius': avgRadius,
      'circularity': circularity,
    };
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }
}

class _ConnectedComponent {
  final List<Point<int>> pixels = [];
}
