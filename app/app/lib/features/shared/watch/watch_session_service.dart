import 'dart:async';
import 'package:flutter/services.dart';

class WatchSessionService {
  static const MethodChannel _channel = MethodChannel('com.apoapps.smartshot.watch');
  static final WatchSessionService _instance = WatchSessionService._internal();
  factory WatchSessionService() => _instance;

  final StreamController<bool> _shotController = StreamController<bool>.broadcast();
  Stream<bool> get shotDetected => _shotController.stream;

  WatchSessionService._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'shotDetected') {
      _shotController.add(true);
    }
  }

  void dispose() {
    _shotController.close();
  }

  /// Envía un evento al Apple Watch
  Future<void> sendShotToWatch() async {
    try {
      await _channel.invokeMethod('sendShotToWatch');
    } catch (_) {}
  }
} 