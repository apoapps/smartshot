import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/sessions/view_model/session_view_model.dart';
import '../../shared/sessions/data/session_model.dart';
import 'package:intl/intl.dart';

class SessionsHistoryScreen extends StatefulWidget {
  const SessionsHistoryScreen({super.key});

  @override
  State<SessionsHistoryScreen> createState() => _SessionsHistoryScreenState();
}

class _SessionsHistoryScreenState extends State<SessionsHistoryScreen> {
  List<SessionModel> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      setState(() => _isLoading = true);
      
      final sessionViewModel = Provider.of<SessionViewModel>(context, listen: false);
      _sessions = await sessionViewModel.getAllSessions();
      
      // Ordenar sesiones por fecha (más reciente primero)
      _sessions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar las sesiones: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
  
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSessions,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sports_basketball, color: Colors.grey, size: 64),
            const SizedBox(height: 16),
            const Text(
              'No hay sesiones registradas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comienza a entrenar para registrar tus progresos',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: _sessions.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        return _buildSessionCard(session);
      },
    );
  }
  
  Widget _buildSessionCard(SessionModel session) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy', 'es_ES');
    final timeFormat = DateFormat('HH:mm', 'es_ES');
    final formattedDate = dateFormat.format(session.dateTime);
    final formattedTime = timeFormat.format(session.dateTime);
    
    final Duration duration = Duration(seconds: session.durationInSeconds);
    final formattedDuration = _formatDuration(session.durationInSeconds);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: const Color(0xFF1E1E1E),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showSessionDetails(session),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedDate,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    formattedTime,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.timer, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Duración: $formattedDuration',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.sports_basketball, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Tiros: ${session.totalShots}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatsRow(session),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: session.successRate / 100,
                backgroundColor: Colors.red.shade700.withOpacity(0.3),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade700),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Efectividad: ${session.successRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: session.successRate > 50 ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatsRow(SessionModel session) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          count: session.successfulShots,
          label: 'Aciertos',
          color: Colors.green,
        ),
        _buildStatItem(
          count: session.missedShots,
          label: 'Fallos',
          color: Colors.red,
        ),
      ],
    );
  }
  
  Widget _buildStatItem({
    required int count,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
  
  void _showSessionDetails(SessionModel session) {
    // Implementar vista detallada de la sesión con clips
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SessionDetailScreen(session: session),
      ),
    );
  }
  
  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    
    return hours > 0 
        ? '$hours h $minutes min'
        : '$minutes min $secs s';
  }
}

class SessionDetailScreen extends StatelessWidget {
  final SessionModel session;
  
  const SessionDetailScreen({super.key, required this.session});
  
  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, d MMMM yyyy • HH:mm', 'es_ES');
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Detalles de sesión'),
        backgroundColor: const Color(0xFF1E1E1E),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(
                          dateFormat.format(session.dateTime),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    _buildStatRow(
                      'Duración:',
                      _formatDuration(session.durationInSeconds),
                      Icons.timer,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Tiros totales:',
                      session.totalShots.toString(),
                      Icons.sports_basketball,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Aciertos:',
                      session.successfulShots.toString(),
                      Icons.check_circle,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Fallos:',
                      session.missedShots.toString(),
                      Icons.cancel,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Efectividad:',
                      '${session.successRate.toStringAsFixed(1)}%',
                      Icons.percent,
                      color: _getEffectivityColor(session.successRate),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            const Text(
              'Clips guardados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 16),
            
            if (session.shotClips.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'No hay clips disponibles para esta sesión',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              _buildClipsList(session.shotClips),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatRow(
    String label,
    String value,
    IconData icon, {
    Color color = Colors.white,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
  
  Widget _buildClipsList(List<ShotClip> clips) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: clips.length,
      itemBuilder: (context, index) {
        final clip = clips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            leading: Icon(
              clip.isSuccessful ? Icons.check_circle : Icons.cancel,
              color: clip.isSuccessful ? Colors.green : Colors.red,
            ),
            title: Text(
              clip.isSuccessful ? 'Tiro acertado' : 'Tiro fallado',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              DateFormat('HH:mm:ss').format(clip.timestamp),
              style: const TextStyle(color: Colors.white70),
            ),
            trailing: Icon(
              _getDetectionTypeIcon(clip.detectionType),
              color: Colors.white70,
              size: 18,
            ),
            onTap: () {
              // Implementar visualización del clip
            },
          ),
        );
      },
    );
  }
  
  IconData _getDetectionTypeIcon(ShotDetectionType type) {
    switch (type) {
      case ShotDetectionType.sensor:
        return Icons.sensors;
      case ShotDetectionType.camera:
        return Icons.camera_alt;
      case ShotDetectionType.manual:
        return Icons.person;
    }
  }
  
  Color _getEffectivityColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 60) return Colors.lightGreen;
    if (rate >= 40) return Colors.yellow;
    if (rate >= 20) return Colors.orange;
    return Colors.red;
  }
  
  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    
    return hours > 0 
        ? '$hours h $minutes min $secs s'
        : '$minutes min $secs s';
  }
} 