#include <Arduino.h>
#include <NimBLEDevice.h>
#include <ArduinoJson.h>


//for run: pio run -t upload
//for monitor: pio device monitor
// Pines del sensor ultrasónico
#define TRIG_PIN 13
#define ECHO_PIN 12

// UUIDs BLE
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// Constantes para medición
#define MAX_DISTANCE_FOR_HIT 20  // Distancia máxima para contar como acierto (cm)
#define MAX_VALID_DISTANCE 400  // Distancia máxima válida para el sensor (cm)
#define MEASUREMENTS_AVG 3      // Número de mediciones para promediar

NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;

// Variables de estado
unsigned int aciertos = 0;
bool lastHit = false;
float lastReportedDistance = -1;  // Última distancia enviada
unsigned long lastNotificationTime = 0;
const int minNotificationInterval = 100; // Intervalo mínimo entre notificaciones (ms)

// Función para medir distancia con el sensor ultrasónico (más precisa)
float measureDistance() {
  // Tomar múltiples muestras y promediar para mayor precisión
  float totalDistance = 0;
  int validReadings = 0;
  
  for (int i = 0; i < MEASUREMENTS_AVG; i++) {
    // Limpiar el trigger
    digitalWrite(TRIG_PIN, LOW);
    delayMicroseconds(2);
    
    // Enviar pulso de 10µs
    digitalWrite(TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(TRIG_PIN, LOW);
    
    // Medir duración con tiempo de espera para evitar bloqueos
    unsigned long timeoutTime = micros() + 30000; // 30ms timeout
    
    // Esperar a que el pin ECHO se ponga en HIGH
    while (digitalRead(ECHO_PIN) == LOW) {
      if (micros() > timeoutTime) {
        break; // Timeout, salir del bucle
      }
    }
    
    unsigned long startTime = micros();
    
    // Esperar a que el pin ECHO se ponga en LOW
    while (digitalRead(ECHO_PIN) == HIGH) {
      if (micros() > timeoutTime) {
        break; // Timeout, salir del bucle
      }
    }
    
    unsigned long endTime = micros();
    
    // Calcular duración y distancia
    if (endTime > startTime && endTime < timeoutTime) {
      unsigned long duration = endTime - startTime;
      float distance = duration * 0.034 / 2.0;
      
      // Solo considerar lecturas válidas
      if (distance > 0 && distance < MAX_VALID_DISTANCE) {
        totalDistance += distance;
        validReadings++;
      }
    }
    
    // Breve pausa entre mediciones
    delayMicroseconds(50);
  }
  
  // Calcular promedio si hay lecturas válidas
  if (validReadings > 0) {
    return totalDistance / validReadings;
  } else {
    return MAX_VALID_DISTANCE; // Valor por defecto si no hay lecturas válidas
  }
}

// Enviar datos por BLE
void sendSensorData(float distancia) {
  if (!deviceConnected) return;
  
  // No enviar notificaciones demasiado frecuentes
  unsigned long currentTime = millis();
  if (currentTime - lastNotificationTime < minNotificationInterval) {
    return;
  }
  
  // Crear JSON con los datos
  StaticJsonDocument<200> doc;
  doc["status"] = "sensor";
  doc["distancia"] = distancia;
  doc["aciertos"] = aciertos;
  
  // Serializar a String
  String jsonResponse;
  serializeJson(doc, jsonResponse);
  
  // Validar formato JSON
  if (!jsonResponse.startsWith("{") || !jsonResponse.endsWith("}")) {
    Serial.println("ERROR: JSON mal formateado");
    return;
  }
  
  // Convertir a std::string para NimBLE y enviar
  std::string jsonStr(jsonResponse.c_str());
  pCharacteristic->setValue(jsonStr);
  
  // Notificar dispositivo conectado
  pCharacteristic->notify();
  
  // Registrar envío
  Serial.print("Enviando datos - Distancia: ");
  Serial.print(distancia);
  Serial.print(" cm, Aciertos: ");
  Serial.println(aciertos);
  
  // Actualizar tiempo de última notificación
  lastNotificationTime = currentTime;
  lastReportedDistance = distancia;
}

// Callback para conexión BLE
class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Dispositivo conectado");
    }
    void onDisconnect(NimBLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Dispositivo desconectado");
      NimBLEDevice::startAdvertising();
    }
};

// Callback para características BLE
class CharacteristicCallbacks: public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      if (value.length() > 0) {
        Serial.print("Comando recibido: ");
        Serial.println(value.c_str());
        
        // Aquí podrías procesar comandos desde la app
        // Por ejemplo, reiniciar contador de aciertos
        if (value == "reset") {
          aciertos = 0;
          sendSensorData(measureDistance());
        }
      }
    }
};

void setup() {
  // Inicializar comunicación serial
  Serial.begin(115200);
  
  // Configurar pines del sensor
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  digitalWrite(TRIG_PIN, LOW);
  
  Serial.println("\n=== SmartShot ESP32 Iniciado ===");
  
  // Configurar BLE
  NimBLEDevice::init("ESP32-SmartShot");
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  NimBLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      NIMBLE_PROPERTY::READ   |
                      NIMBLE_PROPERTY::WRITE  |
                      NIMBLE_PROPERTY::NOTIFY |
                      NIMBLE_PROPERTY::INDICATE
                    );
  
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pService->start();
  
  // Iniciar publicidad BLE
  NimBLEAdvertising *pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  NimBLEDevice::startAdvertising();
  
  Serial.println("Sensor ultrasónico configurado en pines:");
  Serial.println("- TRIG: Pin " + String(TRIG_PIN));
  Serial.println("- ECHO: Pin " + String(ECHO_PIN));
  Serial.println("BLE listo, esperando conexiones...");
  
  // Enviar datos iniciales
  delay(20);  // Pequeña pausa para estabilizar
  aciertos = 0;
  sendSensorData(measureDistance());
}

void loop() {
  // Medir distancia con función optimizada
  float distancia = measureDistance();
  
  // Variable para controlar si hay que enviar datos
  bool shouldSendUpdate = false;
  
  // Comprobar si la distancia es menor a 4cm para considerar un acierto
  if (distancia < MAX_DISTANCE_FOR_HIT) {
    // Distancia menor a 4cm - se considera acierto
    if (!lastHit) {
      // Nuevo acierto detectado
      aciertos++;
      lastHit = true;
      shouldSendUpdate = true;
      
      // Mensaje de detección
      Serial.print("¡ACIERTO! #");
      Serial.print(aciertos);
      Serial.print(" - Distancia: ");
      Serial.print(distancia);
      Serial.println(" cm");
    }
  } else {
    // Fuera del rango de acierto
    if (lastHit) {
      // Acaba de salir del rango
      lastHit = false;
      shouldSendUpdate = true;
    }
  }
  
  // Enviar actualización si:
  // 1. Hay un cambio significativo en la distancia (>0.5cm)
  // 2. O ha pasado el tiempo máximo desde la última actualización (500ms)
  float distanceDifference = abs(distancia - lastReportedDistance);
  if (shouldSendUpdate || 
      distanceDifference > 0.5 || 
      millis() - lastNotificationTime > 500) {
    sendSensorData(distancia);
  }
  
  // Pequeña pausa para estabilidad y rendimiento
  delay(50);  // 50ms para mediciones más frecuentes
}