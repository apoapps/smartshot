import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../camera/camera_view.dart';
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
    final viewModel = Provider.of<BluetoothViewModel>(context);

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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: viewModel.isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                border: Border.all(
                  color: viewModel.isConnected ? Colors.green : Colors.red,
                ),
              ),
              child: Text(
                viewModel.isConnected ? 'Conectado' : 'Desconectado',
                style: TextStyle(
                  color: viewModel.isConnected ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
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
          _buildHomeTab(viewModel),
          const SessionsHistoryScreen(),
        ],
      ),
    );
  }
  
  Widget _buildHomeTab(BluetoothViewModel viewModel) {
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
          const Icon(
            Icons.settings_input_antenna,
            size: 80,
            color: Colors.white70,
          ),
          const SizedBox(height: 20),
          const Text(
            'Conecta tu SmartShot\npara comenzar!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => Provider.of<BluetoothViewModel>(context, listen: false).scanAndConnect(),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Reintentar'),
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
  
  Widget _buildDashboard(BluetoothViewModel viewModel, BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 30),
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SessionScreen())
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
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
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 16.0),
                        child: Text(
                          'Comenzar\npartida!',
                          style: TextStyle(
                            color: Colors.white,
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