import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app/features/shared/sessions/data/session_model.dart';
import 'package:app/features/shared/sessions/data/session_repository.dart';

enum SessionState { initial, loading, active, paused, completed, error }

class SessionViewModel extends ChangeNotifier {
  final SessionRepository _repository;

  // Estado actual
  SessionState _state = SessionState.initial;
  bool _isLoading = false;
  String? _error;

  // Sesión activa
  SessionModel? _currentSession;
  DateTime? _sessionStartTime;
  DateTime? _sessionPauseTime;
  bool _isSessionActive = false;
  final List<ShotClip> _pendingShots = [];

  // Timer para tracking del tiempo
  Timer? _sessionTimer;
  int _elapsedSeconds = 0;

  // Lista de sesiones
  List<SessionModel> _sessions = [];

  // Video seleccionado para reproducir
  String? _selectedVideoPath;

  // Panel de debug
  bool _isDebugPanelVisible = false;
  List<String> _debugMessages = [];
  Map<String, dynamic> _sensorData = {};
  final int _maxDebugMessages = 50;

  // Control de intento de tiro
  bool _isWaitingForShotResult = false;
  Timer? _shotTimeoutTimer;
  int _previousAciertos = 0;

  // Referencia al CameraViewModel para registrar tiros con video
  dynamic
  _cameraViewModel; // Usamos dynamic para evitar dependencias circulares

  SessionViewModel(this._repository);

  /// Establece la referencia al CameraViewModel para poder registrar tiros con video
  void setCameraViewModel(dynamic cameraViewModel) {
    _cameraViewModel = cameraViewModel;
    debugPrint('📹 CameraViewModel vinculado a SessionViewModel');
  }

  // Getters
  SessionState get state => _state;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorMessage => _error; // Alias para compatibilidad
  SessionModel? get currentSession => _currentSession;
  bool get isSessionActive => _isSessionActive;
  List<SessionModel> get sessions => List.unmodifiable(_sessions);
  String? get selectedVideoPath => _selectedVideoPath;
  int get elapsedSeconds => _elapsedSeconds;
  bool get isWaitingForShotResult => _isWaitingForShotResult;

  // Getters para debug
  bool get isDebugPanelVisible => _isDebugPanelVisible;
  List<String> get debugMessages => List.unmodifiable(_debugMessages);
  Map<String, dynamic> get sensorData => Map.unmodifiable(_sensorData);

  // Stats de la sesión actual
  int get currentSessionTotalShots => _pendingShots.length;
  int get currentSessionSuccessfulShots =>
      _pendingShots.where((shot) => shot.isSuccessful).length;
  int get currentSessionMissedShots =>
      currentSessionTotalShots - currentSessionSuccessfulShots;
  double get currentSessionSuccessRate =>
      currentSessionTotalShots > 0
          ? (currentSessionSuccessfulShots / currentSessionTotalShots) * 100
          : 0.0;

  Duration get currentSessionDuration =>
      _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!)
          : Duration.zero;

  // Getters para compatibilidad con el código existente
  int get successfulShots => currentSessionSuccessfulShots;
  int get missedShots => currentSessionMissedShots;

  /// Inicia una nueva sesión de entrenamiento
  Future<void> startSession() async {
    if (_isSessionActive) return;

    _setState(SessionState.loading);
    _setLoading(true);
    _clearError();

    try {
      _sessionStartTime = DateTime.now();
      _sessionPauseTime = null;
      _isSessionActive = true;
      _pendingShots.clear();
      _elapsedSeconds = 0;

      // Iniciar timer
      _startTimer();

      _setState(SessionState.active);
      debugPrint('Nueva sesión iniciada: ${_sessionStartTime}');
      addDebugMessage(
        'Nueva sesión iniciada - ${_sessionStartTime.toString()}',
      );
    } catch (e) {
      _setError('Error al iniciar sesión: $e');
      _setState(SessionState.error);
    } finally {
      _setLoading(false);
    }
  }

  /// Pausa la sesión actual
  Future<void> pauseSession() async {
    if (!_isSessionActive || _state != SessionState.active) return;

    try {
      _sessionPauseTime = DateTime.now();
      _stopTimer();
      _setState(SessionState.paused);

      debugPrint('Sesión pausada');
    } catch (e) {
      _setError('Error al pausar sesión: $e');
      _setState(SessionState.error);
    }
  }

  /// Reanuda la sesión pausada
  Future<void> resumeSession() async {
    if (!_isSessionActive || _state != SessionState.paused) return;

    try {
      // Calcular tiempo pausado y ajustar el tiempo de inicio
      if (_sessionPauseTime != null && _sessionStartTime != null) {
        final pausedDuration = DateTime.now().difference(_sessionPauseTime!);
        _sessionStartTime = _sessionStartTime!.add(pausedDuration);
      }

      _sessionPauseTime = null;
      _startTimer();
      _setState(SessionState.active);

      debugPrint('Sesión reanudada');
    } catch (e) {
      _setError('Error al reanudar sesión: $e');
      _setState(SessionState.error);
    }
  }

  /// Finaliza la sesión actual y la guarda
  Future<void> endSession() async {
    if (!_isSessionActive || _sessionStartTime == null) return;

    _setLoading(true);
    _clearError();

    try {
      _stopTimer();

      final sessionDuration =
          _state == SessionState.paused && _sessionPauseTime != null
              ? _sessionPauseTime!.difference(_sessionStartTime!)
              : DateTime.now().difference(_sessionStartTime!);

      // Crear el modelo de sesión
      final session = SessionModel(
        dateTime: _sessionStartTime!,
        durationInSeconds: sessionDuration.inSeconds,
        totalShots: _pendingShots.length,
        successfulShots:
            _pendingShots.where((shot) => shot.isSuccessful).length,
        shotClips: List.from(_pendingShots),
      );

      // Guardar en el repositorio
      await _repository.saveSession(session);

      // Actualizar estado
      _currentSession = session;
      _isSessionActive = false;
      _sessionStartTime = null;
      _sessionPauseTime = null;
      _elapsedSeconds = 0;

      _setState(SessionState.completed);

      // Recargar la lista de sesiones
      await loadSessions();

      debugPrint('Sesión guardada: ${session.id}');
    } catch (e) {
      _setError('Error al finalizar sesión: $e');
      _setState(SessionState.error);
    } finally {
      _setLoading(false);
    }
  }

  /// Agrega un resultado de tiro (método de compatibilidad)
  Future<void> addShotResult(bool isSuccessful, double confidence) async {
    if (!_isSessionActive) {
      debugPrint('⚠️ No hay sesión activa para registrar el tiro');
      return;
    }

    try {
      // Crear un clip temporal sin video (para compatibilidad)
      final shot = ShotClip(
        timestamp: DateTime.now(),
        isSuccessful: isSuccessful,
        videoPath: '', // Sin video por ahora
        confidenceScore: confidence,
        detectionType: ShotDetectionType.camera, // Por defecto
      );

      _pendingShots.add(shot);

      debugPrint(
        '🏀 Tiro registrado: ${isSuccessful ? "ACIERTO" : "FALLO"} - Confianza: ${(confidence * 100).toStringAsFixed(1)}%',
      );
      addDebugMessage(
        'Tiro registrado: ${isSuccessful ? "ACIERTO" : "FALLO"} - Confianza: ${(confidence * 100).toStringAsFixed(1)}%',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error al agregar resultado de tiro: $e');
    }
  }

  /// Registra un tiro en la sesión activa
  Future<void> registerShot({
    required bool isSuccessful,
    required String videoPath,
    required ShotDetectionType detectionType,
    double? confidenceScore,
  }) async {
    if (!_isSessionActive) return;

    try {
      // Verificar que el archivo de video existe
      if (videoPath.isNotEmpty && !await File(videoPath).exists()) {
        debugPrint('Advertencia: Archivo de video no encontrado: $videoPath');
      }

      final shot = ShotClip(
        timestamp: DateTime.now(),
        isSuccessful: isSuccessful,
        videoPath: videoPath,
        confidenceScore: confidenceScore,
        detectionType: detectionType,
      );

      _pendingShots.add(shot);

      debugPrint(
        'Tiro registrado: ${isSuccessful ? 'Acierto' : 'Fallo'} - $detectionType',
      );
      addDebugMessage(
        'Tiro registrado: ${isSuccessful ? 'Acierto' : 'Fallo'} - $detectionType - Confianza: ${confidenceScore ?? 'N/A'}',
      );

      notifyListeners();
    } catch (e) {
      debugPrint('Error al registrar tiro: $e');
    }
  }

  /// Inicia un intento de tiro - espera 5 segundos para detectar respuesta del ESP32
  Future<void> attemptShot() async {
    if (!_isSessionActive) {
      debugPrint('⚠️ No hay sesión activa para registrar intento de tiro');
      return;
    }

    if (_isWaitingForShotResult) {
      debugPrint('⚠️ Ya hay un intento de tiro en proceso');
      return;
    }

    // Preferir CameraViewModel si está disponible para tiros con video
    if (_cameraViewModel != null) {
      debugPrint('🎥 Usando CameraViewModel para intento de tiro con video');
      try {
        _cameraViewModel.simulateShotAttempt();
        return;
      } catch (e) {
        debugPrint(
          '⚠️ Error usando CameraViewModel, fallback a modo sin video: $e',
        );
      }
    }

    debugPrint(
      '🏀 Iniciando intento de tiro SIN VIDEO - esperando 5 segundos por respuesta del ESP32...',
    );
    addDebugMessage(
      'Intento de tiro SIN VIDEO iniciado - esperando respuesta ESP32',
    );

    _isWaitingForShotResult = true;

    // Obtener el número actual de aciertos del ESP32 para detectar incrementos
    _previousAciertos = _getCurrentEsp32Aciertos();

    notifyListeners();

    // Iniciar timeout de 5 segundos
    _shotTimeoutTimer = Timer(const Duration(seconds: 5), () {
      // Si llegamos aquí, no hubo detección de acierto
      debugPrint(
        '⏰ Timeout - No se detectó acierto del ESP32, registrando como fallo SIN VIDEO',
      );
      addDebugMessage(
        'Timeout - No se detectó acierto, registrando fallo SIN VIDEO',
      );

      _registerShotResult(false, ShotDetectionType.sensor);
      _isWaitingForShotResult = false;
      notifyListeners();
    });
  }

  /// Verifica si hubo un incremento en los aciertos del ESP32
  void checkForEsp32ShotDetection() {
    if (!_isWaitingForShotResult) return;

    final currentAciertos = _getCurrentEsp32Aciertos();

    if (currentAciertos > _previousAciertos) {
      debugPrint(
        '🏀 ¡Acierto detectado por ESP32! $_previousAciertos -> $currentAciertos',
      );
      addDebugMessage(
        '¡Acierto detectado por ESP32! $_previousAciertos -> $currentAciertos',
      );

      _shotTimeoutTimer?.cancel();
      _registerShotResult(true, ShotDetectionType.sensor);
      _isWaitingForShotResult = false;
      notifyListeners();
    }
  }

  /// Obtiene el número actual de aciertos del ESP32 desde los datos de sensores
  int _getCurrentEsp32Aciertos() {
    if (_sensorData.containsKey('ESP32') && _sensorData['ESP32'] is Map) {
      final esp32Data = _sensorData['ESP32'] as Map<String, dynamic>;
      if (esp32Data.containsKey('newAciertos')) {
        return esp32Data['newAciertos'] as int? ?? 0;
      }
    }
    return 0;
  }

  /// Registra el resultado de un tiro (método interno)
  void _registerShotResult(bool isSuccessful, ShotDetectionType detectionType) {
    // DEPRECATED: Este método ya no debe crear clips sin video
    // Los tiros deben registrarse a través del CameraViewModel para incluir video
    debugPrint(
      '⚠️ _registerShotResult está deprecated - los tiros deben registrarse con video',
    );

    // Por compatibilidad temporal, registramos sin video pero con advertencia
    final shot = ShotClip(
      timestamp: DateTime.now(),
      isSuccessful: isSuccessful,
      videoPath: '', // Sin video - ESTO ES EL PROBLEMA
      confidenceScore: 0.9,
      detectionType: detectionType,
    );

    _pendingShots.add(shot);

    debugPrint(
      '⚠️ Resultado de tiro registrado SIN VIDEO: ${isSuccessful ? "ACIERTO" : "FALLO"}',
    );
    addDebugMessage(
      '⚠️ Resultado SIN VIDEO: ${isSuccessful ? "ACIERTO" : "FALLO"}',
    );

    notifyListeners();
  }

  /// Carga todas las sesiones guardadas
  Future<void> loadSessions() async {
    _setLoading(true);
    _clearError();

    try {
      _sessions = await _repository.getAllSessions();
      // Ordenar por fecha, más recientes primero
      _sessions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    } catch (e) {
      _setError('Error al cargar sesiones: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Método para compatibilidad con código existente
  Future<List<SessionModel>> getAllSessions() async {
    // Si ya tenemos sesiones cargadas, devolverlas directamente
    if (_sessions.isNotEmpty) {
      return _sessions;
    }

    // Solo cargar si la lista está vacía
    await loadSessions();
    return _sessions;
  }

  /// Elimina una sesión específica
  Future<void> deleteSession(String sessionId) async {
    _setLoading(true);
    _clearError();

    try {
      await _repository.deleteSession(sessionId);
      await loadSessions(); // Recargar la lista
    } catch (e) {
      _setError('Error al eliminar sesión: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Selecciona un video para reproducir
  void selectVideoForPlayback(String videoPath) {
    _selectedVideoPath = videoPath;
    notifyListeners();
  }

  /// Cierra el reproductor de video
  void closeVideoPlayer() {
    _selectedVideoPath = null;
    notifyListeners();
  }

  /// Obtiene todas las estadísticas de una sesión
  Map<String, dynamic> getSessionStats(SessionModel session) {
    final shotsByType = <ShotDetectionType, int>{};
    final shotsByHour = <int, int>{};

    for (final shot in session.shotClips) {
      // Contar por tipo de detección
      shotsByType[shot.detectionType] =
          (shotsByType[shot.detectionType] ?? 0) + 1;

      // Contar por hora
      final hour = shot.timestamp.hour;
      shotsByHour[hour] = (shotsByHour[hour] ?? 0) + 1;
    }

    return {
      'totalShots': session.totalShots,
      'successfulShots': session.successfulShots,
      'missedShots': session.missedShots,
      'successRate': session.successRate,
      'duration': Duration(seconds: session.durationInSeconds),
      'shotsByType': shotsByType,
      'shotsByHour': shotsByHour,
      'averageConfidence':
          session.shotClips
              .where((shot) => shot.confidenceScore != null)
              .map((shot) => shot.confidenceScore!)
              .fold(0.0, (sum, confidence) => sum + confidence) /
          session.shotClips
              .where((shot) => shot.confidenceScore != null)
              .length,
    };
  }

  /// Busca sesiones por rango de fechas
  List<SessionModel> getSessionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return _sessions
        .where(
          (session) =>
              session.dateTime.isAfter(startDate) &&
              session.dateTime.isBefore(endDate),
        )
        .toList();
  }

  /// Obtiene estadísticas globales de todas las sesiones
  Map<String, dynamic> getGlobalStats() {
    if (_sessions.isEmpty) {
      return {
        'totalSessions': 0,
        'totalShots': 0,
        'totalSuccessfulShots': 0,
        'globalSuccessRate': 0.0,
        'totalPlayTime': Duration.zero,
        'averageSessionDuration': Duration.zero,
      };
    }

    final totalShots = _sessions.fold(
      0,
      (sum, session) => sum + session.totalShots,
    );
    final totalSuccessfulShots = _sessions.fold(
      0,
      (sum, session) => sum + session.successfulShots,
    );
    final totalDuration = _sessions.fold(
      0,
      (sum, session) => sum + session.durationInSeconds,
    );

    return {
      'totalSessions': _sessions.length,
      'totalShots': totalShots,
      'totalSuccessfulShots': totalSuccessfulShots,
      'globalSuccessRate':
          totalShots > 0 ? (totalSuccessfulShots / totalShots) * 100 : 0.0,
      'totalPlayTime': Duration(seconds: totalDuration),
      'averageSessionDuration': Duration(
        seconds: totalDuration ~/ _sessions.length,
      ),
    };
  }

  // Métodos privados para manejo del timer
  void _startTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
  }

  // Métodos privados de utilidad
  void _setState(SessionState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  // Métodos para el panel de debug

  /// Alterna la visibilidad del panel de debug
  void toggleDebugPanel() {
    _isDebugPanelVisible = !_isDebugPanelVisible;

    // Agregar mensaje de debug directamente para evitar recursión
    final timestamp = DateTime.now();
    final formattedMessage =
        '[${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}] Panel de debug ${_isDebugPanelVisible ? "mostrado" : "ocultado"}';
    _debugMessages.insert(0, formattedMessage);

    // Mantener solo los últimos N mensajes
    if (_debugMessages.length > _maxDebugMessages) {
      _debugMessages.removeRange(_maxDebugMessages, _debugMessages.length);
    }

    notifyListeners();
  }

  /// Agrega un mensaje al log de debug
  void addDebugMessage(String message) {
    final timestamp = DateTime.now();
    final formattedMessage =
        '[${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}] $message';

    _debugMessages.insert(0, formattedMessage);

    // Mantener solo los últimos N mensajes
    if (_debugMessages.length > _maxDebugMessages) {
      _debugMessages.removeRange(_maxDebugMessages, _debugMessages.length);
    }

    if (_isDebugPanelVisible) {
      notifyListeners();
    }
  }

  /// Actualiza los datos de sensores para debug
  void updateSensorData(String sensorType, Map<String, dynamic> data) {
    _sensorData[sensorType] = {
      ...data,
      'lastUpdate': DateTime.now().toIso8601String(),
    };

    addDebugMessage('Datos actualizados: $sensorType');

    // Si recibimos datos del ESP32, verificar si hay aciertos nuevos
    if (sensorType == 'ESP32' && _isWaitingForShotResult) {
      checkForEsp32ShotDetection();
    }

    if (_isDebugPanelVisible) {
      notifyListeners();
    }
  }

  /// Limpia los mensajes de debug
  void clearDebugMessages() {
    _debugMessages.clear();

    // Agregar mensaje de debug directamente
    final timestamp = DateTime.now();
    final formattedMessage =
        '[${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}] Log de debug limpiado';
    _debugMessages.insert(0, formattedMessage);

    notifyListeners();
  }

  /// Obtiene el estado actual de conectividad para debug
  Map<String, dynamic> getConnectivityStatus() {
    return {
      'sessionActive': _isSessionActive,
      'sessionState': _state.toString().split('.').last,
      'elapsedTime': _elapsedSeconds,
      'totalShots': _pendingShots.length,
      'successfulShots': currentSessionSuccessfulShots,
      'missedShots': currentSessionMissedShots,
      'sensors': _sensorData,
    };
  }

  /// Simula datos de sensores para testing
  void simulateSensorData() {
    // Simular datos del Apple Watch
    updateSensorData('appleWatch', {
      'connected': true,
      'monitoring': _isSessionActive,
      'batteryLevel': 85,
      'lastShotDetection':
          DateTime.now().subtract(Duration(seconds: 30)).toIso8601String(),
    });

    // Simular datos del sensor Bluetooth
    updateSensorData('bluetooth', {
      'connected': true,
      'signalStrength': -45,
      'aciertos': currentSessionSuccessfulShots,
      'distancia': 3.2,
      'lastReading': DateTime.now().toIso8601String(),
    });

    addDebugMessage('Datos de sensores simulados');
  }

  @override
  void dispose() {
    // Finalizar sesión activa si existe
    if (_isSessionActive) {
      endSession();
    }
    _stopTimer();
    _shotTimeoutTimer?.cancel();
    super.dispose();
  }
}
