import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../bluetooth/bluetooth_view_model.dart';

enum ConnectivityStatus {
  connected, // Verde - Todo bien
  warning, // Amarillo - Parcialmente conectado
  disconnected, // Rojo - Desconectado
  unknown, // Estado desconocido
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
  bool _esp32Connected = false;
  bool _isInitialized = false;

  // Timer para verificaciones periódicas
  Timer? _statusCheckTimer;

  // Referencia al BluetoothViewModel para obtener estados
  BluetoothViewModel? _bluetoothViewModel;

  // Getters
  bool get isEsp32Connected => _esp32Connected;
  bool get isInitialized => _isInitialized;

  // Estados combinados
  ConnectivityStatus get esp32Status =>
      _esp32Connected
          ? ConnectivityStatus.connected
          : ConnectivityStatus.disconnected;

  ConnectivityStatus get overallStatus {
    return _esp32Connected
        ? ConnectivityStatus.connected
        : ConnectivityStatus.disconnected;
  }

  // Configurar referencia al BluetoothViewModel
  void setBluetoothViewModel(BluetoothViewModel bluetoothViewModel) {
    _bluetoothViewModel = bluetoothViewModel;
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
    if (_bluetoothViewModel != null) {
      final esp32Connected = _bluetoothViewModel!.isEsp32Connected;

      if (_esp32Connected != esp32Connected) {
        _esp32Connected = esp32Connected;
        debugPrint(
          '🔵 Estado ESP32 actualizado: ${esp32Connected ? 'Conectado' : 'Desconectado'}',
        );
        notifyListeners();
      }
    }
  }

  // Actualizar estado del ESP32 desde el ViewModel
  void updateEsp32Status(bool connected) {
    if (_esp32Connected != connected) {
      _esp32Connected = connected;
      debugPrint(
        '🔵 Estado ESP32 actualizado: ${connected ? 'Conectado' : 'Desconectado'}',
      );
      notifyListeners();
    }
  }

  // Mantener compatibilidad con el método anterior
  void updateBluetoothStatus(bool connected) {
    updateEsp32Status(connected);
  }

  // Forzar verificación de estado
  Future<void> forceCheck() async {
    await _checkConnectivityStatus();
  }

  // Obtener información detallada del ESP32
  ConnectivityInfo getEsp32Info() {
    if (_esp32Connected) {
      return ConnectivityInfo(
        status: ConnectivityStatus.connected,
        title: 'Sensor ESP32',
        description: 'Conectado y funcionando',
        details: [
          '✅ Dispositivo SmartShot ESP32 conectado',
          '✅ Recibiendo datos del sensor',
          '✅ Listo para detectar tiros',
        ],
      );
    } else {
      return ConnectivityInfo(
        status: ConnectivityStatus.disconnected,
        title: 'Sensor ESP32',
        description: 'No conectado',
        details: [
          '❌ Dispositivo SmartShot ESP32 no encontrado',
          '• Verifica que el sensor esté encendido',
          '• Asegúrate de que el Bluetooth esté habilitado',
          '• Mantén el dispositivo cerca del sensor',
        ],
      );
    }
  }

  // Obtener información del Bluetooth (mantener compatibilidad)
  ConnectivityInfo getBluetoothInfo() {
    return getEsp32Info();
  }

  // Verificar si se puede iniciar una sesión
  bool canStartSession() {
    return _esp32Connected;
  }

  // Obtener mensaje de error para sesión
  String getSessionBlockMessage() {
    if (!_esp32Connected) {
      return 'Necesitas conectar el sensor ESP32 para comenzar una sesión';
    }
    return 'El sensor ESP32 debe estar conectado para iniciar una sesión';
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    super.dispose();
  }
}
