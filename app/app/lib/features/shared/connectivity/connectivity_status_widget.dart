import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'connectivity_service.dart';

class ConnectivityStatusWidget extends StatelessWidget {
  final bool showLabels;
  final bool isCompact;

  const ConnectivityStatusWidget({
    super.key,
    this.showLabels = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, connectivityService, child) {
        if (!connectivityService.isInitialized) {
          return const SizedBox.shrink();
        }

        if (isCompact) {
          return _buildCompactView(context, connectivityService);
        } else {
          return _buildFullView(context, connectivityService);
        }
      },
    );
  }

  Widget _buildCompactView(BuildContext context, ConnectivityService service) {
    return _buildStatusIndicator(
      context,
      service.esp32Status,
      Icons.bluetooth,
      'ESP32',
      () => _showConnectivityDialog(context, service.getBluetoothInfo()),
    );
  }

  Widget _buildFullView(BuildContext context, ConnectivityService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor(service.overallStatus).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.device_hub,
                color: _getStatusColor(service.overallStatus),
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Estado de Conectividad',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Estado del Bluetooth ESP32
          GestureDetector(
            onTap:
                () => _showConnectivityDialog(
                  context,
                  service.getBluetoothInfo(),
                ),
            child: _buildStatusRow(
              'Sensor ESP32',
              service.getBluetoothInfo().description,
              service.getBluetoothInfo().status,
              Icons.bluetooth,
            ),
          ),

          // Mostrar advertencia si no se puede iniciar sesión
          if (!service.canStartSession()) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Necesitas conectar el sensor ESP32 para iniciar sesiones',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(
    BuildContext context,
    ConnectivityStatus status,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final color = _getStatusColor(status);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color.withOpacity(0.2),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            if (showLabels) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    String title,
    String description,
    ConnectivityStatus status,
    IconData icon,
  ) {
    final color = _getStatusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(description, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.info_outline, color: Colors.grey[600], size: 16),
        ],
      ),
    );
  }

  Color _getStatusColor(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.connected:
        return Colors.green;
      case ConnectivityStatus.warning:
        return Colors.orange;
      case ConnectivityStatus.disconnected:
        return Colors.red;
      case ConnectivityStatus.unknown:
        return Colors.grey;
    }
  }

  void _showConnectivityDialog(BuildContext context, ConnectivityInfo info) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: _getStatusColor(info.status).withOpacity(0.3),
              ),
            ),
            title: Row(
              children: [
                Icon(
                  info.status == ConnectivityStatus.connected
                      ? Icons.check_circle
                      : info.status == ConnectivityStatus.warning
                      ? Icons.warning
                      : Icons.error,
                  color: _getStatusColor(info.status),
                ),
                const SizedBox(width: 8),
                Text(info.title, style: const TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.description,
                  style: TextStyle(
                    color: _getStatusColor(info.status),
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                ...info.details
                    .map(
                      (detail) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          detail,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
              if (info.status != ConnectivityStatus.connected)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Forzar verificación de estado
                    Provider.of<ConnectivityService>(
                      context,
                      listen: false,
                    ).forceCheck();
                  },
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
            ],
          ),
    );
  }
}
