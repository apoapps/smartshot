import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../camera/camera_view.dart';

class SmartShotHomePage extends StatelessWidget {
  const SmartShotHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<BluetoothViewModel>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Fondo oscuro para el tema dark
      appBar: AppBar(
        title: const Text('SmartShot', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E), // Barra de app oscura
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: InkWell(
              onTap: viewModel.isConnecting 
                ? null 
                : (viewModel.isConnected ? viewModel.disconnect : viewModel.scanAndConnect),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: viewModel.isConnected ? Colors.green : Colors.red,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      viewModel.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                      color: viewModel.isConnected ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      viewModel.isConnecting
                        ? 'Conectando...'
                        : (viewModel.isConnected ? 'Conectado' : 'Buscar'),
                      style: TextStyle(
                        color: viewModel.isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(viewModel, context),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.purple.shade600,
        child: const Icon(Icons.camera_alt, color: Colors.white),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CameraView())
          );
        },
      ),
    );
  }
  
  Widget _buildBody(BluetoothViewModel viewModel, BuildContext context) {
    // Estado 1: Buscando (loading)
    if (viewModel.isConnecting) {
      return _buildSearchingState();
    }
    
    // Estado 2: Desconectado
    if (!viewModel.isConnected) {
      return _buildDisconnectedState(context);
    }
    
    // Estado 3: Conectado (muestra el dashboard)
    return _buildDashboard(viewModel, context);
  }
  
  Widget _buildSearchingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 20),
          Text(
            'Buscando SmartShot...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade300,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDisconnectedState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bluetooth_disabled,
            size: 80,
            color: Colors.red.shade300,
          ),
          const SizedBox(height: 20),
          const Text(
            'Dispositivo desconectado',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Presiona el botón "Buscar" para conectarte',
            style: TextStyle(fontSize: 16, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () => Provider.of<BluetoothViewModel>(context, listen: false).scanAndConnect(),
            icon: const Icon(Icons.bluetooth_searching, color: Colors.white),
            label: const Text('Buscar dispositivo', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboard(BluetoothViewModel viewModel, BuildContext context) {
    // Determinar si estamos en un dispositivo de pantalla grande
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sensor Ultrasónico',
            style: TextStyle(
              fontSize: 22, 
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          // Layout adaptable basado en el tamaño de pantalla
          Expanded(
            child: isLargeScreen
                ? _buildLargeScreenLayout(viewModel)
                : _buildSmallScreenLayout(viewModel),
          ),
        ],
      ),
    );
  }
  
  // Layout para pantallas grandes (en row)
  Widget _buildLargeScreenLayout(BluetoothViewModel viewModel) {
    return Row(
      children: [
        // Contador de Aciertos
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildAciertosCard(viewModel),
          ),
        ),
        
        // Visualización de la distancia
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: _buildDistanciaCard(viewModel),
          ),
        ),
      ],
    );
  }
  
  // Layout para pantallas pequeñas (en column)
  Widget _buildSmallScreenLayout(BluetoothViewModel viewModel) {
    return Column(
      children: [
        // Contador de Aciertos
        _buildAciertosCard(viewModel),
        const SizedBox(height: 20),
        
        // Visualización de la distancia
        _buildDistanciaCard(viewModel),
      ],
    );
  }
  
  // Widget para el contador de aciertos
  Widget _buildAciertosCard(BluetoothViewModel viewModel) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1C3A), // Morado oscuro para mantener tinte pero oscuro
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.score,
              size: 48,
              color: Colors.purple.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'Aciertos: ${viewModel.aciertos}',
              style: const TextStyle(
                fontSize: 24, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Widget para la visualización de distancia
  Widget _buildDistanciaCard(BluetoothViewModel viewModel) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2939), // Azul oscuro para mantener tinte pero oscuro
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.straighten,
              size: 36,
              color: Colors.blue.shade300,
            ),
            const SizedBox(height: 12),
            const Text(
              'Distancia actual:',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              '${viewModel.distancia.toStringAsFixed(1)} cm',
              style: const TextStyle(
                fontSize: 32, 
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 