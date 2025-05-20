import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/bluetooth_model.dart';
import 'view_models/camera_view_model.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => BluetoothViewModel()),
        ChangeNotifierProvider(create: (context) => CameraViewModel()),
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
      home: const SmartShotHomePage(),
    );
  }
}
