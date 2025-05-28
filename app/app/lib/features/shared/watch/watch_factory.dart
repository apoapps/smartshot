import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:app/features/shared/watch/watch_view_model.dart';
import 'package:app/features/shared/sessions/view_model/session_view_model.dart';
import 'package:app/features/shared/bluetooth/bluetooth_view_model.dart';

/// Factory para manejar la inicialización del subsistema del Apple Watch
class WatchFactory {
  /// Registra los proveedores necesarios para el Apple Watch
  static List<SingleChildWidget> registerProviders() {
    return [
      ChangeNotifierProxyProvider2<SessionViewModel, BluetoothViewModel, WatchViewModel>(
        create: (context) => WatchViewModel(
          Provider.of<SessionViewModel>(context, listen: false),
          Provider.of<BluetoothViewModel>(context, listen: false),
        ),
        update: (context, sessionViewModel, bluetoothViewModel, previous) {
          // Si ya teníamos una instancia, la reutilizamos
          return previous ?? WatchViewModel(sessionViewModel, bluetoothViewModel);
        },
      ),
    ];
  }
  
  /// Inicializa el sistema del Apple Watch
  static Future<void> initialize(BuildContext context) async {
    // Inicializar el ViewModel del Apple Watch
    final watchViewModel = Provider.of<WatchViewModel>(context, listen: false);
    await watchViewModel.initialize();
  }
} 