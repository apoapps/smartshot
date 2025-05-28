import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../shared/connectivity/connectivity_service.dart';
import '../../shared/connectivity/connectivity_status_widget.dart';
import 'session_screen.dart';
import 'sessions_history_screen.dart';

class SmartShotHomePage extends StatefulWidget {
  const SmartShotHomePage({super.key});

  @override
  State<SmartShotHomePage> createState() => _SmartShotHomePageState();
}

class _SmartShotHomePageState extends State<SmartShotHomePage> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothViewModel = Provider.of<BluetoothViewModel>(context);
    final connectivityService = Provider.of<ConnectivityService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 36,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.sports_basketball, size: 36),
            ),
            const SizedBox(width: 8),
            const Text(
              'SmartShot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            const ConnectivityStatusWidget(
              isCompact: true,
              showLabels: false,
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.home), text: 'Inicio'),
            Tab(icon: Icon(Icons.history), text: 'Historial'),
          ],
          indicatorColor: Colors.orange,
          labelColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHomeTab(bluetoothViewModel, connectivityService),
          const SessionsHistoryScreen(),
        ],
      ),
    );
  }
  
  Widget _buildHomeTab(BluetoothViewModel bluetoothViewModel, ConnectivityService connectivityService) {
    // Estado 1: Buscando (loading)
    if (bluetoothViewModel.isConnecting) {
      return _buildSearchingState();
    }
    
    // Verificar si se puede iniciar una sesión basado en el estado de conectividad
    if (!connectivityService.canStartSession()) {
      return _buildDisconnectedState(context, connectivityService);
    }
    
    // Estado 3: Conectado (muestra el dashboard)
    return _buildDashboard(bluetoothViewModel, connectivityService, context);
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
  
  Widget _buildDisconnectedState(BuildContext context, ConnectivityService connectivityService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(
            Icons.settings_input_antenna,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 20),
          const Text(
            'Conecta tus dispositivos\npara comenzar',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            connectivityService.getSessionBlockMessage(),
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          
          // Widget de estado de conectividad completo
          const ConnectivityStatusWidget(
            isCompact: false,
            showLabels: true,
          ),
          
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => Provider.of<BluetoothViewModel>(context, listen: false).scanAndConnect(),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Buscar Sensor Bluetooth'),
          ),
          const SizedBox(height: 20),
          // Botones para desarrollo/pruebas
          Visibility(
            visible: true, // Cambiar a false para producción
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _tabController.animateTo(1); // Cambiar a pestaña de historial
                  },
                  icon: const Icon(Icons.history, color: Colors.orange),
                  label: const Text('Historial', style: TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const SessionScreen())
                    );
                  },
                  icon: const Icon(Icons.play_circle_outline, color: Colors.green),
                  label: const Text('Sesión', style: TextStyle(color: Colors.green)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.green.shade300),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboard(BluetoothViewModel bluetoothViewModel, ConnectivityService connectivityService, BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 20),
          
          // Panel de estado de conectividad compacto en el dashboard
          const ConnectivityStatusWidget(
            isCompact: false,
            showLabels: true,
          ),
          
          const SizedBox(height: 30),
          GestureDetector(
            onTap: () {
              if (connectivityService.canStartSession()) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const SessionScreen())
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(connectivityService.getSessionBlockMessage()),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: connectivityService.canStartSession() 
                      ? Colors.orange.shade800 
                      : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Image.asset(
                        'assets/logo.png',
                        height: 40,
                        errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.sports_basketball, size: 40, color: Colors.white),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          connectivityService.canStartSession()
                              ? 'Comenzar\npartida!'
                              : 'Conecta dispositivos\npara comenzar',
                          style: TextStyle(
                            color: connectivityService.canStartSession() 
                                ? Colors.white 
                                : Colors.grey[400],
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 