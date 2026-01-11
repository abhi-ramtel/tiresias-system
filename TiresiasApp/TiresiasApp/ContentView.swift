//
//  ContentView.swift
//  TiresiasApp
//
//  Main view with camera preview and connection controls
//

import SwiftUI
import AVFoundation
import Foundation
import UIKit
import CoreLocation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var webSocketManager = WebSocketManager()
    @StateObject private var feedbackManager = AlertFeedbackManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var avoidanceManager = LocalAvoidanceManager()
    @State private var depthMap: DepthMap? = nil
    
    // @AppStorage("serverIP") private var serverIP: String = "10.84.104.88" // Change to you ip
    @AppStorage("serverIP") private var serverIP: String = ProcessInfo.processInfo.environment["IP_ADDRESS"] ?? "192.168.1.218" // add it to your env file
    @AppStorage("settings_fps") private var fpsSetting: Double = 15
    @AppStorage("settings_preset") private var presetSetting: String = "inputPriority"
    @AppStorage("settings_jpeg_quality") private var jpegQualitySetting: Double = 0.15
    @AppStorage("settings_frame_stride") private var frameStrideSetting: Int = 1
    @AppStorage("settings_depth_stride") private var depthStrideSetting: Int = 3
    @AppStorage("settings_depth_mode") private var depthModeSetting: String = DepthMode.off.rawValue
    @AppStorage("settings_haptics_enabled") private var hapticsEnabled: Bool = true
    @AppStorage("settings_alerts_enabled") private var alertsEnabled: Bool = false
    @AppStorage("settings_local_avoidance") private var localAvoidanceEnabled: Bool = true
    @AppStorage("settings_critical_distance_m") private var criticalDistanceSetting: Double = 1.8
    @State private var showingSettings = false
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()
            
            if let depthMap = depthMap {
                DepthMeshView(depthMap: depthMap)
                    .ignoresSafeArea()
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
                
                // Analysis overlay (above stats)
                AnalysisOverlayView(
                    summary: webSocketManager.analysisSummary,
                    warnings: webSocketManager.analysisWarnings,
                    location: webSocketManager.analysisLocation,
                    action: webSocketManager.analysisAction,
                    path: webSocketManager.analysisPath,
                    obstacles: webSocketManager.analysisObstacles
                )
                    .padding(.bottom, 10)

                if alertsEnabled, let alert = webSocketManager.lastAlert {
                    AlertBannerView(alert: alert)
                        .padding(.bottom, 10)
                }
                
                // Stats overlay (small text)
                if webSocketManager.isConnected {
                    Text("fps \(cameraManager.currentFPS)  ·  frames \(webSocketManager.framesSent)  ·  \(webSocketManager.latencyMs)ms")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                }
                
                // Control buttons
                HStack(spacing: 24) {
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
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
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
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    .disabled(!webSocketManager.isConnected)
                    .opacity(webSocketManager.isConnected ? 1.0 : 0.5)

                    Button(action: requestAnalysis) {
                        VStack {
                            Image(systemName: "sparkles")
                                .font(.title)
                            Text("Analyze")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                    .background(Color.purple)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
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
            cameraManager.onDepthUpdated = { depth in
                DispatchQueue.main.async {
                    depthMap = depth
                    if localAvoidanceEnabled {
                        if let alert = avoidanceManager.process(depthMap: depth, criticalDistance: criticalDistanceSetting) {
                            webSocketManager.lastAlert = alert
                            feedbackManager.play(alert: alert, hapticsEnabled: hapticsEnabled)
                        }
                    }
                }
            }
            locationManager.onLocationUpdate = { location in
                webSocketManager.sendJSON([
                    "type": "gps",
                    "lat": location.coordinate.latitude,
                    "lon": location.coordinate.longitude
                ])
            }
            locationManager.start()
            applyPerformanceSettings()
        }
        .onChange(of: webSocketManager.lastAlert?.id) { _ in
            if let alert = webSocketManager.lastAlert {
                feedbackManager.play(alert: alert, hapticsEnabled: hapticsEnabled)
            }
        }
        .onChange(of: webSocketManager.decisionAction) { action in
            feedbackManager.playDecision(action: action, hapticsEnabled: hapticsEnabled)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                serverIP: $serverIP,
                fps: $fpsSetting,
                preset: $presetSetting,
                jpegQuality: $jpegQualitySetting,
                frameStride: $frameStrideSetting,
                depthStride: $depthStrideSetting,
                depthMode: $depthModeSetting,
                hapticsEnabled: $hapticsEnabled,
                alertsEnabled: $alertsEnabled,
                localAvoidanceEnabled: $localAvoidanceEnabled,
                criticalDistance: $criticalDistanceSetting,
                onSave: {
                    webSocketManager.serverIP = serverIP
                    applyPerformanceSettings()
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

    private func requestAnalysis() {
        webSocketManager.sendJSON(["type": "analyze_now"])
    }

    private func applyPerformanceSettings() {
        let requested = depthModeFromSetting(depthModeSetting)
        let resolved = resolveDepthMode(requested)
        if resolved != requested {
            depthModeSetting = resolved.rawValue
        }
        if resolved == .off {
            depthMap = nil
        }
        cameraManager.applySettings(
            targetFPS: fpsSetting,
            preset: presetFromSetting(presetSetting),
            jpegQuality: CGFloat(jpegQualitySetting),
            frameStride: frameStrideSetting,
            depthMode: resolved,
            depthStride: depthStrideSetting
        )
    }

    private func depthModeFromSetting(_ value: String) -> DepthMode {
        DepthMode(rawValue: value) ?? .off
    }

    private func resolveDepthMode(_ mode: DepthMode) -> DepthMode {
        switch mode {
        case .lidar:
            return CameraManager.supportsLiDARDepth() ? .lidar : .off
        case .monocular:
            return CameraManager.supportsMonocularDepth() ? .monocular : .off
        case .off:
            return .off
        }
    }

    private func presetFromSetting(_ value: String) -> AVCaptureSession.Preset {
        switch value {
        case "inputPriority":
            return .inputPriority
        case "hd1280x720":
            return .hd1280x720
        case "vga640x480":
            return .vga640x480
        case "medium":
            return .medium
        default:
            return .inputPriority
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
    @Binding var fps: Double
    @Binding var preset: String
    @Binding var jpegQuality: Double
    @Binding var frameStride: Int
    @Binding var depthStride: Int
    @Binding var depthMode: String
    @Binding var hapticsEnabled: Bool
    @Binding var alertsEnabled: Bool
    @Binding var localAvoidanceEnabled: Bool
    @Binding var criticalDistance: Double
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

                Section(header: Text("Performance")) {
                    HStack {
                        Text("FPS")
                        Spacer()
                        Text("\(Int(fps))")
                    }
                    Slider(value: $fps, in: 5...30, step: 1)

                    Picker("Camera Preset", selection: $preset) {
                        Text("Input Priority").tag("inputPriority")
                        Text("HD 720p").tag("hd1280x720")
                        Text("VGA 480p").tag("vga640x480")
                        Text("Medium").tag("medium")
                    }

                    HStack {
                        Text("JPEG Quality")
                        Spacer()
                        Text(String(format: "%.2f", jpegQuality))
                    }
                    Slider(value: $jpegQuality, in: 0.1...0.7, step: 0.05)
                    
                    Stepper("Frame Send Stride: \(frameStride)x", value: $frameStride, in: 1...4)
                    Stepper("Depth Update Stride: \(depthStride)x", value: $depthStride, in: 1...8)

                    Picker("Depth Mode", selection: $depthMode) {
                        ForEach(DepthModeOption.options(), id: \.value) { option in
                            Text(option.displayLabel).tag(option.value)
                        }
                    }
                }

                Section(header: Text("Feedback")) {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                    Toggle("On-Screen Alerts", isOn: $alertsEnabled)
                }

                Section(header: Text("Local Safety")) {
                    Toggle("Local Obstacle Avoidance", isOn: $localAvoidanceEnabled)
                    if localAvoidanceEnabled {
                        HStack {
                            Text("Critical Distance")
                            Spacer()
                            Text(String(format: "%.1fm", criticalDistance))
                        }
                        Slider(value: $criticalDistance, in: 0.8...3.0, step: 0.1)
                    }
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

struct AnalysisOverlayView: View {
    let summary: String
    let warnings: [String]
    let location: String
    let action: String
    let path: String
    let obstacles: [String]

    var body: some View {
        if summary.isEmpty && warnings.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ActionPillView(action: action)
                if !path.isEmpty {
                    Text("Path: \(path)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                if !location.isEmpty && location != "Unknown location" {
                    Text(location)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
                ForEach(warnings.prefix(3), id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                if !obstacles.isEmpty {
                    Text("Caution: \(obstacles.prefix(3).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
    }
}

struct ActionPillView: View {
    let action: String

    var body: some View {
        HStack {
            Text(action)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(colorForAction(action))
                .foregroundColor(.white)
                .cornerRadius(8)
            Spacer()
        }
    }

    private func colorForAction(_ action: String) -> Color {
        switch action {
        case "STOP": return .red
        case "CAUTION": return .orange
        default: return .green
        }
    }
}

struct DepthMeshView: View {
    let depthMap: DepthMap

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard depthMap.width > 0, depthMap.height > 0 else { return }
                let rowStep = max(2, depthMap.height / 36)
                let colStep = max(2, depthMap.width / 36)
                let amplitude: CGFloat = 22
                let scaleX = size.width / CGFloat(depthMap.width)
                let scaleY = size.height / CGFloat(depthMap.height)

                for row in stride(from: 0, to: depthMap.height, by: rowStep) {
                    var path = Path()
                    for col in 0..<depthMap.width {
                        let idx = row * depthMap.width + col
                        let depth = depthMap.normalizedValue(at: idx)
                        let x = CGFloat(col) * scaleX
                        let y = CGFloat(row) * scaleY - (CGFloat(depth) * amplitude)
                        if col == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    let opacity = 0.18 + Double(row % (rowStep * 4)) / Double(rowStep * 4) * 0.1
                    context.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: 1.6)
                }

                for col in stride(from: 0, to: depthMap.width, by: colStep) {
                    var path = Path()
                    for row in 0..<depthMap.height {
                        let idx = row * depthMap.width + col
                        let depth = depthMap.normalizedValue(at: idx)
                        let x = CGFloat(col) * scaleX
                        let y = CGFloat(row) * scaleY - (CGFloat(depth) * amplitude)
                        if row == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    let opacity = 0.1 + Double(col % (colStep * 4)) / Double(colStep * 4) * 0.08
                    context.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: 1.0)
                }
            }
        }
        .blendMode(.screen)
        .opacity(0.85)
    }
}

struct DepthModeOption {
    let value: String
    let label: String
    let enabled: Bool
    var displayLabel: String {
        enabled ? label : "\(label) (Unavailable)"
    }

    static func options() -> [DepthModeOption] {
        let lidarAvailable = CameraManager.supportsLiDARDepth()
        let monoAvailable = CameraManager.supportsMonocularDepth()
        return [
            DepthModeOption(value: DepthMode.off.rawValue, label: "Off", enabled: true),
            DepthModeOption(value: DepthMode.lidar.rawValue, label: "LiDAR", enabled: lidarAvailable),
            DepthModeOption(value: DepthMode.monocular.rawValue, label: "Monocular (DepthAnythingV2 Small)", enabled: monoAvailable)
        ]
    }
}

class AlertFeedbackManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let notification = UINotificationFeedbackGenerator()
    private var lastSpokenAt = Date.distantPast
    private let minSpeakInterval: TimeInterval = 1.0

    func play(alert: AlertMessage, hapticsEnabled: Bool) {
        let now = Date()
        if now.timeIntervalSince(lastSpokenAt) >= minSpeakInterval {
            lastSpokenAt = now
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: alert.text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            synthesizer.speak(utterance)
        }
        let utterance = AVSpeechUtterance(string: alert.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5

        if hapticsEnabled {
            switch alert.level {
            case "CRITICAL":
                notification.notificationOccurred(.error)
            case "HIGH":
                notification.notificationOccurred(.warning)
            default:
                notification.notificationOccurred(.success)
            }
        }
    }

    func playDecision(action: String, hapticsEnabled: Bool) {
        if action == "STOP" {
            let now = Date()
            if now.timeIntervalSince(lastSpokenAt) < minSpeakInterval {
                if hapticsEnabled {
                    notification.notificationOccurred(.error)
                }
                return
            }
            lastSpokenAt = now
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: "Stop")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            synthesizer.speak(utterance)
            if hapticsEnabled {
                notification.notificationOccurred(.error)
            }
        } else if action == "CAUTION" {
            if hapticsEnabled {
                notification.notificationOccurred(.warning)
            }
        }
    }
}

struct AlertBannerView: View {
    let alert: AlertMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(colorForLevel(alert.level))
            Text(alert.text)
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
            Text(alert.level)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "CRITICAL": return .red
        case "HIGH": return .orange
        default: return .yellow
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastSentAt = Date.distantPast
    private let minInterval: TimeInterval = 2.0
    var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let now = Date()
        if now.timeIntervalSince(lastSentAt) < minInterval { return }
        lastSentAt = now
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location error: \(error.localizedDescription)")
    }
}

class LocalAvoidanceManager: ObservableObject {
    private var lastAlertAt = Date.distantPast
    private let minInterval: TimeInterval = 1.5

    func process(depthMap: DepthMap, criticalDistance: Double) -> AlertMessage? {
        let now = Date()
        if now.timeIntervalSince(lastAlertAt) < minInterval {
            return nil
        }
        if depthMap.isAbsolute {
            let minDistance = minDepth(in: depthMap)
            if minDistance > 0 && minDistance <= Float(criticalDistance) {
                lastAlertAt = now
                return AlertMessage(level: "CRITICAL", text: "STOP")
            }
        } else {
            let nearScore = nearScore(in: depthMap)
            if nearScore >= 0.82 {
                lastAlertAt = now
                return AlertMessage(level: "HIGH", text: "Obstacle ahead")
            }
        }
        return nil
    }

    private func minDepth(in depthMap: DepthMap) -> Float {
        let w = depthMap.width
        let h = depthMap.height
        if w == 0 || h == 0 { return 0 }
        let cx = w / 2
        let cy = h / 2
        let radius = max(2, min(w, h) / 12)
        var minVal: Float = .greatestFiniteMagnitude
        for y in max(0, cy - radius)...min(h - 1, cy + radius) {
            for x in max(0, cx - radius)...min(w - 1, cx + radius) {
                let value = depthMap.values[y * w + x]
                if value > 0 {
                    minVal = min(minVal, value)
                }
            }
        }
        return minVal == .greatestFiniteMagnitude ? 0 : minVal
    }

    private func nearScore(in depthMap: DepthMap) -> Float {
        let w = depthMap.width
        let h = depthMap.height
        if w == 0 || h == 0 { return 0 }
        let cx = w / 2
        let cy = h / 2
        let radius = max(2, min(w, h) / 10)
        var values: [Float] = []
        values.reserveCapacity((radius * 2 + 1) * (radius * 2 + 1))
        for y in max(0, cy - radius)...min(h - 1, cy + radius) {
            for x in max(0, cx - radius)...min(w - 1, cx + radius) {
                let idx = y * w + x
                values.append(depthMap.normalizedValue(at: idx))
            }
        }
        if values.isEmpty { return 0 }
        values.sort()
        return values[values.count / 2]
    }
}

#Preview {
    ContentView()
}
