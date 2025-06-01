import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'features/shared/bluetooth/bluetooth_view_model.dart';
import 'features/camera/camera_view_model.dart';
import 'features/dashboard/view/dashboard_view.dart';
import 'features/shared/sessions/data/session_repository.dart';
import 'features/shared/sessions/view_model/session_view_model.dart';
import 'features/shared/connectivity/connectivity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializar datos de formateo de fecha para locale español
  await initializeDateFormatting('es_ES', null);
  
  final sessionRepository = SessionRepository();
  await sessionRepository.init();
  
  // Inicializar servicio de conectividad
  final connectivityService = ConnectivityService();
  await connectivityService.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (context) => sessionRepository),
        ChangeNotifierProvider(create: (context) => connectivityService),
        ChangeNotifierProvider(create: (context) => BluetoothViewModel()),
        ChangeNotifierProxyProvider<SessionRepository, SessionViewModel>(
          create: (context) => SessionViewModel(
            Provider.of<SessionRepository>(context, listen: false),
          ),
          update: (context, sessionRepository, previous) => 
              previous ?? SessionViewModel(sessionRepository),
        ),
        // CameraViewModel se creará localmente en SessionScreen
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
