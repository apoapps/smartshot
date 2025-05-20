import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/session_model.dart';
import '../data/session_repository.dart';

enum SessionState {
  initial,
  loading,
  active,
  paused,
  completed,
  error
}

class SessionViewModel extends ChangeNotifier {
  final SessionRepository _repository;
  
  // Estado de la sesión
  SessionState _state = SessionState.initial;
  String? _errorMessage;
  SessionModel? _currentSession;
  Timer? _sessionTimer;
  int _elapsedSeconds = 0;
  int _successfulShots = 0;
  int _totalShots = 0;
  final List<ShotClip> _clips = [];

  // Getters
  SessionState get state => _state;
  String? get errorMessage => _errorMessage;
  SessionModel? get currentSession => _currentSession;
  int get elapsedSeconds => _elapsedSeconds;
  int get successfulShots => _successfulShots;
  int get totalShots => _totalShots;
  int get missedShots => _totalShots - _successfulShots;
  List<ShotClip> get clips => List.unmodifiable(_clips);
  bool get isSessionActive => _state == SessionState.active || _state == SessionState.paused;

  SessionViewModel(this._repository);

  // Iniciar sesión
  Future<void> startSession() async {
    try {
      _state = SessionState.loading;
      notifyListeners();
      
      await _repository.init();
      
      _state = SessionState.active;
      _elapsedSeconds = 0;
      _successfulShots = 0;
      _totalShots = 0;
      _clips.clear();
      
      // Iniciar temporizador
      _startTimer();
      
      notifyListeners();
    } catch (e) {
      _state = SessionState.error;
      _errorMessage = "Error al iniciar la sesión: $e";
      notifyListeners();
    }
  }
  
  // Pausar sesión
  void pauseSession() {
    if (_state != SessionState.active) return;
    
    _state = SessionState.paused;
    _sessionTimer?.cancel();
    notifyListeners();
  }
  
  // Reanudar sesión
  void resumeSession() {
    if (_state != SessionState.paused) return;
    
    _state = SessionState.active;
    _startTimer();
    notifyListeners();
  }
  
  // Finalizar sesión
  Future<void> endSession() async {
    if (!isSessionActive) return;
    
    try {
      _state = SessionState.loading;
      notifyListeners();
      
      _sessionTimer?.cancel();
      
      // Crear modelo de sesión
      _currentSession = SessionModel(
        dateTime: DateTime.now(),
        durationInSeconds: _elapsedSeconds,
        totalShots: _totalShots,
        successfulShots: _successfulShots,
        shotClips: List.from(_clips),
      );
      
      // Guardar en la base de datos
      await _repository.saveSession(_currentSession!);
      
      _state = SessionState.completed;
      notifyListeners();
    } catch (e) {
      _state = SessionState.error;
      _errorMessage = "Error al finalizar la sesión: $e";
      notifyListeners();
    }
  }
  
  // Registrar un tiro (detectado por sensor)
  Future<void> registerShot({
    required bool isSuccessful,
    required String videoPath,
    required ShotDetectionType detectionType,
    double? confidenceScore,
  }) async {
    if (!isSessionActive) return;
    
    final newClip = ShotClip(
      timestamp: DateTime.now(),
      isSuccessful: isSuccessful,
      videoPath: videoPath,
      confidenceScore: confidenceScore,
      detectionType: detectionType,
    );
    
    _clips.add(newClip);
    _totalShots++;
    
    if (isSuccessful) {
      _successfulShots++;
    }
    
    notifyListeners();
  }
  
  // Cargar sesión por ID
  Future<void> loadSession(String sessionId) async {
    try {
      _state = SessionState.loading;
      notifyListeners();
      
      await _repository.init();
      _currentSession = await _repository.getSessionById(sessionId);
      
      if (_currentSession != null) {
        _elapsedSeconds = _currentSession!.durationInSeconds;
        _successfulShots = _currentSession!.successfulShots;
        _totalShots = _currentSession!.totalShots;
        _clips.clear();
        _clips.addAll(_currentSession!.shotClips);
      }
      
      _state = SessionState.completed;
      notifyListeners();
    } catch (e) {
      _state = SessionState.error;
      _errorMessage = "Error al cargar la sesión: $e";
      notifyListeners();
    }
  }
  
  // Obtener todas las sesiones
  Future<List<SessionModel>> getAllSessions() async {
    await _repository.init();
    return _repository.getAllSessions();
  }
  
  // Eliminar una sesión
  Future<void> deleteSession(String sessionId) async {
    await _repository.init();
    await _repository.deleteSession(sessionId);
    notifyListeners();
  }
  
  // Iniciar temporizador de sesión
  void _startTimer() {
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }
} 