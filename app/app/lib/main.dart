import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

// UUIDs para el servicio BLE y características - Deben coincidir con los del ESP32
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => BluetoothViewModel(),
      child: const SmartShotApp(),
    ),
  );
}

class SmartShotApp extends StatelessWidget {
  const SmartShotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartShot',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SmartShotHomePage(),
    );
  }
}

class SmartShotHomePage extends StatelessWidget {
  const SmartShotHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<BluetoothViewModel>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartShot'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Estado de conexión
          Container(
            padding: const EdgeInsets.all(16),
            color:
                viewModel.isConnected
                    ? Colors.green.shade100
                    : Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  viewModel.isConnected
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: viewModel.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(
                  viewModel.isConnected ? 'Conectado' : 'Desconectado',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: viewModel.isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),

          // Acciones Bluetooth
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed:
                      viewModel.isConnecting
                          ? null
                          : (viewModel.isConnected
                              ? viewModel.disconnect
                              : viewModel.scanAndConnect),
                  icon: Icon(
                    viewModel.isConnected
                        ? Icons.bluetooth_disabled
                        : Icons.bluetooth_searching,
                  ),
                  label: Text(
                    viewModel.isConnecting
                        ? 'Conectando...'
                        : (viewModel.isConnected
                            ? 'Desconectar'
                            : 'Buscar y Conectar'),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
          ),

          // Control del LED
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Control de LED (Pin D13)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  // Estado actual del LED
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          viewModel.ledState
                              ? Colors.yellow.shade100
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          size: 48,
                          color:
                              viewModel.ledState ? Colors.yellow : Colors.grey,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'LED está ${viewModel.ledState ? "ENCENDIDO" : "APAGADO"}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Botones de control
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              viewModel.isConnected
                                  ? () => viewModel.toggleLed(true)
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('ENCENDER'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              viewModel.isConnected
                                  ? () => viewModel.toggleLed(false)
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('APAGAR'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed:
                        viewModel.isConnected
                            ? viewModel.requestLedState
                            : null,
                    child: const Text('CONSULTAR ESTADO'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
      final String response = utf8.decode(value);
      print('Respuesta recibida: $response');

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
