import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../connectivity/connectivity_service.dart';

// UUIDs para el servicio BLE y características - ESP32
const String ESP32_SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String ESP32_CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

enum DeviceType { esp32 }

class ConnectedDevice {
  final BluetoothDevice device;
  final DeviceType type;
  final BluetoothCharacteristic? dataCharacteristic;

  ConnectedDevice({
    required this.device,
    required this.type,
    this.dataCharacteristic,
  });
}

class BluetoothViewModel extends ChangeNotifier {
  // Dispositivos conectados
  ConnectedDevice? _esp32Device;

  // Estados
  bool _isConnecting = false;
  bool _ledState = false;
  int _aciertos = 0;
  double _distancia = 0;

  // Nuevo campo para seguir cuando se detecta un incremento en aciertos
  int _previousAciertos = 0;
  bool _shotDetected = false;

  // Callback para enviar datos de debug
  Function(String, Map<String, dynamic>)? _debugCallback;

  // Referencia al servicio de conectividad
  final ConnectivityService _connectivityService = ConnectivityService();

  // Getters existentes
  bool get isConnected => _esp32Device != null;
  bool get isEsp32Connected => _esp32Device != null;
  bool get isConnecting => _isConnecting;
  bool get ledState => _ledState;
  int get aciertos => _aciertos;
  double get distancia => _distancia;

  // Getter para informar cuando se detecta un tiro
  bool get shotDetected {
    if (_shotDetected) {
      _shotDetected = false;
      return true;
    }
    return false;
  }

  /// Configura el callback para enviar datos de debug
  void setDebugCallback(Function(String, Map<String, dynamic>) callback) {
    _debugCallback = callback;
  }

  /// Envía datos de debug si hay un callback configurado
  void _sendDebugData(String message, Map<String, dynamic> data) {
    _debugCallback?.call(message, data);
  }

  // Escanear y conectar a dispositivos ESP32
  Future<void> scanAndConnect() async {
    _isConnecting = true;
    notifyListeners();

    try {
      // Verificar estado del Bluetooth antes de escanear
      final bluetoothState = await FlutterBluePlus.adapterState.first;
      debugPrint('🔵 Estado del Bluetooth: $bluetoothState');

      if (bluetoothState != BluetoothAdapterState.on) {
        debugPrint('❌ Bluetooth no está encendido. Estado: $bluetoothState');
        _isConnecting = false;
        notifyListeners();
        return;
      }

      debugPrint('🔍 Iniciando escaneo de dispositivos ESP32...');

      // Verificar si ya estamos escaneando
      if (await FlutterBluePlus.isScanning.first) {
        debugPrint('⚠️ Ya se está ejecutando un escaneo - deteniéndolo');
        await FlutterBluePlus.stopScan();
        await Future.delayed(Duration(milliseconds: 500));
      }

      // Iniciar el escaneo
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // Escuchar los resultados del escaneo
      bool esp32Found = false;

      await for (final result in FlutterBluePlus.scanResults) {
        for (ScanResult r in result) {
          debugPrint(
            '📱 Dispositivo encontrado: ${r.device.advName} (${r.device.remoteId})',
          );

          // Buscar ESP32
          if (!esp32Found &&
              (r.device.advName.toLowerCase().contains('esp32') ||
                  r.device.advName.toLowerCase().contains('smartshot'))) {
            debugPrint(
              '✅ Dispositivo ESP32 SmartShot encontrado: ${r.device.advName}',
            );
            esp32Found = true;
            await _connectToEsp32(r.device);
            break;
          }
        }

        if (esp32Found) break;
      }

      // Información sobre dispositivos encontrados
      if (!esp32Found) {
        debugPrint('❌ No se encontró dispositivo ESP32 SmartShot');
      }
    } catch (e) {
      debugPrint('❌ Error al escanear/conectar: $e');
      _handleBluetoothError(e);
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  // Conectar específicamente al ESP32
  Future<void> _connectToEsp32(BluetoothDevice device) async {
    try {
      debugPrint('🔄 Conectando al ESP32...');
      await device.connect();

      // Descubrir servicios
      List<BluetoothService> services = await device.discoverServices();

      // Buscar el servicio y característica específicos del ESP32
      BluetoothCharacteristic? dataCharacteristic;

      for (BluetoothService service in services) {
        if (service.serviceUuid.toString().toUpperCase().contains(
          ESP32_SERVICE_UUID.toUpperCase(),
        )) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.characteristicUuid
                .toString()
                .toUpperCase()
                .contains(ESP32_CHARACTERISTIC_UUID.toUpperCase())) {
              dataCharacteristic = characteristic;

              // Configurar notificaciones para recibir respuestas
              await characteristic.setNotifyValue(true);
              characteristic.onValueReceived.listen((data) {
                _handleEsp32Response(data);
              });

              break;
            }
          }
        }
      }

      if (dataCharacteristic != null) {
        _esp32Device = ConnectedDevice(
          device: device,
          type: DeviceType.esp32,
          dataCharacteristic: dataCharacteristic,
        );

        debugPrint('✅ ESP32 conectado exitosamente');
        _sendDebugData('ESP32', {
          'connected': true,
          'device': device.advName,
          'serviceFound': true,
        });
      } else {
        debugPrint('❌ Característica ESP32 no encontrada');
        await device.disconnect();
      }
    } catch (e) {
      debugPrint('❌ Error al conectar ESP32: $e');
      await device.disconnect();
    }

    // Actualizar el servicio de conectividad
    _connectivityService.updateBluetoothStatus(isConnected);
    notifyListeners();
  }

  // Manejar errores de Bluetooth
  void _handleBluetoothError(dynamic e) {
    if (e.toString().contains('bluetooth must be turned on')) {
      debugPrint('💡 Sugerencia: Habilita Bluetooth en Configuración');
    } else if (e.toString().contains('CBManagerStateUnknown')) {
      debugPrint('💡 Esperando inicialización del Bluetooth...');
      // Intentar de nuevo después de un delay
      Future.delayed(Duration(seconds: 2)).then((_) async {
        if (await FlutterBluePlus.adapterState.first ==
            BluetoothAdapterState.on) {
          debugPrint('🔄 Bluetooth ya disponible, reintentando...');
          scanAndConnect();
        }
      });
    }
  }

  // Desconectar todos los dispositivos
  Future<void> disconnect() async {
    // Desconectar ESP32
    if (_esp32Device != null) {
      try {
        await _esp32Device!.device.disconnect();
        debugPrint('✅ ESP32 desconectado');
      } catch (e) {
        debugPrint('❌ Error al desconectar ESP32: $e');
      }
      _esp32Device = null;
    }

    // Actualizar el servicio de conectividad
    _connectivityService.updateBluetoothStatus(false);

    notifyListeners();
  }

  // Métodos específicos para ESP32
  Future<void> toggleLed(bool state) async {
    if (_esp32Device?.dataCharacteristic != null) {
      try {
        final Map<String, dynamic> command = {
          'command': 'led',
          'state': state ? 1 : 0,
        };

        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);

        await _esp32Device!.dataCharacteristic!.write(bytes);
      } catch (e) {
        debugPrint('❌ Error al enviar comando LED: $e');
      }
    }
  }

  Future<void> requestLedState() async {
    if (_esp32Device?.dataCharacteristic != null) {
      try {
        final Map<String, dynamic> command = {'command': 'status'};
        final String jsonStr = jsonEncode(command);
        final List<int> bytes = utf8.encode(jsonStr);

        await _esp32Device!.dataCharacteristic!.write(bytes);
      } catch (e) {
        debugPrint('❌ Error al solicitar estado LED: $e');
      }
    }
  }

  // Manejar respuestas del ESP32
  void _handleEsp32Response(List<int> value) {
    try {
      if (value.isEmpty) return;

      // Si recibimos exactamente 4 bytes, podría ser un float IEEE-754
      if (value.length == 4) {
        try {
          final buffer = Uint8List.fromList(value).buffer;
          final byteData = ByteData.view(buffer);
          final valorFloat = byteData.getFloat32(0, Endian.little);

          if (valorFloat >= 0 && valorFloat < 1000) {
            _distancia = valorFloat;
            notifyListeners();
            return;
          }
        } catch (e) {
          debugPrint('❌ Error al interpretar como float: $e');
        }
      }

      // Intenta convertir bytes a string
      String response;
      try {
        response = utf8.decode(value);
      } catch (e) {
        debugPrint('❌ Error al decodificar UTF-8: $e');
        return;
      }

      if (!response.startsWith('{') || !response.endsWith('}')) {
        return;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response);
      } catch (e) {
        debugPrint('❌ Error al decodificar JSON: $e');
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
              debugPrint('❌ Error al convertir distancia: $e');
            }
          }

          if (data.containsKey('aciertos')) {
            try {
              _previousAciertos = _aciertos;
              _aciertos = data['aciertos'] ?? 0;

              if (_aciertos > _previousAciertos) {
                debugPrint(
                  '🏀 ¡Acierto detectado por ESP32! $_previousAciertos -> $_aciertos',
                );
                _shotDetected = true;
                _sendDebugData('ESP32', {
                  'shotDetected': true,
                  'previousAciertos': _previousAciertos,
                  'newAciertos': _aciertos,
                });
              }
            } catch (e) {
              debugPrint('❌ Error al convertir aciertos: $e');
            }
          }

          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('❌ Error general al procesar respuesta ESP32: $e');
    }
  }
}
