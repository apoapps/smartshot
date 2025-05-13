# SmartShot - Control de LED con ESP32 y Flutter

Esta aplicación permite controlar un LED conectado a un ESP32 usando Bluetooth. La aplicación está construida con Flutter y utiliza Provider para la gestión del estado.

## Características

- Conexión Bluetooth con un ESP32
- Control de LED en el pin D13 (encendido/apagado)
- Solicitud del estado actual del LED
- Interfaz de usuario intuitiva

## Requisitos

### Para la aplicación Flutter:
- Flutter 3.0 o superior
- Paquetes:
  - flutter_blue_plus: ^1.35.5
  - provider: ^6.1.5

### Para el ESP32:
- Arduino IDE
- Bibliotecas:
  - BluetoothSerial
  - ArduinoJson

## Configuración

### ESP32:

1. Conecte un LED al pin D13 del ESP32 (con una resistencia de 220-330 ohms en serie)
2. Abra el archivo `app/lib/esp32/esp32_code.ino` en Arduino IDE
3. Instale las bibliotecas necesarias si aún no las tiene
4. Cargue el código al ESP32

### Aplicación Flutter:

1. Clone este repositorio
2. Ejecute `flutter pub get` para instalar las dependencias
3. Ejecute la aplicación con `flutter run`

## Uso

1. Encienda el ESP32
2. Abra la aplicación SmartShot en su dispositivo móvil
3. Pulse "Buscar y Conectar" para encontrar y conectarse al ESP32
4. Una vez conectado, utilice los botones para controlar el LED:
   - "ENCENDER": Enciende el LED
   - "APAGAR": Apaga el LED
   - "CONSULTAR ESTADO": Solicita al ESP32 el estado actual del LED

## Estructura del proyecto

- `lib/main.dart`: Punto de entrada de la aplicación
- `lib/models/bluetooth_model.dart`: Modelo que gestiona la conexión Bluetooth y el estado del LED
- `lib/screens/home_screen.dart`: Pantalla principal con la interfaz de usuario
- `lib/esp32/esp32_code.ino`: Código de Arduino para el ESP32

## Protocolo de comunicación

La comunicación entre la aplicación Flutter y el ESP32 se realiza mediante mensajes JSON:

### Comandos de la aplicación al ESP32:

```json
{"command": "led", "state": 1}  // Encender LED
{"command": "led", "state": 0}  // Apagar LED
{"command": "status"}           // Solicitar estado
```

### Respuestas del ESP32 a la aplicación:

```json
{"status": "led", "state": 1}  // LED encendido
{"status": "led", "state": 0}  // LED apagado
```
