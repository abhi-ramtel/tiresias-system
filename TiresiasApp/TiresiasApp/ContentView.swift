//
//  ContentView.swift
//  TiresiasApp
//
//  Main view with camera preview and connection controls
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var webSocketManager = WebSocketManager()
    
    @State private var serverIP: String = "10.84.104.88"
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar with status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        ConnectionStatusView(status: webSocketManager.connectionStatus)
                        if webSocketManager.isConnected {
                            HStack(spacing: 4) {
                                Image(systemName: webSocketManager.connectionMethod == "USB" ? "cable.connector" : "wifi")
                                    .font(.caption2)
                                Text(webSocketManager.connectionMethod)
                                    .font(.caption2)
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                        }
                    }
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding()
                
                Spacer()
                
                // Stats overlay
                if webSocketManager.isConnected {
                    HStack(spacing: 20) {
                        StatView(title: "FPS", value: "\(cameraManager.currentFPS)")
                        StatView(title: "Frames", value: "\(webSocketManager.framesSent)")
                        StatView(title: "Latency", value: "\(webSocketManager.latencyMs)ms")
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                }
                
                // Control buttons
                HStack(spacing: 30) {
                    // Connect/Disconnect button
                    Button(action: toggleConnection) {
                        VStack {
                            Image(systemName: webSocketManager.isConnected ? "wifi.slash" : "wifi")
                                .font(.title)
                            Text(webSocketManager.isConnected ? "Disconnect" : "Connect")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(webSocketManager.isConnected ? Color.red : Color.green)
                        .clipShape(Circle())
                    }
                    
                    // Stream toggle button
                    Button(action: toggleStreaming) {
                        VStack {
                            Image(systemName: cameraManager.isStreaming ? "stop.fill" : "play.fill")
                                .font(.title)
                            Text(cameraManager.isStreaming ? "Stop" : "Stream")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(cameraManager.isStreaming ? Color.orange : Color.blue)
                        .clipShape(Circle())
                    }
                    .disabled(!webSocketManager.isConnected)
                    .opacity(webSocketManager.isConnected ? 1.0 : 0.5)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
            cameraManager.onFrameCaptured = { imageData in
                webSocketManager.sendFrame(imageData)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                serverIP: $serverIP,
                onSave: {
                    webSocketManager.serverIP = serverIP
                }
            )
        }
        .alert("Connection Error", isPresented: $webSocketManager.showError) {
            Button("OK", role: .cancel) { }
            Button("Retry") { connectToServer() }
        } message: {
            Text(webSocketManager.errorMessage)
        }
    }
    
    private func toggleConnection() {
        if webSocketManager.isConnected {
            cameraManager.stopStreaming()
            webSocketManager.disconnect()
        } else {
            connectToServer()
        }
    }
    
    private func connectToServer() {
        webSocketManager.serverIP = serverIP
        webSocketManager.connect()
    }
    
    private func toggleStreaming() {
        if cameraManager.isStreaming {
            cameraManager.stopStreaming()
        } else {
            cameraManager.startStreaming()
        }
    }
}

// MARK: - Supporting Views

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

struct SettingsView: View {
    @Binding var serverIP: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Server Configuration")) {
                    TextField("Server IP Address", text: $serverIP)
                        .keyboardType(.decimalPad)
                    
                    Text("Enter your Mac's IP address. Find it by running:\nipconfig getifaddr en0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Connection Info")) {
                    LabeledContent("Port", value: "8000")
                    LabeledContent("Protocol", value: "WebSocket")
                    LabeledContent("Endpoint", value: "/ws/video")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
