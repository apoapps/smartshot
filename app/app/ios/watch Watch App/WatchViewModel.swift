import Foundation
import WatchConnectivity
import CoreMotion
import SwiftUI

class WatchViewModel: NSObject, ObservableObject {
    var session: WCSession
    let motionManager = CMMotionManager()
    @Published var shotDetected = false
    @Published var lastShotTime = Date()
    @Published var isMonitoring = false
    @Published var connectionStatus = "Desconectado"
    
    // Sensibilidad para la detección del movimiento (ajustable)
    private let accelerationThreshold: Double = 2.5
    
    // Tiempo mínimo entre detecciones (para evitar falsos positivos)
    private let detectionCooldown: TimeInterval = 1.5
    
    init(session: WCSession = .default) {
        self.session = session
        super.init()
        
        // Configurar y activar la sesión de WatchConnectivity
        self.session.delegate = self
        session.activate()
        
        // Verificar y actualizar el estado de la conexión
        updateConnectionStatus()
    }
    
    func updateConnectionStatus() {
        connectionStatus = session.isReachable ? "Conectado" : "Desconectado"
        print("Estado de conexión: \(connectionStatus)")
    }
    
    func sendDataMessage(data: [String: Any] = [:]) {
        // Siempre enviamos incluso si no es reachable, ya que 
        // el sistema manejará la entrega cuando sea posible
        print("Enviando mensaje: \(data)")
        session.sendMessage(data, replyHandler: { reply in
            print("Respuesta recibida: \(reply)")
        }, errorHandler: { error in
            print("Error enviando mensaje: \(error.localizedDescription)")
        })
    }
    
    // Comienza a monitorear movimientos de tiro
    func startMonitoring() {
        guard !isMonitoring, motionManager.isAccelerometerAvailable else { 
            print("No se puede iniciar monitoreo: ya activo o acelerómetro no disponible")
            return 
        }
        
        print("Iniciando monitoreo de tiros")
        
        motionManager.accelerometerUpdateInterval = 0.05 // Más frecuente para mayor precisión
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data, error == nil else { return }
            
            // Detectar el movimiento característico de un tiro de baloncesto
            let acceleration = sqrt(
                pow(data.acceleration.x, 2) +
                pow(data.acceleration.y, 2) +
                pow(data.acceleration.z, 2)
            ) - 1.0 // Restar gravedad
            
            // Si detectamos un movimiento brusco (tiro) y ha pasado suficiente tiempo desde el último
            if acceleration > self.accelerationThreshold && 
               Date().timeIntervalSince(self.lastShotTime) > self.detectionCooldown {
                
                print("¡TIRO DETECTADO! Aceleración: \(acceleration)")
                
                self.shotDetected = true
                self.lastShotTime = Date()
                
                // Enviar a la app iOS
                self.sendDataMessage(data: [
                    "shotDetected": true,
                    "timestamp": self.lastShotTime.timeIntervalSince1970
                ])
                
                // Feedback háptico
                WKHapticType.notification
                let device = WKInterfaceDevice.current()
                device.play(.notification)
                
                // Resetear después de un momento
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.shotDetected = false
                }
            }
        }
        
        isMonitoring = true
        sendDataMessage(data: ["monitoring": true])
    }
    
    // Detiene el monitoreo
    func stopMonitoring() {
        guard isMonitoring else { 
            print("No se puede detener: monitoreo no activo")
            return 
        }
        
        print("Deteniendo monitoreo de tiros")
        
        motionManager.stopAccelerometerUpdates()
        isMonitoring = false
        sendDataMessage(data: ["monitoring": false])
    }
    
    // Para pruebas - Simular un tiro
    func simulateShot() {
        print("Simulando detección de tiro")
        shotDetected = true
        lastShotTime = Date()
        
        // Enviar a la app iOS
        sendDataMessage(data: [
            "shotDetected": true,
            "timestamp": lastShotTime.timeIntervalSince1970
        ])
        
        // Feedback háptico
        WKInterfaceDevice.current().play(.notification)
        
        // Resetear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.shotDetected = false
        }
    }
}

extension WatchViewModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            print("Sesión activada: \(activationState.rawValue), error: \(error?.localizedDescription ?? "ninguno")")
            self.updateConnectionStatus()
            
            // Notificar estado inicial
            if activationState == .activated {
                self.sendDataMessage(data: ["monitoring": self.isMonitoring])
            }
        }
    }
    
    // Recibir mensajes desde la app iOS
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            print("Mensaje recibido: \(message)")
            
            guard let action = message["action"] as? String else {
                print("Mensaje sin acción")
                return
            }
            
            switch action {
            case "startMonitoring":
                print("Comando recibido: startMonitoring")
                self.startMonitoring()
                
            case "stopMonitoring":
                print("Comando recibido: stopMonitoring")
                self.stopMonitoring()
                
            case "sessionStatus":
                let isActive = message["isActive"] as? Bool ?? false
                print("Comando recibido: sessionStatus - isActive: \(isActive)")
                if isActive {
                    self.startMonitoring()
                } else {
                    self.stopMonitoring()
                }
                
            case "test":
                print("Comando de prueba recibido")
                // Responder al mensaje de prueba
                self.sendDataMessage(data: ["testResponse": true, "status": "ok"])
                
            case "ping":
                print("Comando ping recibido")
                // Responder al ping
                self.sendDataMessage(data: ["pong": true, "status": "ok"])
                
            default:
                print("Comando desconocido: \(action)")
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        // Procesar el mensaje normalmente
        self.session(session, didReceiveMessage: message)
        
        // Responder
        replyHandler(["status": "received"])
    }
    
    // Métodos obligatorios de WCSessionDelegate
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateConnectionStatus()
        }
    }
} 