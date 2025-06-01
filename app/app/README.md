# SmartShot Basketball Tracker

Aplicación para seguimiento y análisis de tiros de baloncesto, que detecta y graba jugadas usando sensores de movimiento (Apple Watch) y sensores ultrasónicos (ESP32), con grabación automática de video y estadísticas avanzadas.

---

## Índice

1. [Resumen del Proyecto](#resumen)
2. [Arquitectura General (MVVM + Provider)](#arquitectura)
3. [Sensores y Detección](#sensores)
   - [Apple Watch (Movimiento)](#watch)
   - [ESP32 (Sensor ultrasónico)](#esp32)
4. [Modelos de Datos](#modelos)
5. [Almacenamiento y Persistencia](#storage)
6. [Gestión de Sesiones](#sesiones)
7. [UI: Ejemplos de Frontend](#ui)
8. [Análisis de Jugadas](#analisis)
9. [Ejemplo de Flujo Completo](#flujo)
10. [Notas y Consejos](#notas)

---

## 1. <a name="resumen"></a>Resumen del Proyecto

SmartShot es una app para grabar, analizar y almacenar jugadas de baloncesto. Detecta automáticamente tiros buenos y malos usando dos fuentes:
- **Apple Watch**: Detecta el movimiento del brazo.
- **ESP32**: Detecta el paso del balón por el aro con un sensor ultrasónico.

La app graba los últimos 10 segundos de video por cada jugada y almacena los clips junto con los resultados.

---

## 2. <a name="arquitectura"></a>Arquitectura General (MVVM + Provider)

La app sigue el patrón **MVVM** (Modelo-Vista-ViewModel) y usa **Provider** para la gestión de estado.

```
lib/
  features/
    camera/                # Lógica y UI de la cámara
    dashboard/             # Pantallas principales
    shared/
      analysis/            # Lógica de análisis de jugadas
      bluetooth/           # Conexión con ESP32 y Watch
      connectivity/        # Estado de conectividad
      sessions/            # Modelos, repositorio y lógica de sesiones
```

**Diagrama:**

```
[UI Widgets] <-> [ViewModels] <-> [Services/Repositorios] <-> [Modelos]
```

- **Provider** inyecta los ViewModels en la UI.
- Los ViewModels notifican cambios a la UI.
- Los servicios encapsulan la lógica de negocio y acceso a hardware.

---

## 3. <a name="sensores"></a>Sensores y Detección

### <a name="watch"></a>Apple Watch

- Detecta el movimiento de tiro usando la app watchOS.
- Envía eventos a la app Flutter vía BLE/WatchConnectivity.

**Ejemplo de manejo de eventos:**
```dart
void _handleWatchMessage(Map<String, dynamic> message) {
  final action = message['action'] as String?;
  if (action == 'shotDetected') {
    // Se detectó un tiro desde el Watch
    _watchShotDetected = true;
    notifyListeners();
  }
}
```

### <a name="esp32"></a>ESP32 (Sensor ultrasónico)

- Detecta si el balón pasa por el aro.
- Se conecta vía Bluetooth BLE.
- Envía eventos de tiro exitoso.

**Ejemplo de conexión y detección:**
```dart
await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
if (r.device.advName.toLowerCase().contains('esp32')) {
  await _connectToEsp32(r.device);
}
```

---

## 4. <a name="modelos"></a>Modelos de Datos

### Modelo de Sesión

```dart
@HiveType(typeId: 0)
class SessionModel extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) final DateTime dateTime;
  @HiveField(2) final int durationInSeconds;
  @HiveField(3) final int totalShots;
  @HiveField(4) final int successfulShots;
  @HiveField(5) final List<ShotClip> shotClips;
}
```

### Modelo de Clip de Tiro

```dart
@HiveType(typeId: 1)
class ShotClip extends HiveObject {
  @HiveField(0) final String id;
  @HiveField(1) final DateTime timestamp;
  @HiveField(2) final bool isSuccessful;
  @HiveField(3) final String videoPath;
  @HiveField(4) final double? confidenceScore;
  @HiveField(5) final ShotDetectionType detectionType;
}
```

### Tipos de Detección

```dart
@HiveType(typeId: 2)
enum ShotDetectionType {
  sensor,   // ESP32
  camera,   // Visión por computadora
  manual,   // Usuario
  watch     // Apple Watch
}
```

---

## 5. <a name="storage"></a>Almacenamiento y Persistencia

- **Hive** se usa para persistir sesiones y clips.
- Los videos se guardan en el almacenamiento interno.

**Repositorio de sesiones:**
```dart
class SessionRepository {
  Future<void> saveSession(SessionModel session);
  Future<List<SessionModel>> getAllSessions();
  Future<void> deleteSession(String id);
  Future<String> getNewVideoFilePath();
}
```

---

## 6. <a name="sesiones"></a>Gestión de Sesiones

- Un ViewModel controla el ciclo de vida de la sesión.
- Se pueden iniciar, pausar, reanudar y finalizar sesiones.
- Cada tiro detectado se registra con su video y resultado.

**Ejemplo de uso en ViewModel:**
```dart
Future<void> startSession() async {
  _sessionStartTime = DateTime.now();
  _isSessionActive = true;
  _pendingShots.clear();
  _startTimer();
  _setState(SessionState.active);
}
```

---

## 7. <a name="ui"></a>UI: Ejemplos de Frontend

### Dashboard Principal

```dart
class SmartShotHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SmartShot')),
      body: TabBarView(
        children: [
          _buildHomeTab(),
          SessionsHistoryScreen(),
        ],
      ),
    );
  }
}
```

### Estado de Conectividad

```dart
class ConnectivityStatusWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityService>(
      builder: (context, service, child) {
        return Row(
          children: [
            Icon(Icons.bluetooth, color: service.esp32Status == ConnectivityStatus.connected ? Colors.green : Colors.red),
            Icon(Icons.watch, color: service.watchStatus == ConnectivityStatus.connected ? Colors.green : Colors.red),
          ],
        );
      },
    );
  }
}
```

### Vista de Cámara

```dart
class CameraView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<CameraViewModel>(
      builder: (context, cameraVM, child) {
        if (!cameraVM.isInitialized) return CircularProgressIndicator();
        return CameraPreview(cameraVM.cameraController!);
      },
    );
  }
}
```

### Historial de Sesiones

```dart
ListView.builder(
  itemCount: _sessions.length,
  itemBuilder: (context, index) {
    final session = _sessions[index];
    return ListTile(
      title: Text('Sesión: ${session.dateTime}'),
      subtitle: Text('Tiros: ${session.totalShots} - Aciertos: ${session.successfulShots}'),
      onTap: () => _showSessionDetails(session),
    );
  },
)
```

---

## 8. <a name="analisis"></a>Análisis de Jugadas

- El servicio de análisis procesa los videos y detecta tiros buenos/malos.
- Puede usar modelos de ML locales o servicios externos.

**Modelo de resultado de análisis:**
```dart
class AnalysisResult {
  final List<ShotDetection> shotsDetected;
  final AnalysisSummary summary;
}
```

---

## 9. <a name="flujo"></a>Ejemplo de Flujo Completo

1. **Usuario inicia sesión de entrenamiento.**
2. **App conecta con ESP32 y Watch.**
3. **Cuando se detecta un tiro (por movimiento o sensor):**
   - Se graban los últimos 10 segundos de video.
   - Se almacena el clip y el resultado (acierto/fallo).
4. **Al finalizar la sesión:**
   - Se guarda la sesión con todos los tiros.
   - El usuario puede ver el historial y reproducir los videos.

---

## 10. <a name="notas"></a>Notas y Consejos

- **MVVM + Provider**: Mantén la lógica fuera de la UI para facilitar pruebas y escalabilidad.
- **Sensores**: Puedes usar solo uno o ambos sensores para mayor precisión.
- **Persistencia**: Hive es rápido y fácil de usar para modelos simples.
- **UI**: Usa Consumer y Provider para actualizar la UI en tiempo real.
- **FVM**: Usa `fvm flutter run` para asegurar la versión correcta de Flutter.

---

¿Quieres ejemplos más detallados de alguna sección? ¿O necesitas diagramas visuales? ¡Avísame!
