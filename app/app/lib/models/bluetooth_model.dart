import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:convert';

class BluetoothViewModel extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _ledState = false;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get ledState => _ledState;

  // Escanear y conectar al primer dispositivo encontrado con el nombre ESP32
  Future<void> scanAndConnect() async {
    _isConnecting = true;
    notifyListeners();

    try {
      // Iniciar el escaneo
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
      
      // Escuchar los resultados del escaneo
      await for (final result in FlutterBluePlus.scanResults) {
        for (ScanResult r in result) {
          // Busca un dispositivo con ESP32 en el nombre
          if (r.device.advName.toLowerCase().contains('esp32')) {
            await FlutterBluePlus.stopScan();
            
            // Conectarse al dispositivo
            await _connectToDevice(r.device);
            return;
          }
        }
      }
      
      // Si llegamos aquí, no se encontró el dispositivo
      _isConnecting = false;
      notifyListeners();
    } catch (e) {
      print('Error al escanear/conectar: $e');
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Conectar a un dispositivo específico
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _device = device;
      
      // Descubrir servicios
      List<BluetoothService> services = await device.discoverServices();
      
      // Buscar el servicio y característica adecuados
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          // Característica para controlar el LED
          if (characteristic.properties.write) {
            _characteristic = characteristic;
            break;
          }
        }
      }
      
      _isConnected = true;
    } catch (e) {
      print('Error al conectar: $e');
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Desconectar
  Future<void> disconnect() async {
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (e) {
        print('Error al desconectar: $e');
      }
    }
    
    _device = null;
    _characteristic = null;
    _isConnected = false;
    notifyListeners();
  }

  // Encender/apagar el LED
  Future<void> toggleLed(bool state) async {
    if (_characteristic != null) {
      try {
        // Crear un JSON con el comando
        final Map<String, dynamic> command = {
          'command': 'led',
          'state': state ? 1 : 0
        };
        
        // Convertir a string y luego a bytes
        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);
        
        // Escribir en la característica
        await _characteristic!.write(bytes);
        
        // Actualizar el estado local
        _ledState = state;
        notifyListeners();
      } catch (e) {
        print('Error al enviar comando: $e');
      }
    }
  }

  // Solicitar el estado actual del LED
  Future<void> requestLedState() async {
    if (_characteristic != null) {
      try {
        // Comando para solicitar estado
        final Map<String, dynamic> command = {
          'command': 'status'
        };
        
        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);
        
        // Escribir en la característica
        await _characteristic!.write(bytes);
        
        // Configurar notificaciones para recibir la respuesta
        await _characteristic!.setNotifyValue(true);
        
        _characteristic!.onValueReceived.listen((value) {
          _handleResponse(value);
        });
      } catch (e) {
        print('Error al solicitar estado: $e');
      }
    }
  }

  // Manejar la respuesta recibida del ESP32
  void _handleResponse(List<int> value) {
    try {
      final String response = utf8.decode(value);
      final Map<String, dynamic> data = jsonDecode(response);
      
      if (data.containsKey('status') && data.containsKey('state')) {
        if (data['status'] == 'led') {
          _ledState = data['state'] == 1;
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error al procesar respuesta: $e');
    }
  }
} 