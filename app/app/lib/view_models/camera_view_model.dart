import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraViewModel extends ChangeNotifier {
  CameraController? cameraController;
  List<CameraDescription> cameras = [];
  bool isInitialized = false;
  bool isLoading = false;
  String? errorMessage;

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
      );

      // Inicializar la cámara
      await cameraController!.initialize();
      isInitialized = true;
      isLoading = false;
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
    );

    try {
      await cameraController!.initialize();
      isLoading = false;
      notifyListeners();
    } catch (e) {
      errorMessage = "Error al cambiar la cámara: $e";
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    cameraController?.dispose();
    super.dispose();
  }
}
