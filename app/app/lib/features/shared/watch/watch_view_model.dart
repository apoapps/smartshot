import 'package:flutter/foundation.dart';
import 'dart:async';
import 'watch_session_service.dart';

class WatchViewModel extends ChangeNotifier {
  bool shotDetected = false;
  final WatchSessionService _watchService = WatchSessionService();
  Timer? _resetTimer;

  WatchViewModel() {
    _watchService.shotDetected.listen((_) {
      _handleShotDetection();
    });
  }

  /// Maneja la detección de un tiro (desde el reloj o manualmente)
  void _handleShotDetection() {
    shotDetected = true;
    notifyListeners();
    
    // Auto-reset después de 3 segundos
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 3), () {
      reset();
    });
  }

  /// Resetea el estado de detección
  void reset() {
    if (shotDetected) {
      shotDetected = false;
      notifyListeners();
    }
  }

  /// Envía manualmente un evento de tiro al Apple Watch
  /// y también activa la detección en la app
  Future<void> sendShotToWatch() async {
    await _watchService.sendShotToWatch();
    _handleShotDetection(); // También activamos la detección en la app
  }
  
  /// Simula una detección de tiro sin usar el Apple Watch
  void simulateShotDetection() {
    _handleShotDetection();
  }
  
  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
} 