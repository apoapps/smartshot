# Configuración del Apple Watch - SmartShot

## Problema Actual

El error `WCErrorCodeWatchAppNotInstalled` indica que la aplicación del Apple Watch no está instalada o no está configurada correctamente.

## Solución

### 1. Verificar Bundle Identifiers

✅ **CORREGIDO**: El bundle identifier en `ios/watch Watch App/Info.plist` ha sido actualizado de:
- ❌ `com.example.app.watchkitapp` 
- ✅ `com.apoapps.smartshot.app.watchkitapp`

### 2. Compilar e Instalar la App del Watch

Ejecuta el siguiente script para compilar e instalar la aplicación del Apple Watch:

```bash
./build_watch_app.sh
```

### 3. Pasos Manuales Alternativos

Si el script no funciona, puedes hacerlo manualmente:

1. **Abrir Xcode**:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Seleccionar el esquema del Watch**:
   - En Xcode, selecciona el esquema "watch Watch App"
   - Asegúrate de que tu Apple Watch esté conectado y emparejado

3. **Compilar e instalar**:
   - Presiona Cmd+R para compilar e instalar
   - O usa Product → Run

### 4. Verificar Instalación

1. **En tu Apple Watch**:
   - Busca la aplicación "SmartShot" en la pantalla de inicio
   - Si no aparece, ve a la app Watch en tu iPhone
   - En la pestaña "Mi Watch", busca SmartShot y asegúrate de que esté instalada

2. **Abrir la aplicación**:
   - Toca la aplicación SmartShot en tu Apple Watch
   - Debería mostrar la interfaz de monitoreo

### 5. Verificar Conectividad

Una vez instalada la aplicación:

1. **Ejecutar la app de Flutter**:
   ```bash
   flutter run
   ```

2. **Verificar logs**:
   - Los mensajes de error `WCErrorCodeWatchAppNotInstalled` deberían desaparecer
   - Deberías ver mensajes como: `📱 App del Watch instalada: true`

## Troubleshooting

### Si la aplicación no se instala:

1. **Verificar emparejamiento**:
   - Asegúrate de que tu Apple Watch esté emparejado con tu iPhone
   - Ve a Configuración → General → Apple Watch en tu iPhone

2. **Verificar permisos de desarrollador**:
   - En tu Apple Watch: Configuración → General → Gestión de dispositivos
   - Confía en tu certificado de desarrollador

3. **Reiniciar dispositivos**:
   - Reinicia tu Apple Watch
   - Reinicia tu iPhone
   - Vuelve a intentar la instalación

### Si la aplicación se instala pero no se comunica:

1. **Verificar que la app esté abierta**:
   - Abre manualmente la aplicación SmartShot en tu Apple Watch
   - Déjala en primer plano

2. **Verificar conectividad**:
   - Asegúrate de que ambos dispositivos estén en la misma red WiFi
   - O que el Bluetooth esté activado

## Cambios Realizados

### Archivos Modificados:

1. **`ios/watch Watch App/Info.plist`**:
   - Corregido bundle identifier

2. **`lib/features/shared/connectivity/connectivity_service.dart`**:
   - Mejorado manejo de errores
   - Agregada verificación de instalación de app

3. **`lib/features/shared/watch/watch_service.dart`**:
   - Agregada verificación de instalación antes de enviar mensajes
   - Implementado throttling de errores para evitar spam
   - Mejorado manejo de excepciones

4. **`build_watch_app.sh`**:
   - Script automatizado para compilar e instalar la app del Watch

## Estado Esperado

Después de seguir estos pasos, deberías ver:

```
📱 Estado Apple Watch - Emparejado: true, Alcanzable: true, App instalada: true
✅ Comunicación con app del Watch: OK
```

En lugar de:

```
WCSession counterpart app not installed
WCErrorCodeWatchAppNotInstalled
``` 