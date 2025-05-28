import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'camera_view_model.dart';
import 'package:app/features/shared/watch/watch_service.dart';
import 'package:app/features/shared/bluetooth/bluetooth_view_model.dart';

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
  final WatchService _watchService = WatchService();
  bool _appleWatchConnected = false;

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
      
      // Inicializar Apple Watch
      _initializeAppleWatch();
    });
  }
  
  Future<void> _initializeAppleWatch() async {
    await _watchService.initialize();
    setState(() {
      _appleWatchConnected = true;
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
              'Inicializando cámara...',
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
    return Stack(
      children: [
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: 1,
              height: 1,
              child: CameraPreview(cameraVM.cameraController!),
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
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Vista de cámara
          Positioned.fill(
            child: CameraPreview(cameraVM.cameraController!),
          ),
          
          // Panel de estado de dispositivos
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: _buildDeviceStatusPanel(),
          ),

          // Panel de control
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: _buildControlPanel(cameraVM),
          ),

          // Botón para simular un tiro desde el Apple Watch
          Positioned(
            right: 20,
            bottom: 100,
            child: FloatingActionButton(
              backgroundColor: Colors.orange.withOpacity(0.7),
              onPressed: () => _watchService.simulateShotDetection(),
              mini: true,
              tooltip: 'Simular tiro desde Apple Watch',
              child: const Icon(Icons.sports_basketball),
            ),
          ),
          
          // Botón para iniciar/detener monitoreo de Apple Watch
          Positioned(
            left: 20,
            bottom: 100,
            child: FloatingActionButton(
              backgroundColor: Colors.blue.withOpacity(0.7),
              onPressed: () => _toggleWatchMonitoring(cameraVM),
              mini: true,
              tooltip: 'Activar/Desactivar monitoreo de Apple Watch',
              child: const Icon(Icons.watch),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusPanel() {
    // Obtener el BluetoothViewModel para verificar estado
    final bluetoothVM = Provider.of<BluetoothViewModel>(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.bluetooth,
                color: bluetoothVM.isConnected ? Colors.blue : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Sensor Bluetooth: ${bluetoothVM.isConnected ? 'Conectado' : 'Desconectado'}',
                style: TextStyle(
                  color: bluetoothVM.isConnected ? Colors.blue : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.watch,
                color: _appleWatchConnected ? Colors.green : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Apple Watch: ${_appleWatchConnected ? 'Conectado' : 'No conectado'}',
                style: TextStyle(
                  color: _appleWatchConnected ? Colors.green : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(CameraViewModel cameraVM) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildControlButton(
            icon: Icons.watch,
            label: 'APPLE WATCH',
            color: Colors.blue,
            onTap: () => _toggleWatchMonitoring(cameraVM),
          ),
          _buildControlButton(
            icon: Icons.bluetooth,
            label: 'BLUETOOTH',
            color: Colors.green,
            onTap: () => _toggleBluetoothConnection(),
          ),
          _buildControlButton(
            icon: Icons.sports_basketball,
            label: 'SIMULAR',
            color: Colors.orange,
            onTap: () => _watchService.simulateShotDetection(),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _toggleWatchMonitoring(CameraViewModel cameraVM) async {
    // Esta función alternará el monitoreo del Apple Watch
    if (_appleWatchConnected) {
      await cameraVM.startWatchMonitoring();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monitoreo de Apple Watch activado'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Apple Watch no conectado'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _toggleBluetoothConnection() {
    // Esta función alternará la conexión Bluetooth
    final bluetoothVM = Provider.of<BluetoothViewModel>(context, listen: false);
    
    if (bluetoothVM.isConnected) {
      bluetoothVM.disconnect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sensor Bluetooth desconectado'),
          backgroundColor: Colors.orange,
        ),
      );
    } else {
      bluetoothVM.scanAndConnect();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conectando sensor Bluetooth...'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }
} 