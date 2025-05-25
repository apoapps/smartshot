import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/sessions/view_model/session_view_model.dart';
import '../../shared/bluetooth/bluetooth_view_model.dart';
import '../../camera/camera_view.dart';
import 'package:intl/intl.dart';
import '../../shared/sessions/data/session_model.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  // Variables to track sensor data changes
  int _initialArduinoShotCount = 0;
  int _lastArduinoShotCount = 0;
  int _sessionShotCount = 0;
  
  @override
  void initState() {
    super.initState();
    // Iniciar la sesión cuando se carga la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessionViewModel = Provider.of<SessionViewModel>(context, listen: false);
      final bluetoothViewModel = Provider.of<BluetoothViewModel>(context, listen: false);
      
      // Save initial Arduino shot count as baseline
      _initialArduinoShotCount = bluetoothViewModel.aciertos;
      _lastArduinoShotCount = _initialArduinoShotCount;
      
      debugPrint('Session starting with initial Arduino shot count: $_initialArduinoShotCount');
      
      // Start session
      sessionViewModel.startSession();
      
      // Listen for Bluetooth updates
      bluetoothViewModel.addListener(_handleBluetoothUpdates);
    });
  }
  
  @override
  void dispose() {
    // Remove listener when widget is destroyed
    Provider.of<BluetoothViewModel>(context, listen: false)
        .removeListener(_handleBluetoothUpdates);
    super.dispose();
  }
  
  void _handleBluetoothUpdates() {
    final bluetoothViewModel = Provider.of<BluetoothViewModel>(context, listen: false);
    final sessionViewModel = Provider.of<SessionViewModel>(context, listen: false);
    
    // If session is not active, do nothing
    if (!sessionViewModel.isSessionActive) return;
    
    // COMENTADO: Ya no necesitamos detectar tiros aquí porque CameraViewModel
    // se encarga de detectar y registrar tiros con videos automáticamente
    
    // Only track changes in Arduino shot counter from JSON
    // final currentArduinoShotCount = bluetoothViewModel.aciertos;
    
    // Only increase if the count actually increases
    // if (currentArduinoShotCount > _lastArduinoShotCount) {
    //   // Calculate how many new shots were detected
    //   final newShotsCount = currentArduinoShotCount - _lastArduinoShotCount;
    //   _lastArduinoShotCount = currentArduinoShotCount;
    //   
    //   // Register each new shot detected
    //   for (int i = 0; i < newShotsCount; i++) {
    //     _registerSuccessfulShot(sessionViewModel);
    //   }
    //   
    //   debugPrint('Shot detected! Arduino count: $_lastArduinoShotCount (Session shots: $_sessionShotCount)');
    // }
  }
  
  void _registerSuccessfulShot(SessionViewModel sessionViewModel) {
    // COMENTADO: Ya no necesario - CameraViewModel registra los tiros
    // // Increment session shot counter
    // _sessionShotCount++;
    // 
    // // Register the shot in the session view model
    // sessionViewModel.registerShot(
    //   isSuccessful: true,
    //   videoPath: '', // Ideally get this from the camera
    //   detectionType: ShotDetectionType.sensor,
    //   confidenceScore: 1.0,
    // );
    // 
    // debugPrint('Successful shot registered! Session shot count: $_sessionShotCount');
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
              errorBuilder:
                  (context, error, stackTrace) => const Icon(
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
                    color:
                        viewModel.isConnected
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Game in progress...',
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
                    label: 'Successful',
                    count: viewModel.successfulShots,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 24),
                  _buildShotCounter(
                    label: 'Missed',
                    count: viewModel.missedShots,
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(
          width: double.infinity,
          height: 400,
          child: Positioned(left: 0, right: 0, child: CameraView()),
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
                  child: const Text('Finish'),
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
                  child: const Text('Pause'),
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
            'Paused...',
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
                label: 'Successful',
                count: viewModel.successfulShots,
                color: Colors.green,
              ),
              const SizedBox(width: 24),
              _buildShotCounter(
                label: 'Missed',
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
            label: const Text('Resume'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
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
