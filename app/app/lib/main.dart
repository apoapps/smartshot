import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'features/shared/bluetooth/bluetooth_view_model.dart';
import 'features/camera/camera_view_model.dart';
import 'features/dashboard/view/dashboard_view.dart';
import 'features/shared/sessions/data/session_repository.dart';
import 'features/shared/sessions/view_model/session_view_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar datos de formateo de fecha para locale español
  await initializeDateFormatting('es_ES', null);
  
  final sessionRepository = SessionRepository();
  await sessionRepository.init();
  
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (context) => sessionRepository),
        ChangeNotifierProvider(create: (context) => BluetoothViewModel()),
        ChangeNotifierProxyProvider<SessionRepository, SessionViewModel>(
          create: (context) => SessionViewModel(context.read<SessionRepository>()),
          update: (context, repository, previous) => 
            previous ?? SessionViewModel(repository),
        ),
        ChangeNotifierProxyProvider2<SessionRepository, BluetoothViewModel, CameraViewModel>(
          create: (context) => CameraViewModel(
            context.read<SessionRepository>(), 
            context.read<BluetoothViewModel>(),
            null, // Pasará null como sessionViewModel por ahora
          ),
          update: (context, repository, bluetoothViewModel, previous) => 
            previous ?? CameraViewModel(repository, bluetoothViewModel),
        ),
      ],
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
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        useMaterial3: true,
      ),
      home: const SmartShotHomePage(),
    );
  }
}
