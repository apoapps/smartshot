import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:app/features/shared/sessions/view_model/session_view_model.dart';
import 'package:app/features/shared/sessions/data/session_model.dart';
import 'package:app/features/shared/sessions/view/session_detail_view.dart';
import 'package:app/features/shared/sessions/view/video_player_view.dart';

class SessionsListView extends StatefulWidget {
  const SessionsListView({Key? key}) : super(key: key);

  @override
  State<SessionsListView> createState() => _SessionsListViewState();
}

class _SessionsListViewState extends State<SessionsListView> {
  @override
  void initState() {
    super.initState();
    // Cargar sesiones al inicializar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionViewModel>().loadSessions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Sesiones'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<SessionViewModel>().loadSessions();
            },
          ),
        ],
      ),
      body: Consumer<SessionViewModel>(
        builder: (context, sessionViewModel, child) {
          if (sessionViewModel.isLoading) {
            return const Center(
              child: CircularProgressIndicator(
                color: Colors.orange,
              ),
            );
          }

          if (sessionViewModel.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar sesiones',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sessionViewModel.error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      sessionViewModel.loadSessions();
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          if (sessionViewModel.sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.sports_basketball,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay sesiones guardadas',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inicia una nueva sesión de entrenamiento para comenzar',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sessionViewModel.sessions.length,
            itemBuilder: (context, index) {
              final session = sessionViewModel.sessions[index];
              return _SessionCard(
                session: session,
                onTap: () => _openSessionDetail(context, session),
                onDelete: () => _showDeleteDialog(context, session),
              );
            },
          );
        },
      ),
      floatingActionButton: Consumer<SessionViewModel>(
        builder: (context, sessionViewModel, child) {
          // Mostrar estadísticas globales
          final stats = sessionViewModel.getGlobalStats();
          
          return FloatingActionButton.extended(
            onPressed: () => _showGlobalStats(context, stats),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.analytics),
            label: Text('${stats['totalSessions']} Sesiones'),
          );
        },
      ),
    );
  }

  void _openSessionDetail(BuildContext context, SessionModel session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionDetailView(session: session),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, SessionModel session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Sesión'),
        content: Text(
          '¿Estás seguro de que quieres eliminar la sesión del ${DateFormat('dd/MM/yyyy HH:mm').format(session.dateTime)}?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<SessionViewModel>().deleteSession(session.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showGlobalStats(BuildContext context, Map<String, dynamic> stats) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Estadísticas Globales'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatRow('Total de sesiones:', '${stats['totalSessions']}'),
            _StatRow('Total de tiros:', '${stats['totalShots']}'),
            _StatRow('Tiros exitosos:', '${stats['totalSuccessfulShots']}'),
            _StatRow('Porcentaje de acierto:', '${stats['globalSuccessRate'].toStringAsFixed(1)}%'),
            _StatRow('Tiempo total jugado:', _formatDuration(stats['totalPlayTime'])),
            _StatRow('Duración promedio:', _formatDuration(stats['averageSessionDuration'])),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}

class _SessionCard extends StatelessWidget {
  final SessionModel session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy HH:mm').format(session.dateTime),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  PopupMenuButton(
                    icon: const Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        onTap: onDelete,
                        child: const Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Eliminar'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatChip(
                    icon: Icons.sports_basketball,
                    label: 'Tiros',
                    value: '${session.totalShots}',
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    icon: Icons.check_circle,
                    label: 'Aciertos',
                    value: '${session.successfulShots}',
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    icon: Icons.percent,
                    label: 'Precisión',
                    value: '${session.successRate.toStringAsFixed(1)}%',
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatSessionDuration(session.durationInSeconds),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${session.shotClips.length} clips de video',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
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

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSessionDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final secs = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
} 