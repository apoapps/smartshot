# SmartShot - ESP32 BLE Flutter App

Aplicación que conecta un ESP32 con una app móvil Flutter usando Bluetooth Low Energy (BLE).

## Características

- Comunicación bidireccional entre ESP32 y dispositivos móviles
- Control remoto de LED mediante comandos JSON
- Interfaz de usuario intuitiva para control y monitoreo
- Utiliza el patrón Provider para gestión de estado en Flutter

## Estructura del proyecto

- `/app` - Aplicación Flutter con patrón MVC
- `/device` - Código para el ESP32 con soporte BLE

## Configuración

### ESP32
- Conectar el LED al pin 13
- Cargar el código utilizando PlatformIO

### Flutter
- Ejecutar `flutter pub get` para instalar dependencias
- Utiliza `flutter_blue_plus` para comunicación BLE
