import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'camera_view_model.dart';

class CameraDebugView extends StatelessWidget {
  const CameraDebugView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug de Cámara'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Consumer<CameraViewModel>(
        builder: (context, cameraViewModel, child) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estado de la Cámara',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Inicializada: ${cameraViewModel.isInitialized}'),
                        Text('Detectando: ${cameraViewModel.isDetectionEnabled}'),
                        Text('Total tiros: ${cameraViewModel.totalShots}'),
                        Text('Aciertos: ${cameraViewModel.successfulShots}'),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Simular Tiros',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => cameraViewModel.simulateShot(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Simular Acierto'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => cameraViewModel.simulateShot(false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Simular Fallo'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                ElevatedButton(
                  onPressed: () => _showBufferInfo(context, cameraViewModel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Ver Info del Buffer'),
                ),
                
                const SizedBox(height: 16),
                
                const Expanded(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Instrucciones',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Usa los botones "Simular" para probar la grabación de clips\n'
                            '2. Ve a "Historial de Sesiones" para verificar que se guardaron\n'
                            '3. Usa "Ver Info del Buffer" para diagnosticar problemas\n'
                            '4. Los logs aparecen en la consola de debug',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  void _showBufferInfo(BuildContext context, CameraViewModel cameraViewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Info del Buffer'),
        content: SingleChildScrollView(
          child: Text(
            cameraViewModel.getBufferDebugInfo(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
} 