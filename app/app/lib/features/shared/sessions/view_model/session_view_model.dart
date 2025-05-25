import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app/features/shared/sessions/data/session_model.dart';
import 'package:app/features/shared/sessions/data/session_repository.dart';

enum SessionState {
  initial,
  loading,
  active,
  paused,
  completed,
  error,
}

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
  
  SessionViewModel(this._repository);
  
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
          
  Duration get currentSessionDuration => _sessionStartTime != null 
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
      
      final sessionDuration = _state == SessionState.paused && _sessionPauseTime != null
          ? _sessionPauseTime!.difference(_sessionStartTime!)
          : DateTime.now().difference(_sessionStartTime!);
      
      // Crear el modelo de sesión
      final session = SessionModel(
        dateTime: _sessionStartTime!,
        durationInSeconds: sessionDuration.inSeconds,
        totalShots: _pendingShots.length,
        successfulShots: _pendingShots.where((shot) => shot.isSuccessful).length,
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
      
      debugPrint('Tiro registrado: ${isSuccessful ? 'Acierto' : 'Fallo'} - $detectionType');
      
      notifyListeners();
      
    } catch (e) {
      debugPrint('Error al registrar tiro: $e');
    }
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
      'averageConfidence': session.shotClips
          .where((shot) => shot.confidenceScore != null)
          .map((shot) => shot.confidenceScore!)
          .fold(0.0, (sum, confidence) => sum + confidence) /
          session.shotClips
              .where((shot) => shot.confidenceScore != null)
              .length,
    };
  }
  
  /// Busca sesiones por rango de fechas
  List<SessionModel> getSessionsByDateRange(DateTime startDate, DateTime endDate) {
    return _sessions.where((session) => 
        session.dateTime.isAfter(startDate) && 
        session.dateTime.isBefore(endDate)
    ).toList();
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
    
    final totalShots = _sessions.fold(0, (sum, session) => sum + session.totalShots);
    final totalSuccessfulShots = _sessions.fold(0, (sum, session) => sum + session.successfulShots);
    final totalDuration = _sessions.fold(0, (sum, session) => sum + session.durationInSeconds);
    
    return {
      'totalSessions': _sessions.length,
      'totalShots': totalShots,
      'totalSuccessfulShots': totalSuccessfulShots,
      'globalSuccessRate': totalShots > 0 ? (totalSuccessfulShots / totalShots) * 100 : 0.0,
      'totalPlayTime': Duration(seconds: totalDuration),
      'averageSessionDuration': Duration(seconds: totalDuration ~/ _sessions.length),
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
  
  @override
  void dispose() {
    // Finalizar sesión activa si existe
    if (_isSessionActive) {
      endSession();
    }
    _stopTimer();
    super.dispose();
  }
} 