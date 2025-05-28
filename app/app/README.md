# SmartShot Basketball Tracker

Aplicación para seguimiento de tiros de baloncesto que detecta y analiza tiros mediante sensores de movimiento y tecnología de Apple Watch.

## Características

- Detección de tiros con el acelerómetro del Apple Watch
- Registro de tiros acertados mediante sensores Bluetooth
- Análisis de movimientos y estadísticas de tiro
- Captura automática de video de los mejores momentos

## Integración Flutter con Apple Watch

Esta aplicación utiliza el paquete `watch_connectivity` para establecer comunicación bidireccional entre la aplicación Flutter y la extensión del Apple Watch. La implementación es mucho más simple que soluciones personalizadas utilizando MethodChannel.

### Estructura de comunicación

1. **Flutter (Dart)**: Utiliza el paquete `watch_connectivity` para enviar y recibir mensajes.
2. **WatchOS (Swift)**: Implementa `WCSessionDelegate` para manejar la comunicación.

### Formato de mensajes

Los mensajes se envían como maps (diccionarios) con una estructura simple:

- **Mensajes del Apple Watch a Flutter**:
  ```
  {
    "shotDetected": true,
    "timestamp": 1687654321.123
  }
  ```

- **Mensajes de Flutter al Apple Watch**:
  ```
  {
    "action": "startMonitoring"
  }
  ```

### Configuración requerida

Para utilizar esta integración, asegúrate de:

1. Tener un Apple Watch emparejado con el iPhone.
2. Tener la extensión Watch instalada junto con la aplicación iOS.
3. Añadir el paquete `watch_connectivity: ^0.2.1+1` a tu `pubspec.yaml`.

## Requisitos

- iOS 13.0+
- WatchOS 6.0+
- Flutter 3.0+

## Instalación

1. Clona este repositorio
2. Ejecuta `flutter pub get`
3. Abre el proyecto en Xcode para configurar la extensión del Watch

## Desarrollo

Este proyecto sigue la arquitectura MVVM (Model-View-ViewModel) con Provider para la gestión del estado.
