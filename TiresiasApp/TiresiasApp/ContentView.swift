//
//  ContentView.swift
//  TiresiasApp
//
//  Main view with camera preview and connection controls
//

import SwiftUI
import AVFoundation
import Foundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var webSocketManager = WebSocketManager()
    
    // @AppStorage("serverIP") private var serverIP: String = "10.84.104.88" // Change to you ip
    @AppStorage("serverIP") private var serverIP: String = ProcessInfo.processInfo.environment["IP_ADDRESS"] ?? "192.168.1.218" // add it to your env file
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            if let depth = webSocketManager.depthOverlay {
                DepthMeshView(depth: depth)
                    .ignoresSafeArea()
                    .opacity(0.45)
            }
            
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
            cameraManager.onFrameCaptured = { imageData, depthPacket in
                webSocketManager.sendFrame(imageData, depth: depthPacket)
            }
        }
        .onChange(of: webSocketManager.depthOverlay != nil) { hasDepth in
            print("ℹ️ Depth overlay active: \(hasDepth)")
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

struct DepthMeshView: View {
    let depth: DepthOverlayData

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard depth.width > 0, depth.height > 0 else { return }
                guard let (minV, maxV) = depthMinMax(), maxV > minV else { return }

                let step = 2
                let cellWidth = size.width / CGFloat(depth.width)
                let cellHeight = size.height / CGFloat(depth.height)
                let minF = CGFloat(minV)
                let maxF = CGFloat(maxV)

                for y in stride(from: 0, to: depth.height, by: step) {
                    for x in stride(from: 0, to: depth.width, by: step) {
                        let idx = y * depth.width + x
                        let value = depth.values[idx]
                        if value == 0 { continue }
                        let t = (CGFloat(value) - minF) / (maxF - minF)
                        let color = depthColor(t)
                        let rect = CGRect(
                            x: CGFloat(x) * cellWidth,
                            y: CGFloat(y) * cellHeight,
                            width: cellWidth * CGFloat(step),
                            height: cellHeight * CGFloat(step)
                        )
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
    }

    private func depthMinMax() -> (UInt16, UInt16)? {
        var minV: UInt16 = .max
        var maxV: UInt16 = .min
        for v in depth.values where v > 0 {
            if v < minV { minV = v }
            if v > maxV { maxV = v }
        }
        if minV == .max || maxV == .min { return nil }
        return (minV, maxV)
    }

    private func depthColor(_ t: CGFloat) -> Color {
        let clamped = min(max(t, 0), 1)
        return Color(red: clamped, green: 0.2, blue: 1.0 - clamped)
    }
}

#Preview {
    ContentView()
}
