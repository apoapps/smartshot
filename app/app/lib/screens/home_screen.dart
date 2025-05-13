import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bluetooth_model.dart';

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
            color: viewModel.isConnected ? Colors.green.shade100 : Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  viewModel.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
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
                  onPressed: viewModel.isConnecting 
                    ? null 
                    : (viewModel.isConnected ? viewModel.disconnect : viewModel.scanAndConnect),
                  icon: Icon(viewModel.isConnected ? Icons.bluetooth_disabled : Icons.bluetooth_searching),
                  label: Text(
                    viewModel.isConnecting
                      ? 'Conectando...'
                      : (viewModel.isConnected ? 'Desconectar' : 'Buscar y Conectar'),
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
                      color: viewModel.ledState ? Colors.yellow.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          size: 48,
                          color: viewModel.ledState ? Colors.yellow : Colors.grey,
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
                          onPressed: viewModel.isConnected ? () => viewModel.toggleLed(true) : null,
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
                          onPressed: viewModel.isConnected ? () => viewModel.toggleLed(false) : null,
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
                    onPressed: viewModel.isConnected ? viewModel.requestLedState : null,
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