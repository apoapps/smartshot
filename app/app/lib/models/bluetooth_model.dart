import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// UUIDs para el servicio BLE y características - Deben coincidir con los del ESP32
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

class BluetoothViewModel extends ChangeNotifier {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _ledState = false;
  int _aciertos = 0;
  double _distancia = 0;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get ledState => _ledState;
  int get aciertos => _aciertos;
  double get distancia => _distancia;

  // Escanear y conectar al primer dispositivo encontrado con el nombre ESP32
  Future<void> scanAndConnect() async {
    _isConnecting = true;
    notifyListeners();

    try {
      // Iniciar el escaneo
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

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

      // Buscar el servicio y característica específicos definidos en el ESP32
      for (BluetoothService service in services) {
        if (service.serviceUuid.toString().toUpperCase().contains(
          SERVICE_UUID.toUpperCase(),
        )) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.characteristicUuid
                .toString()
                .toUpperCase()
                .contains(CHARACTERISTIC_UUID.toUpperCase())) {
              _characteristic = characteristic;

              // Configurar notificaciones para recibir respuestas
              await _characteristic!.setNotifyValue(true);
              _characteristic!.onValueReceived.listen((data) {
                _handleResponse(data);
              });

              break;
            }
          }
        }
      }

      _isConnected = _characteristic != null;

      if (!_isConnected) {
        print('Característica BLE no encontrada');
        await disconnect();
      }
    } catch (e) {
      print('Error al conectar: $e');
      await disconnect();
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
          'state': state ? 1 : 0,
        };

        // Convertir a string y luego a bytes
        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);

        // Escribir en la característica
        await _characteristic!.write(bytes);

        // Estado se actualizará cuando recibamos la notificación de respuesta
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
        final Map<String, dynamic> command = {'command': 'status'};

        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);

        // Escribir en la característica
        await _characteristic!.write(bytes);

        // La respuesta se procesará en el listener configurado en _connectToDevice
      } catch (e) {
        print('Error al solicitar estado: $e');
      }
    }
  }

  // Manejar la respuesta recibida del ESP32
  void _handleResponse(List<int> value) {
    try {
      // Debug: mostrar los bytes recibidos
      print('Bytes recibidos: ${value.toString()}');
      
      // Intenta decodificar sólo si hay bytes suficientes
      if (value.isEmpty) {
        print('Se recibió una lista vacía de bytes');
        return;
      }
      
      // Si recibimos exactamente 4 bytes, podría ser un float IEEE-754
      if (value.length == 4) {
        // Intenta tratarlo como un valor flotante (Little Endian)
        try {
          // Convertir 4 bytes a ByteData para leer como float
          final buffer = Uint8List.fromList(value).buffer;
          final byteData = ByteData.view(buffer);
          final valorFloat = byteData.getFloat32(0, Endian.little);
          
          print('Interpretando como float: $valorFloat');
          
          // Actualizar la distancia si parece un valor válido
          if (valorFloat >= 0 && valorFloat < 1000) {
            _distancia = valorFloat;
            notifyListeners();
            return;
          }
        } catch (e) {
          print('Error al interpretar como float: $e');
        }
      }
      
      // Intenta convertir bytes a string
      String response;
      try {
        response = utf8.decode(value);
        print('Texto recibido: $response');
      } catch (e) {
        print('Error al decodificar UTF-8: $e');
        print('Bytes individuales: ${value.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ')}');
        return;
      }
      
      // Verificar que el texto tenga formato de JSON
      if (!response.startsWith('{') || !response.endsWith('}')) {
        print('Formato no válido de JSON: $response');
        return;
      }
      
      // Intenta parsear el JSON
      Map<String, dynamic> data;
      try {
        data = jsonDecode(response);
        print('JSON decodificado: $data');
      } catch (e) {
        print('Error al decodificar JSON: $e');
        return;
      }

      if (data.containsKey('status')) {
        if (data['status'] == 'led') {
          _ledState = data['state'] == 1;
          notifyListeners();
        } else if (data['status'] == 'sensor') {
          if (data.containsKey('distancia')) {
            try {
              _distancia = (data['distancia'] as num).toDouble();
            } catch (e) {
              print('Error al convertir distancia: $e');
            }
          }
          
          if (data.containsKey('aciertos')) {
            try {
              _aciertos = data['aciertos'] ?? 0;
            } catch (e) {
              print('Error al convertir aciertos: $e');
            }
          }
          
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error general al procesar respuesta: $e');
    }
  }
} 