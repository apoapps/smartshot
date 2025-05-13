#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>

// Pin donde está conectado el LED
#define LED_PIN 13

// UUIDs para el servicio BLE y características
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;
bool ledState = false;

// Declaración previa de funciones
void processCommand(const char* jsonStr);
void sendLedState();

// Callbacks para manejar conexión/desconexión
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Dispositivo conectado");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Dispositivo desconectado");
      
      // Reiniciar publicidad cuando se desconecta para poder reconectar
      pServer->getAdvertising()->start();
    }
};

// Callbacks para manejar escritura en característica
class CharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string value = pCharacteristic->getValue();
      
      if (value.length() > 0) {
        Serial.println("Comando recibido:");
        Serial.println(value.c_str());
        
        // Procesar el comando JSON
        processCommand(value.c_str());
      }
    }
};

void setup() {
  // Inicializar comunicación serial
  Serial.begin(115200);
  
  // Inicializar pin LED como salida
  pinMode(LED_PIN, OUTPUT);
  
  // Crear dispositivo BLE
  BLEDevice::init("ESP32-SmartShot");
  
  // Crear servidor BLE
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  // Crear servicio BLE
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Crear característica BLE
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_INDICATE
                    );
  
  // Agregar descriptor
  pCharacteristic->addDescriptor(new BLE2902());
  
  // Configurar callbacks para la característica
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  
  // Iniciar servicio
  pService->start();
  
  // Iniciar publicidad
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // funciones para ayudar con iPhone
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("BLE listo, esperando conexiones...");
}

void loop() {
  // El procesamiento principal ocurre en los callbacks
  delay(100);
}

// Procesar comando recibido
void processCommand(const char* jsonStr) {
  StaticJsonDocument<200> doc;
  
  DeserializationError error = deserializeJson(doc, jsonStr);
  
  if (error) {
    Serial.print("Error al deserializar JSON: ");
    Serial.println(error.c_str());
    return;
  }
  
  if (doc.containsKey("command")) {
    const char* command = doc["command"];
    
    if (strcmp(command, "led") == 0) {
      if (doc.containsKey("state")) {
        int state = doc["state"];
        digitalWrite(LED_PIN, state);
        ledState = state;
        sendLedState();
      }
    } else if (strcmp(command, "status") == 0) {
      sendLedState();
    }
  }
}

// Enviar estado del LED como respuesta
void sendLedState() {
  if (deviceConnected) {
    StaticJsonDocument<200> doc;
    
    doc["status"] = "led";
    doc["state"] = digitalRead(LED_PIN);
    
    String jsonResponse;
    serializeJson(doc, jsonResponse);
    
    pCharacteristic->setValue(jsonResponse.c_str());
    pCharacteristic->notify();
    
    Serial.print("Enviando estado: ");
    Serial.println(jsonResponse);
  }
}