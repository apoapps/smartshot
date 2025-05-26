# 🤖 Guía de OpenPose para SmartShot

## 🔍 ¿Cómo verificar si OpenPose está funcionando?

### Desde la App Flutter
1. **Abrir SmartShot**
2. **Ir a "Iniciar Sesión"** 
3. **Presionar "🔍 Diagnóstico de Métodos"**
4. **Verificar el estado:**
   - ✅ **🤖 OpenPose: Activo** ← Esto es lo que queremos ver
   - ✅ **🌐 Backend Saludable: Activo**

### Desde los Logs del Backend
```bash
# En la terminal donde corre el backend, busca:
✅ OpenPose inicializado correctamente    # ← BUENO
WARNING: OpenPose init failed: No module named 'pyopenpose'  # ← MALO
```

## 🚨 Estado Actual (Según tus logs)
```
❌ OpenPose: NO FUNCIONANDO
✅ Backend Flask: FUNCIONANDO (puerto 5001)
✅ TensorFlow: FUNCIONANDO  
✅ Sensor Arduino: FUNCIONANDO
```

**Problema:** `No module named 'pyopenpose'`

## 🛠️ Solución Rápida

### Opción 1: Instalación Automática (Recomendada)
```bash
# Desde el directorio raíz de tu proyecto
./scripts/install_openpose.sh
```

### Opción 2: Instalación Manual
```bash
# 1. Ir al directorio del backend
cd ai/AI-basketball-analysis

# 2. Activar entorno virtual
source venv/bin/activate

# 3. Instalar OpenPose
pip install pyopenpose

# 4. Si falla, probar alternativa:
pip install openpose-python

# 5. Reiniciar backend
python api_bridge.py
```

### Opción 3: Sin OpenPose (Fallback)
Si OpenPose no se puede instalar, la app seguirá funcionando con:
- **TensorFlow Lite** (detección local)
- **Detección por Color** (fallback)  
- **Sensor Arduino** (siempre disponible)

## 🧪 Verificación Post-Instalación

### 1. Verificar en Terminal
```bash
cd ai/AI-basketball-analysis
source venv/bin/activate
python -c "import pyopenpose; print('✅ OpenPose OK')"
```

### 2. Reiniciar Backend
```bash
# Detener backend actual (Ctrl+C)
# Luego ejecutar:
cd ai/AI-basketball-analysis
source venv/bin/activate  
python api_bridge.py
```

**Buscar en los logs:**
```
✅ OpenPose inicializado correctamente    # ← Esto confirma que funciona
```

### 3. Verificar en App
1. Abrir SmartShot
2. Ir a "Iniciar Sesión"
3. Presionar "🔍 Diagnóstico de Métodos"
4. Verificar: **🤖 OpenPose: Activo**

## 🎯 ¿Qué hace cada método de detección?

### 🤖 OpenPose (Método Principal)
- **Función:** Análisis avanzado de poses y movimientos
- **Ventajas:** Más preciso para analizar técnica de tiro
- **Requisitos:** Backend Python con OpenPose instalado

### 🧠 TensorFlow Lite (Fallback 1)
- **Función:** Detección rápida local de objetos
- **Ventajas:** Funciona sin conexión a internet
- **Requisitos:** Modelo .tflite en assets/

### 🎨 Detección Color (Fallback 2)  
- **Función:** Detecta pelota por color naranja
- **Ventajas:** Siempre disponible, muy rápido
- **Requisitos:** Ninguno

### 📡 Sensor Arduino (Siempre activo)
- **Función:** Sensor físico en el aro que detecta encestes
- **Ventajas:** 100% preciso para detección de aciertos
- **Requisitos:** Arduino conectado via Bluetooth

## 🔄 Flujo Híbrido Recomendado
1. **OpenPose** analiza la técnica de tiro → Si detecta intento de tiro
2. **Arduino** confirma si fue acierto o falla → Graba video
3. **TensorFlow Lite** como backup si OpenPose falla
4. **Color** como último recurso

## 📱 ¿Cómo saber qué método está activo?
En la pantalla de sesión verás indicadores:
- **Método Activo:** Se muestra en la parte superior
- **Diagnóstico:** Botón "🔍 Diagnóstico de Métodos"
- **Logs:** Mensajes en la consola de debug

## 🆘 Resolución de Problemas

### Problema: "No module named 'pyopenpose'"
**Solución:** Ejecutar `./scripts/install_openpose.sh`

### Problema: Backend no responde
**Solución:** Verificar que esté corriendo en puerto 5001
```bash
curl http://localhost:5001/health
```

### Problema: Arduino no detecta
**Solución:** Verificar conexión Bluetooth en la app

### Problema: TensorFlow Lite no funciona  
**Solución:** Verificar que existe `assets/models/basketball_detector.tflite` 