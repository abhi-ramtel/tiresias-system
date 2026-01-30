//
//  ContentView.swift
//  TiresiasApp
//
//  Main view with camera preview, mini map, and accessibility controls
//

import SwiftUI
import AVFoundation
import Foundation
import MapKit

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var navigationAgent = NavigationAgent()
    @StateObject private var realtimeNavManager = RealTimeNavigationManager()
    @ObservedObject private var locationManager = LocationManager.shared
    
    // Settings - Uses SERVER_IP env var (export SERVER_IP=`ipconfig getifaddr en0`)
    @AppStorage("serverIP") private var serverIP: String = ProcessInfo.processInfo.environment["SERVER_IP"] ?? "10.84.15.64"
    @State private var showingSettings = false
    
    // Map states
    @State private var isMapExpanded = false
    @State private var showNavigationMap = false
    @State private var showPathGuidance = false
    
    // Navigation state
    @State private var isVoiceNavigationActive = false
    
    var body: some View {
        ZStack {
            // MARK: - Camera Layer
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            // MARK: - Path Guidance Overlay (when enabled)
            if showPathGuidance && webSocketManager.isConnected {
                PathGuidanceOverlayView(
                    webSocketManager: webSocketManager,
                    cameraManager: cameraManager
                )
                .transition(.opacity)
            }
            
            // MARK: - Overlay UI
            VStack {
                // Top bar with status
                HStack(alignment: .top) {
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
                    
                    // Settings and Map in top-right
                    VStack(alignment: .trailing, spacing: 8) {
                        // Settings button
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Settings")
                        
                        // Route status badge (when navigating)
                        if realtimeNavManager.hasActiveRoute {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                Text("Route Ready")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.6))
                            .cornerRadius(8)
                        }
                        
                        // Mini Map below settings
                        MiniMapView(navigationManager: realtimeNavManager, isExpanded: $isMapExpanded)
                            .frame(width: 120, height: 120)
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    }
                }
                .padding()
                
                Spacer()
                
                // Navigation status bar (when navigating)
                if realtimeNavManager.isNavigating {
                    navigationStatusBar
                }
                
                // Stats overlay
                if webSocketManager.isConnected {
                    statsOverlay
                }
                
                // Control buttons
                controlButtons
                    .padding(.bottom, 40)
            }
            
            // MARK: - Expanded Map Sheet
            if isMapExpanded {
                ExpandedMapView(navigationManager: realtimeNavManager, isPresented: $isMapExpanded)
                    .transition(.move(edge: .bottom))
                    .zIndex(100)
            }
            
            // MARK: - Full Navigation Map (Apple Maps style)
            if showNavigationMap {
                NavigationMapView(
                    navigationManager: realtimeNavManager,
                    isPresented: $showNavigationMap
                )
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .onAppear {
            setupOnAppear()
        }
        .onChange(of: realtimeNavManager.hasActiveRoute) { _, hasRoute in
            // Close navigation map if navigation was stopped
            if !hasRoute {
                showNavigationMap = false
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
    
    // MARK: - Navigation Status Bar
    
    private var navigationStatusBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: directionIcon(for: realtimeNavManager.currentInstruction))
                    .font(.title)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading) {
                    Text(realtimeNavManager.currentInstruction.rawValue)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    if realtimeNavManager.distanceToNextTurn > 0 {
                        Text("\(Int(realtimeNavManager.distanceToNextTurn))m to next turn")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Expand to full map button
                Button(action: {
                    showNavigationMap = true
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Expand navigation map")
                .padding(.trailing, 8)
                
                Button(action: {
                    realtimeNavManager.stopNavigation()
                    isVoiceNavigationActive = false
                    showNavigationMap = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Stop navigation")
            }
            
            Text("→ \(realtimeNavManager.destinationName)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
        .background(Color.blue.opacity(0.8))
        .cornerRadius(12)
        .padding(.horizontal)
        .onTapGesture {
            // Tap anywhere on the bar to expand
            showNavigationMap = true
        }
        .accessibilityHint("Tap to expand navigation map")
    }
    
    // MARK: - Stats Overlay
    
    private var statsOverlay: some View {
        HStack(spacing: 20) {
            StatView(title: "FPS", value: "\(cameraManager.currentFPS)")
            StatView(title: "Frames", value: "\(webSocketManager.framesSent)")
            StatView(title: "Latency", value: "\(webSocketManager.latencyMs)ms")
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }
    
    // MARK: - Control Buttons
    
    private var controlButtons: some View {
        VStack(spacing: 16) {
            // Primary row
            HStack(spacing: 20) {
                // Connect/Disconnect
                ControlButton(
                    icon: webSocketManager.isConnected ? "wifi.slash" : "wifi",
                    label: webSocketManager.isConnected ? "Disconnect" : "Connect",
                    color: webSocketManager.isConnected ? .red : .green,
                    action: toggleConnection
                )
                
                // Voice Navigation
                ControlButton(
                    icon: isVoiceNavigationActive ? "mic.fill" : "mic",
                    label: "Navigate",
                    color: isVoiceNavigationActive ? .orange : .purple,
                    action: startVoiceNavigation
                )
                .accessibilityHint("Tap and speak your destination")
                
                // Stream toggle
                ControlButton(
                    icon: cameraManager.isStreaming ? "stop.fill" : "play.fill",
                    label: cameraManager.isStreaming ? "Stop" : "Stream",
                    color: cameraManager.isStreaming ? .orange : .blue,
                    action: toggleStreaming
                )
                .disabled(!webSocketManager.isConnected)
                .opacity(webSocketManager.isConnected ? 1.0 : 0.5)
            }
            
            // Secondary row - Accessibility features
            HStack(spacing: 20) {
                // Path Guidance toggle
                ControlButton(
                    icon: showPathGuidance ? "eye.fill" : "eye",
                    label: showPathGuidance ? "Guidance On" : "Guidance",
                    color: showPathGuidance ? .green : .gray,
                    size: .small,
                    action: {
                        showPathGuidance.toggle()
                        webSocketManager.setGuidanceEnabled(showPathGuidance)
                    }
                )
                .disabled(!webSocketManager.isConnected)
                .opacity(webSocketManager.isConnected ? 1.0 : 0.5)
                .accessibilityLabel("Toggle path guidance")
                .accessibilityHint("Shows real-time obstacle detection and direction guidance")
                
                // Announce heading
                ControlButton(
                    icon: "location.north.fill",
                    label: "Heading",
                    color: .cyan,
                    size: .small,
                    action: {
                        realtimeNavManager.announceHeading()
                    }
                )
                .accessibilityLabel("Announce current heading")
                
                // Announce status
                ControlButton(
                    icon: "speaker.wave.2.fill",
                    label: "Status",
                    color: .indigo,
                    size: .small,
                    action: {
                        realtimeNavManager.announceCurrentStatus()
                    }
                )
                .accessibilityLabel("Announce navigation status")
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupOnAppear() {
        cameraManager.checkPermissions()
        cameraManager.onFrameCaptured = { imageData in
            webSocketManager.sendFrame(imageData)
        }
        navigationAgent.requestPermissions()
        locationManager.requestPermissions()
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
    
    private func startVoiceNavigation() {
        guard !isVoiceNavigationActive else { return }
        
        isVoiceNavigationActive = true
        
        // Start listening with callback to trigger real-time navigation
        navigationAgent.startListeningWithCallback { [self] destination in
            if !destination.isEmpty {
                // Start real-time turn-by-turn navigation like Apple Maps
                realtimeNavManager.startNavigation(to: destination)
                
                // Show the full-screen navigation map when route is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if self.realtimeNavManager.hasActiveRoute && !self.showNavigationMap {
                        self.showNavigationMap = true
                    }
                }
            }
            DispatchQueue.main.async {
                self.isVoiceNavigationActive = false
            }
        }
        
        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if self.isVoiceNavigationActive {
                self.isVoiceNavigationActive = false
            }
        }
    }
    
    private func directionIcon(for direction: NavigationDirection) -> String {
        switch direction {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .straight: return "arrow.up"
        case .arrived: return "flag.checkered"
        case .unknown: return "questionmark"
        }
    }
    
    private func announceAccessibility(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Control Button

struct ControlButton: View {
    let icon: String
    let label: String
    let color: Color
    var size: ButtonSize = .regular
    let action: () -> Void
    
    enum ButtonSize {
        case small, regular
        
        var dimension: CGFloat {
            switch self {
            case .small: return 60
            case .regular: return 80
            }
        }
        
        var iconFont: Font {
            switch self {
            case .small: return .title3
            case .regular: return .title
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(size.iconFont)
                Text(label)
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(width: size.dimension, height: size.dimension)
            .background(color)
            .clipShape(Circle())
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
                    
                    Text("Enter your Mac's IP address.\nRun: ipconfig getifaddr en0")
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
