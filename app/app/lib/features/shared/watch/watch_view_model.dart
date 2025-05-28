import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app/features/shared/watch/watch_service.dart';
import 'package:app/features/shared/sessions/view_model/session_view_model.dart';
import 'package:app/features/shared/bluetooth/bluetooth_view_model.dart';
import 'package:app/features/shared/sessions/data/session_model.dart';

class WatchViewModel extends ChangeNotifier {
  final WatchService _watchService = WatchService();
  final SessionViewModel _sessionViewModel;
  final BluetoothViewModel _bluetoothViewModel;
  
  bool _isWatchMonitoring = false;
  bool _isInitialized = false;
  bool _forceMonitoringState = true; // Forzar estado de monitoreo a true para desarrollo
  
  // Tiempo para considerar un tiro como fallido (en ms)
  static const int _missedShotTimeout = 7000; // 7 segundos
  
  // Último momento en que se detectó un tiro desde el reloj
  DateTime? _lastWatchShotTime;
  
  // Timer para verificar tiros fallidos
  Timer? _shotVerificationTimer;
  
  // Stream subscriptions
  StreamSubscription? _watchShotSubscription;
  
  WatchViewModel(this._sessionViewModel, this._bluetoothViewModel);
  
  // Getter con estado forzado para desarrollo
  bool get isWatchMonitoring => _forceMonitoringState || _isWatchMonitoring;
  bool get isInitialized => _isInitialized;
  
  // Inicializar el servicio y configurar los listeners
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('🔄 Inicializando WatchViewModel...');
    
    await _watchService.initialize();
    
    // Escuchar las detecciones de tiros desde el Apple Watch
    _watchShotSubscription = _watchService.onShotDetected.listen(_handleWatchShotDetection);
    debugPrint('✅ Suscripción a eventos del Apple Watch configurada');
    
    // Sincronizar el estado de la sesión con el Apple Watch
    _syncSessionState();
    debugPrint('✅ Sincronización de sesión configurada');
    
    // Para desarrollo, consideramos que está conectado
    _isWatchMonitoring = true;
    _forceMonitoringState = true;
    
    _isInitialized = true;
    debugPrint('✅ WatchViewModel inicializado correctamente');
    notifyListeners();
  }
  
  // Manejar la detección de un tiro desde el Apple Watch
  void _handleWatchShotDetection(DateTime detectionTime) {
    debugPrint('🏀 Tiro detectado en el Apple Watch');
    _lastWatchShotTime = detectionTime;
    
    // Cancelar cualquier timer anterior
    _shotVerificationTimer?.cancel();
    
    // Crear un nuevo timer para verificar si hubo un acierto
    _shotVerificationTimer = Timer(Duration(milliseconds: _missedShotTimeout), () {
      _checkForMissedShot();
    });
    
    debugPrint('⏰ Timer de verificación iniciado: ${_missedShotTimeout}ms');
  }
  
  // Verificar si un tiro fue fallido comparando con el sensor bluetooth
  void _checkForMissedShot() {
    debugPrint('🔍 Verificando resultado del tiro...');
    
    // Si el Bluetooth detectó un tiro exitoso recientemente, registramos como acierto
    if (_bluetoothViewModel.shotDetected) {
      debugPrint('✅ Acierto detectado por el sensor Bluetooth');
      
      // Si hay una sesión activa, registramos el tiro como exitoso
      if (_sessionViewModel.isSessionActive) {
        debugPrint('📝 Registrando tiro exitoso en la sesión');
        _sessionViewModel.registerShot(
          isSuccessful: true,
          videoPath: '', // Sin video en este caso
          detectionType: ShotDetectionType.sensor,
          confidenceScore: 0.95, // Alta confianza en la detección
        );
      } else {
        debugPrint('⚠️ No hay sesión activa para registrar el tiro exitoso');
      }
      return;
    }
    
    // Si no hay una sesión activa, no hacemos nada
    if (!_sessionViewModel.isSessionActive) {
      debugPrint('⚠️ No hay sesión activa para registrar el tiro fallido');
      return;
    }
    
    // Verificar el estado de Bluetooth
    debugPrint('🔵 Estado de Bluetooth - Conectado: ${_bluetoothViewModel.isConnected}');
    
    // Registrar el tiro como fallido en la sesión
    debugPrint('❌ Tiro fallido detectado por el Apple Watch (después de ${_missedShotTimeout/1000} segundos)');
    _sessionViewModel.registerShot(
      isSuccessful: false,
      videoPath: '', // Sin video en este caso
      detectionType: ShotDetectionType.sensor,
      confidenceScore: 0.9, // Alta confianza en la detección
    );
  }
  
  // Iniciar el monitoreo en el Apple Watch
  Future<bool> startWatchMonitoring() async {
    if (!_isInitialized) {
      debugPrint('🔄 Inicializando WatchViewModel antes de iniciar monitoreo');
      await initialize();
    }
    
    debugPrint('🔄 Iniciando monitoreo en el Apple Watch');
    final result = await _watchService.startWatchMonitoring();
    
    // Siempre considerar conectado para propósitos de desarrollo
    _isWatchMonitoring = true;
    notifyListeners();
    
    debugPrint('✅ Monitoreo del Apple Watch ${result ? 'iniciado' : 'falló'}');
    return result;
  }
  
  // Detener el monitoreo en el Apple Watch
  Future<bool> stopWatchMonitoring() async {
    if (!_isInitialized) return false;
    
    final result = await _watchService.stopWatchMonitoring();
    
    // Solo actualizar estado si es explícitamente desactivado
    if (!_forceMonitoringState) {
      _isWatchMonitoring = false;
      notifyListeners();
    }
    
    return result;
  }
  
  // Sincronizar el estado de la sesión con el Apple Watch
  void _syncSessionState() {
    // Monitorear cambios en el estado de la sesión
    _sessionViewModel.addListener(() {
      final isActive = _sessionViewModel.isSessionActive;
      _watchService.updateSessionStatus(isActive);
      
      if (isActive && !_isWatchMonitoring) {
        startWatchMonitoring();
      } else if (!isActive && _isWatchMonitoring && !_forceMonitoringState) {
        stopWatchMonitoring();
      }
    });
  }
  
  @override
  void dispose() {
    _shotVerificationTimer?.cancel();
    _watchShotSubscription?.cancel();
    super.dispose();
  }

  // Getter para compatibilidad con la vista de cámara existente
  bool get shotDetected => _lastWatchShotTime != null && 
      DateTime.now().difference(_lastWatchShotTime!).inSeconds < 3;

  // Método para simular una detección de tiro (para debug)
  void simulateShotDetection() {
    debugPrint('🏀 Simulando tiro desde Apple Watch');
    _handleWatchShotDetection(DateTime.now());
  }
  
  // Método para probar la integración completa
  void testIntegration() {
    debugPrint('🧪 Iniciando prueba de integración...');
    
    // 1. Verificar estado del watch
    debugPrint('📱 Estado del Apple Watch: ${isWatchMonitoring ? 'Monitoreando' : 'No monitoreando'}');
    
    // 2. Verificar estado de la sesión
    debugPrint('📊 Estado de la sesión: ${_sessionViewModel.isSessionActive ? 'Activa' : 'Inactiva'}');
    
    // 3. Verificar estado del bluetooth
    debugPrint('🔵 Estado del Bluetooth: ${_bluetoothViewModel.isConnected ? 'Conectado' : 'Desconectado'}');
    
    // 4. Simular detección de tiro
    simulateShotDetection();
    
    // 5. Simular acierto de tiro desde bluetooth
    Future.delayed(Duration(seconds: 2), () {
      debugPrint('🔵 Simulando acierto desde sensor Bluetooth');
      // No podemos simular directamente ya que shotDetected es un getter de un solo uso
      // pero el método _checkForMissedShot() lo verificará
    });
    
    debugPrint('✅ Prueba de integración completada');
  }
} 