//
//  ContentView.swift
//  watch Watch App
//
//  Created by Alejandro Apodaca on 26/05/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel: WatchViewModel = WatchViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("SmartShot")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                
                // Estado de conexión
                HStack {
                    Circle()
                        .fill(viewModel.connectionStatus == "Conectado" ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(viewModel.connectionStatus)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                Divider()
                
                // Estado de monitoreo
                if viewModel.isMonitoring {
                    HStack {
                        Text("Monitoreando")
                            .font(.body)
                        
                        Circle()
                            .fill(Color.green)
                            .frame(width: 10, height: 10)
                            .opacity(viewModel.shotDetected ? 0.3 : 1.0)
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true),
                                value: viewModel.shotDetected
                            )
                    }
                    .padding(.vertical, 4)
                    
                    Button(action: {
                        viewModel.stopMonitoring()
                    }) {
                        Text("Detener")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Text("Inactivo")
                        .font(.body)
                        .foregroundColor(.gray)
                        .padding(.vertical, 4)
                    
                    Button(action: {
                        viewModel.startMonitoring()
                    }) {
                        Text("Iniciar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }
                
                // Feedback de tiro detectado
                if viewModel.shotDetected {
                    Text("¡Tiro detectado!")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fontWeight(.bold)
                        .padding(.top, 5)
                }
                
                Divider()
                
                // Botón para simular un tiro (testing)
                Button(action: {
                    viewModel.simulateShot()
                }) {
                    Label("Simular tiro", systemImage: "basketball.fill")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .padding(.top, 4)
                
                // Mostrar último tiempo de detección
                Text("Último: \(formatTime(viewModel.lastShotTime))")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
        }
    }
    
    // Formatear tiempo para mostrar solo hora:minuto:segundo
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
