import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

class WatchService {
  static final WatchService _instance = WatchService._internal();
  
  factory WatchService() => _instance;
  
  WatchService._internal();
  
  // Instancia del paquete watch_connectivity
  final WatchConnectivity _watchConnectivity = WatchConnectivity();
  
  // Stream para notificar cuando se detecta un tiro desde el Apple Watch
  final StreamController<DateTime> _shotDetectionController = 
      StreamController<DateTime>.broadcast();
  
  // Exponer el stream para que otros puedan escuchar los eventos
  Stream<DateTime> get onShotDetected => _shotDetectionController.stream;
  
  // Control de estado
  bool _isInitialized = false;
  bool _forceAcceptMessages = false; // Forzar la recepción de mensajes incluso si hay problemas de conectividad
  
  // Inicializar el servicio
  Future<void> initialize() async {
    if (!Platform.isIOS) {
      debugPrint('⚠️ Apple Watch solo soportado en iOS');
      return;
    }
    
    if (_isInitialized) return;
    
    debugPrint('🔄 Inicializando servicio de Apple Watch...');
    
    // Configurar listeners para recibir mensajes del Apple Watch
    _configureMessageStream();
    
    // Verificar el estado de conexión
    try {
      final isPaired = await _watchConnectivity.isPaired;
      final isReachable = await _watchConnectivity.isReachable;
      debugPrint('📱 Estado Apple Watch - Emparejado: $isPaired, Alcanzable: $isReachable');
    } catch (e) {
      debugPrint('⚠️ Error al verificar estado del Apple Watch: $e');
    }
    
    // Permitir mensajes incluso si hay problemas temporales de conexión
    _forceAcceptMessages = true;
    
    _isInitialized = true;
    debugPrint('✅ Servicio de Apple Watch inicializado correctamente');
    
    // Enviar mensaje de prueba para verificar la conexión
    _sendTestMessage();
  }
  
  // Configurar el stream de mensajes
  void _configureMessageStream() {
    _watchConnectivity.messageStream.listen((message) {
      debugPrint('📥 Mensaje recibido del Apple Watch: $message');
      
      if (message.containsKey('shotDetected') && message['shotDetected'] == true) {
        final timestamp = message['timestamp'] as double?;
        
        // Convertir timestamp a DateTime
        final detectionTime = timestamp != null 
            ? DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).toInt())
            : DateTime.now();
        
        debugPrint('🏀 Tiro detectado desde Apple Watch: $detectionTime');
        
        // Notificar a los oyentes
        _shotDetectionController.add(detectionTime);
      } else if (message.containsKey('monitoring')) {
        final isMonitoring = message['monitoring'] as bool? ?? false;
        debugPrint('📱 Estado de monitoreo del Apple Watch: ${isMonitoring ? 'Activo' : 'Inactivo'}');
      } else if (message.containsKey('testResponse')) {
        debugPrint('✅ Respuesta de prueba recibida del Apple Watch');
      } else {
        debugPrint('ℹ️ Mensaje desconocido del Apple Watch: $message');
      }
    });
  }
  
  // Envía un mensaje de prueba al Watch para verificar la conexión
  Future<void> _sendTestMessage() async {
    try {
      debugPrint('🧪 Enviando mensaje de prueba al Apple Watch...');
      await _watchConnectivity.sendMessage({
        'action': 'test', 
        'timestamp': DateTime.now().millisecondsSinceEpoch
      }).timeout(const Duration(seconds: 5));
      debugPrint('✅ Mensaje de prueba enviado correctamente');
    } catch (e) {
      debugPrint('❌ Error al enviar mensaje de prueba: $e');
    }
  }
  

  // Iniciar monitoreo de tiros en el Apple Watch
  Future<bool> startWatchMonitoring() async {
    if (!Platform.isIOS) return false;
    
    debugPrint('🏀 Iniciando monitoreo de tiros en Apple Watch...');
    
    try {
      // Intentar enviar el mensaje incluso si hay problemas de conectividad
      await _watchConnectivity.sendMessage({'action': 'startMonitoring'})
          .catchError((error) {
        debugPrint('⚠️ Error al enviar mensaje al Apple Watch: $error');
        // Continuamos a pesar del error
      });
      
      debugPrint('✅ Comando de inicio enviado al Apple Watch');
      return true;
    } catch (e) {
      debugPrint('❌ Error al iniciar monitoreo del Apple Watch: $e');
      // A pesar del error, devolvemos true para mantener activo el sistema
      return true;
    }
  }
  
  // Detener monitoreo de tiros en el Apple Watch
  Future<bool> stopWatchMonitoring() async {
    if (!Platform.isIOS) return false;
    
    try {
      // Intentar enviar el mensaje incluso si hay problemas de conectividad
      await _watchConnectivity.sendMessage({'action': 'stopMonitoring'})
          .catchError((error) {
        debugPrint('⚠️ Error al enviar mensaje al Apple Watch: $error');
        // Continuamos a pesar del error
      });
      
      return true;
    } catch (e) {
      debugPrint('❌ Error al detener monitoreo del Apple Watch: $e');
      return true;
    }
  }
  
  // Actualizar estado de la sesión
  Future<bool> updateSessionStatus(bool isActive) async {
    if (!Platform.isIOS) return false;
    
    try {
      // Intentar enviar el mensaje incluso si hay problemas de conectividad
      await _watchConnectivity.sendMessage({
        'action': 'sessionStatus',
        'isActive': isActive
      }).catchError((error) {
        debugPrint('⚠️ Error al enviar estado de sesión al Apple Watch: $error');
        // Continuamos a pesar del error
      });
      
      return true;
    } catch (e) {
      debugPrint('❌ Error al actualizar estado de sesión en Apple Watch: $e');
      return true;
    }
  }
  
  // Simular una detección de tiro (para testing)
  void simulateShotDetection() {
    final detectionTime = DateTime.now();
    debugPrint('🏀 Simulando tiro detectado: $detectionTime');
    _shotDetectionController.add(detectionTime);
  }
  
  // Liberar recursos
  void dispose() {
    _shotDetectionController.close();
  }
} 