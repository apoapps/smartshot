import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import '../bluetooth/bluetooth_view_model.dart';
import '../watch/watch_service.dart';

enum ConnectivityStatus {
  connected,      // Verde - Todo bien
  warning,        // Amarillo - Parcialmente conectado
  disconnected,   // Rojo - Desconectado
  unknown         // Gris - Estado desconocido
}

class ConnectivityInfo {
  final ConnectivityStatus status;
  final String title;
  final String description;
  final List<String> details;

  ConnectivityInfo({
    required this.status,
    required this.title,
    required this.description,
    required this.details,
  });
}

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  // Estados de conexión
  bool _bluetoothConnected = false;
  bool _watchPaired = false;
  bool _watchReachable = false;
  bool _watchAppCommunicating = false;
  bool _isInitialized = false;

  // Timer para verificaciones periódicas
  Timer? _statusCheckTimer;

  // Getters
  bool get isBluetoothConnected => _bluetoothConnected;
  bool get isWatchPaired => _watchPaired;
  bool get isWatchReachable => _watchReachable;
  bool get isWatchAppCommunicating => _watchAppCommunicating;
  bool get isInitialized => _isInitialized;

  // Estados combinados
  ConnectivityStatus get bluetoothStatus => _bluetoothConnected 
      ? ConnectivityStatus.connected 
      : ConnectivityStatus.disconnected;
  
  ConnectivityStatus get watchStatus {
    if (!_watchPaired) return ConnectivityStatus.disconnected;
    if (!_watchReachable) return ConnectivityStatus.warning;
    if (!_watchAppCommunicating) return ConnectivityStatus.warning;
    return ConnectivityStatus.connected;
  }

  ConnectivityStatus get overallStatus {
    final bluetoothOk = _bluetoothConnected;
    final watchOk = _watchPaired && _watchReachable && _watchAppCommunicating;
    
    if (bluetoothOk && watchOk) return ConnectivityStatus.connected;
    if (bluetoothOk || watchOk) return ConnectivityStatus.warning;
    return ConnectivityStatus.disconnected;
  }

  // Inicializar el servicio
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('🔄 Inicializando ConnectivityService...');
    
    // Verificar estado inicial
    await _checkConnectivityStatus();
    
    // Configurar verificaciones periódicas cada 5 segundos
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnectivityStatus();
    });
    
    _isInitialized = true;
    debugPrint('✅ ConnectivityService inicializado');
  }

  // Verificar estados de conectividad
  Future<void> _checkConnectivityStatus() async {
    await _checkBluetoothStatus();
    await _checkWatchStatus();
    notifyListeners();
  }

  // Verificar estado del Bluetooth
  Future<void> _checkBluetoothStatus() async {
    // Nota: Este método será llamado desde el BluetoothViewModel
    // para actualizar el estado cuando cambie
  }

  // Verificar estado del Apple Watch
  Future<void> _checkWatchStatus() async {
    if (!Platform.isIOS) {
      _watchPaired = false;
      _watchReachable = false;
      _watchAppCommunicating = false;
      return;
    }

    try {
      final WatchConnectivity watchConnectivity = WatchConnectivity();
      
      // Verificar si está emparejado
      _watchPaired = await watchConnectivity.isPaired;
      
      // Verificar si está alcanzable
      _watchReachable = await watchConnectivity.isReachable;
      
      // Verificar comunicación con la app del watch
      if (_watchPaired && _watchReachable) {
        await _testWatchAppCommunication();
      } else {
        _watchAppCommunicating = false;
      }
      
      debugPrint('📱 Estado Watch - Emparejado: $_watchPaired, Alcanzable: $_watchReachable, App comunicando: $_watchAppCommunicating');
      
    } catch (e) {
      debugPrint('❌ Error verificando estado del Watch: $e');
      _watchPaired = false;
      _watchReachable = false;
      _watchAppCommunicating = false;
    }
  }

  // Probar comunicación con la app del watch
  Future<void> _testWatchAppCommunication() async {
    try {
      final WatchConnectivity watchConnectivity = WatchConnectivity();
      
      // Simplificar el test de comunicación sin timeout complejo
      try {
        // Enviar mensaje simple sin esperar respuesta
        await watchConnectivity.sendMessage({
          'action': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch
        });
        
        // Si no hay excepción, asumimos que la comunicación funciona
        _watchAppCommunicating = true;
        debugPrint('📱 Comunicación con app del Watch: OK');
        
      } on Exception {
        _watchAppCommunicating = false;
        debugPrint('📱 Comunicación con app del Watch: FAILED');
      }
      
    } catch (e) {
      _watchAppCommunicating = false;
      debugPrint('❌ Error en comunicación con app del Watch: $e');
    }
  }

  // Actualizar estado del Bluetooth desde el ViewModel
  void updateBluetoothStatus(bool connected) {
    if (_bluetoothConnected != connected) {
      _bluetoothConnected = connected;
      debugPrint('🔵 Estado Bluetooth actualizado: ${connected ? 'Conectado' : 'Desconectado'}');
      notifyListeners();
    }
  }

  // Forzar verificación de estado
  Future<void> forceCheck() async {
    await _checkConnectivityStatus();
  }

  // Obtener información detallada del Bluetooth
  ConnectivityInfo getBluetoothInfo() {
    if (_bluetoothConnected) {
      return ConnectivityInfo(
        status: ConnectivityStatus.connected,
        title: 'Sensor Bluetooth',
        description: 'Conectado y funcionando',
        details: [
          '✅ Dispositivo SmartShot conectado',
          '✅ Recibiendo datos del sensor',
          '✅ Listo para detectar tiros'
        ],
      );
    } else {
      return ConnectivityInfo(
        status: ConnectivityStatus.disconnected,
        title: 'Sensor Bluetooth',
        description: 'No conectado',
        details: [
          '❌ Dispositivo SmartShot no encontrado',
          '• Verifica que el sensor esté encendido',
          '• Asegúrate de que el Bluetooth esté habilitado',
          '• Mantén el dispositivo cerca del sensor'
        ],
      );
    }
  }

  // Obtener información detallada del Apple Watch
  ConnectivityInfo getWatchInfo() {
    if (!Platform.isIOS) {
      return ConnectivityInfo(
        status: ConnectivityStatus.disconnected,
        title: 'Apple Watch',
        description: 'No soportado en este dispositivo',
        details: [
          '❌ Apple Watch solo disponible en iOS',
        ],
      );
    }

    if (!_watchPaired) {
      return ConnectivityInfo(
        status: ConnectivityStatus.disconnected,
        title: 'Apple Watch',
        description: 'No emparejado',
        details: [
          '❌ Apple Watch no emparejado',
          '• Abre la app Watch en tu iPhone',
          '• Sigue el proceso de emparejamiento',
          '• Asegúrate de que ambos dispositivos estén cerca'
        ],
      );
    }

    if (!_watchReachable) {
      return ConnectivityInfo(
        status: ConnectivityStatus.warning,
        title: 'Apple Watch',
        description: 'Emparejado pero no alcanzable',
        details: [
          '⚠️ Apple Watch emparejado pero no alcanzable',
          '• Verifica que el Watch esté encendido',
          '• Asegúrate de que esté en rango',
          '• Revisa la conexión WiFi/Bluetooth'
        ],
      );
    }

    if (!_watchAppCommunicating) {
      return ConnectivityInfo(
        status: ConnectivityStatus.warning,
        title: 'Apple Watch',
        description: 'App del Watch no responde',
        details: [
          '⚠️ Apple Watch conectado pero la app no responde',
          '• Abre la app SmartShot en tu Apple Watch',
          '• Verifica que la app esté instalada',
          '• Reinicia la app del Watch si es necesario'
        ],
      );
    }

    return ConnectivityInfo(
      status: ConnectivityStatus.connected,
      title: 'Apple Watch',
      description: 'Conectado y comunicando',
      details: [
        '✅ Apple Watch emparejado',
        '✅ Dispositivo alcanzable',
        '✅ App SmartShot respondiendo',
        '✅ Listo para detectar tiros'
      ],
    );
  }

  // Verificar si se puede iniciar una sesión
  bool canStartSession() {
    // Requiere al menos Bluetooth O Watch funcionales
    return _bluetoothConnected || (_watchPaired && _watchReachable && _watchAppCommunicating);
  }

  // Obtener mensaje de error para sesión
  String getSessionBlockMessage() {
    if (!_bluetoothConnected && !_watchPaired) {
      return 'Necesitas conectar el sensor Bluetooth o emparejar el Apple Watch para comenzar una sesión';
    }
    if (!_bluetoothConnected && !_watchAppCommunicating) {
      return 'El Apple Watch está emparejado pero la app SmartShot no está respondiendo. Ábrela en tu Watch o conecta el sensor Bluetooth';
    }
    return 'Al menos un dispositivo debe estar conectado para iniciar una sesión';
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
} 