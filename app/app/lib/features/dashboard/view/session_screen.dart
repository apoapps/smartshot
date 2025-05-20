import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/sessions/view_model/session_view_model.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../camera/camera_view.dart';
import 'package:intl/intl.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  @override
  void initState() {
    super.initState();
    // Iniciar la sesión cuando se carga la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SessionViewModel>(context, listen: false).startSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo.png',
              height: 32,
              errorBuilder: (context, error, stackTrace) => 
                  const Icon(Icons.sports_basketball, size: 32, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text(
              'SmartShot',
              style: TextStyle(color: Colors.white),
            ),
            const Spacer(),
            Consumer<BluetoothViewModel>(
              builder: (context, viewModel, _) {
                return Container(
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
                );
              },
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer<SessionViewModel>(
        builder: (context, sessionViewModel, _) {
          switch (sessionViewModel.state) {
            case SessionState.loading:
              return const Center(child: CircularProgressIndicator());
              
            case SessionState.active:
              return _buildActiveSession(sessionViewModel);
              
            case SessionState.paused:
              return _buildPausedSession(sessionViewModel);
              
            case SessionState.completed:
              return _buildCompletedSession(sessionViewModel);
              
            case SessionState.error:
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${sessionViewModel.errorMessage ?? "Desconocido"}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => sessionViewModel.startSession(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
              
            case SessionState.initial:
            default:
              return const Center(child: Text('Iniciando sesión...'));
          }
        },
      ),
    );
  }
  
  Widget _buildActiveSession(SessionViewModel viewModel) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Partida en progreso...',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _formatDuration(viewModel.elapsedSeconds),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildShotCounter(
                    label: 'Aciertos',
                    count: viewModel.successfulShots,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 24),
                  _buildShotCounter(
                    label: 'Fallos',
                    count: viewModel.missedShots,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
        
        const Expanded(
          child: CameraView(),
        ),
        
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => viewModel.endSession(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Finalizar'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => viewModel.pauseSession(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Pausar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildPausedSession(SessionViewModel viewModel) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'En pausa...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _formatDuration(viewModel.elapsedSeconds),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShotCounter(
                label: 'Aciertos',
                count: viewModel.successfulShots,
                color: Colors.green,
              ),
              const SizedBox(width: 24),
              _buildShotCounter(
                label: 'Fallos',
                count: viewModel.missedShots,
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => viewModel.resumeSession(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Reanudar'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCompletedSession(SessionViewModel viewModel) {
    final session = viewModel.currentSession;
    if (session == null) {
      return const Center(child: Text('Error: Sesión no disponible'));
    }
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: Colors.green,
            size: 72,
          ),
          const SizedBox(height: 16),
          const Text(
            '¡Sesión completada!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Duración: ${_formatDuration(session.durationInSeconds)}',
            style: const TextStyle(
              fontSize: 18,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShotCounter(
                label: 'Aciertos',
                count: session.successfulShots,
                color: Colors.green,
              ),
              const SizedBox(width: 24),
              _buildShotCounter(
                label: 'Fallos',
                count: session.missedShots,
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Efectividad: ${session.successRate.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              // Volver a la pantalla de dashboard
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text('Volver al menú principal'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              // Ver los clips
              // Implementar pantalla de galería de clips
            },
            child: const Text('Ver clips guardados'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildShotCounter({
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
  
  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours.toString().padLeft(1, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    
    return hours == '0' ? '$minutes:$secs' : '$hours:$minutes:$secs';
  }
} 