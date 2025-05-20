import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../view_models/camera_view_model.dart';

class CameraView extends StatefulWidget {
  const CameraView({Key? key}) : super(key: key);

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
      appBar: AppBar(
        title: const Text('Vista de Cámara'),
      ),
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

          return Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraPreview(cameraViewModel.cameraController!),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Botón para cambiar de cámara
                    FloatingActionButton(
                      onPressed: cameraViewModel.switchCamera,
                      child: const Icon(Icons.flip_camera_ios),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
