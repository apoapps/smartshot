import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/sessions/view_model/session_view_model.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../camera/camera_view.dart';
import '../../camera/camera_view_model.dart';
import 'package:intl/intl.dart';
import '../../shared/sessions/data/session_model.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  CameraViewModel? _cameraViewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessionViewModel = Provider.of<SessionViewModel>(context, listen: false);
      
      // Crear e inicializar el camera view model
      _cameraViewModel = CameraViewModel(sessionViewModel: sessionViewModel);
      
      // Iniciar la sesión
      sessionViewModel.startSession();
      
      debugPrint('Sesión iniciada con nueva cámara simplificada');
    });
  }

  @override
  void dispose() {
    _cameraViewModel?.dispose();
    super.dispose();
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
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.sports_basketball,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Text('SmartShot', style: TextStyle(color: Colors.white)),
            const Spacer(),
            Consumer<BluetoothViewModel>(
              builder: (context, viewModel, _) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: viewModel.isConnected
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    border: Border.all(
                      color: viewModel.isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Text(
                    viewModel.isConnected ? 'Connected' : 'Disconnected',
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
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${sessionViewModel.errorMessage ?? "Unknown"}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => sessionViewModel.startSession(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );

            case SessionState.initial:
            default:
              return const Center(child: Text('Starting session...'));
          }
        },
      ),
    );
  }

  Widget _buildActiveSession(SessionViewModel viewModel) {
    return SafeArea(
      child: Stack(
        children: [
          // Fondo de cámara a pantalla completa
          Positioned.fill(
            child: _cameraViewModel != null
                ? ChangeNotifierProvider<CameraViewModel>.value(
                    value: _cameraViewModel!,
                    child: const CameraView(
                      isBackground: true,
                      backgroundOpacity: 0.7, // 70% visible, 30% oscuro
                    ),
                  )
                : Container(
                    color: Colors.black,
                  ),
          ),
          
          // Contenido principal
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header con información de la sesión
                  Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(20.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Sesión en progreso...',
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
                              label: 'Exitosos',
                              count: viewModel.successfulShots,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 24),
                            _buildShotCounter(
                              label: 'Fallados',
                              count: viewModel.missedShots,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Espacio flexible para empujar los botones hacia abajo
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                  ),

                  // Botones de control en la parte inferior
                  Container(
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPausedSession(SessionViewModel viewModel) {
    return SafeArea(
      child: Stack(
        children: [
          // Fondo de cámara a pantalla completa
          Positioned.fill(
            child: _cameraViewModel != null
                ? ChangeNotifierProvider<CameraViewModel>.value(
                    value: _cameraViewModel!,
                    child: const CameraView(
                      isBackground: true,
                      backgroundOpacity: 0.5, // Más oscuro cuando está pausado
                    ),
                  )
                : Container(
                    color: Colors.black,
                  ),
          ),
          
          // Contenido principal
          Positioned.fill(
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(32.0),
                padding: const EdgeInsets.all(32.0),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.orange.withOpacity(0.5),
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.pause_circle_outline,
                      size: 64,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Sesión Pausada',
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
                          label: 'Exitosos',
                          count: viewModel.successfulShots,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 24),
                        _buildShotCounter(
                          label: 'Fallados',
                          count: viewModel.missedShots,
                          color: Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => viewModel.resumeSession(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
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
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(color: Colors.white70),
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

  Widget _buildCompletedSession(SessionViewModel viewModel) {
    final session = viewModel.currentSession;
    if (session == null) {
      return const Center(child: Text('Error: Session not available'));
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 72),
          const SizedBox(height: 16),
          const Text(
            'Session completed!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Duration: ${_formatDuration(session.durationInSeconds)}',
            style: const TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShotCounter(
                label: 'Successful',
                count: session.successfulShots,
                color: Colors.green,
              ),
              const SizedBox(width: 24),
              _buildShotCounter(
                label: 'Missed',
                count: session.missedShots,
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Success Rate: ${session.successRate.toStringAsFixed(1)}%',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              // Return to dashboard screen
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text('Back to main menu'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              // View clips
              // Implement gallery view
            },
            child: const Text('View saved clips'),
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
          style: TextStyle(fontSize: 16, color: color.withOpacity(0.8)),
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
