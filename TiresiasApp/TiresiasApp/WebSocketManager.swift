//
//  WebSocketManager.swift
//  TiresiasApp
//
//  Manages WebSocket connection to the Python edge server
//

import Foundation
import Network
import AVFoundation

class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var framesSent: Int = 0
    @Published var latencyMs: Int = 0
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var connectionMethod: String = "WiFi"
    
    // Path Guidance properties
    @Published var guidanceDirection: String = "path_clear"
    @Published var guidanceInstruction: String = ""
    @Published var pathClearPercent: Double = 100.0
    @Published var obstacleCount: Int = 0
    @Published var detectedObstacles: [String] = []
    @Published var guidanceEnabled: Bool = true
    @Published var voiceGuidanceEnabled: Bool = true
    
    // Voice synthesis for guidance
    private let synthesizer = AVSpeechSynthesizer()
    private var lastVoiceAnnouncementTime = Date.distantPast
    private let voiceAnnouncementInterval: TimeInterval = 2.0  // Don't repeat too often
    private var lastAnnouncedDirection: String = ""
    private var premiumVoice: AVSpeechSynthesisVoice?
    
    // Find the best available voice on device
    private func findPremiumVoice() -> AVSpeechSynthesisVoice? {
        // Try Alex first (Siri-quality voice)
        if let alexVoice = AVSpeechSynthesisVoice(identifier: AVSpeechSynthesisVoiceIdentifierAlex) {
            print("🎙️ Using Alex voice (premium)")
            return alexVoice
        }
        
        // Look for enhanced/premium quality voices
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Filter for English voices and prefer premium quality
        let englishVoices = allVoices.filter { $0.language.starts(with: "en") }
        
        // Try to find a premium quality voice (iOS 16+)
        if #available(iOS 16.0, *) {
            // Look for premium voices first
            if let premiumVoice = englishVoices.first(where: { $0.voiceTraits.contains(.isPersonalVoice) }) {
                print("🎙️ Using Personal Voice")
                return premiumVoice
            }
        }
        
        // Look for enhanced quality voices (marked as "enhanced" in identifier)
        if let enhancedVoice = englishVoices.first(where: { 
            $0.identifier.lowercased().contains("enhanced") || 
            $0.identifier.lowercased().contains("premium") ||
            $0.quality == .enhanced
        }) {
            print("🎙️ Using enhanced voice: \(enhancedVoice.name)")
            return enhancedVoice
        }
        
        // Prefer specific high-quality voices by name
        let preferredNames = ["Samantha", "Evan", "Nicky", "Aaron", "Allison"]
        for name in preferredNames {
            if let voice = englishVoices.first(where: { $0.name == name && $0.quality == .enhanced }) {
                print("🎙️ Using \(name) (enhanced)")
                return voice
            }
        }
        
        // Fall back to any enhanced English voice
        if let enhancedVoice = englishVoices.first(where: { $0.quality == .enhanced }) {
            print("🎙️ Using enhanced voice: \(enhancedVoice.name)")
            return enhancedVoice
        }
        
        // Last resort: default en-US voice
        print("🎙️ Using default en-US voice")
        return AVSpeechSynthesisVoice(language: "en-US")
    }
    
    // var serverIP: String = "10.84.104.88" // Use your own IP here (Change it)
    var serverIP: String = ProcessInfo.processInfo.environment["IP_ADDRESS"] ?? "10.84.15.64" // add it to your env file
    
    private let serverPort = 8000
    private var usingUSBFallback = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var pingTimer: Timer?
    private var lastPingTime: Date?
    
    private let reconnectDelay: TimeInterval = 2.0
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    private var userInitiatedDisconnect = false  // Track if user disconnected
    
    // Session that bypasses proxy AND Private Relay (for local network)
    private lazy var directSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Disable ALL proxies including iCloud Private Relay
        config.connectionProxyDictionary = [
            "HTTPEnable": false,
            "HTTPSEnable": false,
            kCFProxyTypeKey as String: kCFProxyTypeNone as Any
        ] as [String: Any]
        config.timeoutIntervalForRequest = 5
        config.waitsForConnectivity = false  // Don't wait, fail fast
        // Disable constrained/expensive network restrictions
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        return URLSession(configuration: config)
    }()
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false  // Don't wait for connectivity
        // Disable ALL proxies including iCloud Private Relay
        config.connectionProxyDictionary = [
            "HTTPEnable": false,
            "HTTPSEnable": false,
            kCFProxyTypeKey as String: kCFProxyTypeNone as Any
        ] as [String: Any]
        config.allowsCellularAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    var webSocketURL: URL {
        URL(string: "ws://\(serverIP):\(serverPort)/ws/video")!
    }
    
    var healthCheckURL: URL {
        URL(string: "http://\(serverIP):\(serverPort)/health")!
    }
    
    // MARK: - Network Checks
    
    private func checkNetworkInterface() {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "NetworkMonitor")
        
        monitor.pathUpdateHandler = { [weak self] path in
            monitor.cancel() // Only need one check
            
            let isWiFi = path.usesInterfaceType(.wifi)
            let isCellular = path.usesInterfaceType(.cellular)
            let isConstrained = path.isConstrained // Private Relay often sets this
            
            DispatchQueue.main.async {
                if isCellular && !isWiFi {
                    print("⚠️ WARNING: iPhone is on CELLULAR, not WiFi!")
                    print("   Local server connection will likely fail.")
                    print("   Please connect to the same WiFi network as your Mac.")
                } else if isWiFi {
                    print("✅ iPhone is connected via WiFi")
                }
                
                if isConstrained {
                    print("⚠️ Network is constrained (possibly Private Relay)")
                    print("   Consider disabling 'Limit IP Address Tracking' for this WiFi network")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        updateStatus(.connecting)
        usingUSBFallback = false
        userInitiatedDisconnect = false  // Reset flag when connecting
        
        // Check network interface first
        checkNetworkInterface()
        
        // First try WiFi connection
        print("🔍 Attempting WiFi connection to \(serverIP)...")
        testServerConnection { [weak self] success in
            guard let self = self else { return }
            
            if success {
                DispatchQueue.main.async {
                    self.connectionMethod = "WiFi"
                }
                print("✅ WiFi connection available")
                self.establishWebSocket()
            } else {
                // WiFi failed, try USB fallback
                print("⚠️ WiFi connection failed, trying USB fallback...")
                self.tryUSBFallback()
            }
        }
    }
    
    private func tryUSBFallback() {
        // For USB, iPhone connects to Mac's IP via the USB network interface
        // The USB connection creates a direct network link at 172.20.10.x or similar
        usingUSBFallback = true
        updateStatus(.connecting)
        
        // Try common USB/local network IPs
        // Note: 172.20.10.x is when iPhone shares to Mac, not typical for this use case
        // localhost (127.0.0.1) won't work from iOS device
        // serverIP is the primary IP we should retry
        let usbIPs = [serverIP, "192.168.1.1", "192.168.0.1", "10.0.0.1"]
        
        print("🔍 Attempting USB/fallback connection...")
        print("   Note: Ensure iPhone is on same WiFi network as Mac")
        tryNextUSBIP(ips: usbIPs, index: 0)
    }
    
    private func tryNextUSBIP(ips: [String], index: Int) {
        guard index < ips.count else {
            // All IPs failed
            print("❌ All connection attempts failed")
            usingUSBFallback = false
            handleConnectionError(
                "Cannot reach server.\n\n" +
                "⚠️ Make sure iPhone is on WiFi (not cellular)\n" +
                "⚠️ Connect to SAME WiFi as your Mac\n" +
                "⚠️ Disable iCloud Private Relay:\n" +
                "   Settings → WiFi → (i) → Limit IP Tracking OFF\n\n" +
                "Server IP: \(serverIP):8000"
            )
            return
        }
        
        let testIP = ips[index]
        let testURL = URL(string: "http://\(testIP):\(serverPort)/health")!
        
        print("🔍 Trying \(testIP)...")
        
        var request = URLRequest(url: testURL)
        request.timeoutInterval = 3
        
        // Use direct session to bypass iCloud Private Relay
        directSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("✅ Connected via \(testIP)")
                DispatchQueue.main.async {
                    self.serverIP = testIP
                    self.connectionMethod = "USB"
                }
                self.establishWebSocket()
            } else {
                if let error = error {
                    print("   ❌ \(testIP) failed: \(error.localizedDescription)")
                } else {
                    print("   ❌ \(testIP) failed: No valid response")
                }
                // Try next IP
                self.tryNextUSBIP(ips: ips, index: index + 1)
            }
        }.resume()
    }
    
    func disconnect() {
        print("🔴 Initiating disconnect...")
        
        // Mark as user-initiated to prevent auto-reconnect
        userInitiatedDisconnect = true
        
        // Stop ping timer first
        pingTimer?.invalidate()
        pingTimer = nil
        
        // Cancel WebSocket with proper closure
        if let task = webSocketTask {
            // Send close frame and wait briefly for it to complete
            task.cancel(with: .normalClosure, reason: "User disconnected".data(using: .utf8))
        }
        webSocketTask = nil
        reconnectAttempts = 0
        
        // Reset state on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isConnected = false
            self.updateStatus(.disconnected)
            self.framesSent = 0
            self.latencyMs = 0
            self.connectionMethod = "WiFi"
        }
        print("🔴 Disconnected from server")
    }
    
    private func testServerConnection(completion: @escaping (Bool) -> Void) {
        print("🔍 Testing server connection to: \(healthCheckURL)")
        
        var request = URLRequest(url: healthCheckURL)
        request.timeoutInterval = 5
        
        // Use direct session to bypass iCloud Private Relay
        directSession.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let nsError = error as NSError
                    print("❌ Health check failed: \(error.localizedDescription)")
                    print("   Error domain: \(nsError.domain), code: \(nsError.code)")
                    if nsError.code == -1004 {
                        print("   💡 Hint: Server may not be running or firewall is blocking")
                    } else if nsError.code == -1003 {
                        print("   💡 Hint: Cannot find host - check IP address")
                    } else if nsError.code == -1200 {
                        print("   💡 Hint: SSL/ATS error - check Info.plist settings")
                    }
                    completion(false)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("   HTTP Status: \(httpResponse.statusCode)")
                    if httpResponse.statusCode == 200 {
                        print("✅ Server is reachable")
                        completion(true)
                    } else {
                        print("⚠️ Server responded with unexpected status: \(httpResponse.statusCode)")
                        completion(false)
                    }
                } else {
                    print("⚠️ No HTTP response received")
                    completion(false)
                }
            }
        }.resume()
    }
    
    private func establishWebSocket() {
        print("🔌 Connecting to WebSocket: \(webSocketURL)")
        
        webSocketTask = urlSession.webSocketTask(with: webSocketURL)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start ping timer for latency measurement
        startPingTimer()
    }
    
    // MARK: - Frame Sending
    
    func sendFrame(_ imageData: Data) {
        guard isConnected, let task = webSocketTask else { return }
        
        let message = URLSessionWebSocketTask.Message.data(imageData)
        task.send(message) { [weak self] error in
            if let error = error {
                print("❌ Send error: \(error.localizedDescription)")
                self?.handleConnectionError(error.localizedDescription)
            } else {
                DispatchQueue.main.async {
                    self?.framesSent += 1
                }
            }
        }
    }
    
    // MARK: - Message Receiving
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // Continue receiving
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ Receive error: \(error.localizedDescription)")
                self?.handleDisconnection()
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Parse JSON guidance messages
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let type = json["type"] as? String {
                    if type == "guidance" {
                        DispatchQueue.main.async {
                            let newDirection = json["direction"] as? String ?? "path_clear"
                            self.guidanceDirection = newDirection
                            self.guidanceInstruction = json["instruction"] as? String ?? ""
                            self.pathClearPercent = json["path_clear_percent"] as? Double ?? 100.0
                            self.obstacleCount = json["obstacle_count"] as? Int ?? 0
                            
                            // Parse obstacles
                            if let obstacles = json["obstacles"] as? [[String: Any]] {
                                self.detectedObstacles = obstacles.compactMap { $0["class"] as? String }
                            }
                            
                            // Voice announcement for direction changes
                            self.announceGuidanceIfNeeded(direction: newDirection)
                        }
                    }
                }
            }
            
        case .data(let data):
            print("📦 Received data: \(data.count) bytes")
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Voice Guidance
    
    private func announceGuidanceIfNeeded(direction: String) {
        guard voiceGuidanceEnabled && guidanceEnabled else { return }
        
        // Only announce important changes
        let now = Date()
        let timeSinceLastAnnouncement = now.timeIntervalSince(lastVoiceAnnouncementTime)
        
        // Announce immediately for critical directions, or throttle for others
        let isCritical = direction == "stop" || direction == "move_left" || direction == "move_right"
        let shouldAnnounce = (direction != lastAnnouncedDirection && isCritical) ||
                             (direction != "path_clear" && timeSinceLastAnnouncement >= voiceAnnouncementInterval)
        
        guard shouldAnnounce else { return }
        
        // Generate voice message
        let voiceMessage: String
        switch direction {
        case "path_clear":
            // Don't announce path clear unless transitioning from blocked
            if lastAnnouncedDirection == "stop" || lastAnnouncedDirection == "move_left" || lastAnnouncedDirection == "move_right" {
                voiceMessage = "Path clear"
            } else {
                return
            }
        case "move_left":
            voiceMessage = "Move left"
        case "move_right":
            voiceMessage = "Move right"
        case "slight_left":
            voiceMessage = "Slight left"
        case "slight_right":
            voiceMessage = "Slight right"
        case "stop":
            voiceMessage = "Stop. Obstacle ahead"
        case "slow_down":
            voiceMessage = "Slow down"
        default:
            return
        }
        
        // Speak the message with premium voice
        let utterance = AVSpeechUtterance(string: voiceMessage)
        
        // Use cached premium voice or find one
        if premiumVoice == nil {
            premiumVoice = findPremiumVoice()
        }
        utterance.voice = premiumVoice
        
        // Tuned parameters for natural speech
        utterance.rate = 0.48  // Slightly slower than default for clarity
        utterance.pitchMultiplier = 1.05  // Slightly higher pitch sounds more natural
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.1
        
        // Stop any current speech and speak new message
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
        
        lastVoiceAnnouncementTime = now
        lastAnnouncedDirection = direction
    }
    
    func setVoiceGuidanceEnabled(_ enabled: Bool) {
        voiceGuidanceEnabled = enabled
        if !enabled {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
    
    // MARK: - Guidance Control
    
    func setGuidanceEnabled(_ enabled: Bool) {
        guidanceEnabled = enabled
        
        // Send command to server
        let command: [String: Any] = [
            "type": "set_guidance",
            "enabled": enabled
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: command),
           let jsonString = String(data: data, encoding: .utf8) {
            let message = URLSessionWebSocketTask.Message.string(jsonString)
            webSocketTask?.send(message) { error in
                if let error = error {
                    print("❌ Failed to send guidance command: \(error)")
                }
            }
        }
    }
    
    // MARK: - Ping/Pong for Latency
    
    private func startPingTimer() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        lastPingTime = Date()
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("⚠️ Ping failed: \(error.localizedDescription)")
            } else if let self = self, let pingTime = self.lastPingTime {
                let latency = Int(Date().timeIntervalSince(pingTime) * 1000)
                DispatchQueue.main.async {
                    self.latencyMs = latency
                }
            }
        }
    }
    
    // MARK: - Status Management
    
    private func updateStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
    
    private func handleConnectionError(_ message: String) {
        DispatchQueue.main.async {
            let method = self.usingUSBFallback ? "USB" : "WiFi"
            print("❌ Connection error via \(method): \(message)")
            self.errorMessage = message
            self.showError = true
            self.updateStatus(.error)
        }
    }
    
    private func handleDisconnection() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateStatus(.disconnected)
        }
        
        // Only auto-reconnect if not user-initiated
        if !userInitiatedDisconnect {
            attemptReconnect()
        } else {
            print("🔴 User-initiated disconnect, not reconnecting")
        }
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ Max reconnection attempts reached")
            updateStatus(.error)
            return
        }
        
        reconnectAttempts += 1
        print("🔄 Reconnection attempt \(reconnectAttempts)/\(maxReconnectAttempts)")
        updateStatus(.reconnecting)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            self?.connect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        let method = usingUSBFallback ? "USB" : "WiFi"
        print("🟢 WebSocket connected via \(method)")
        reconnectAttempts = 0
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionMethod = method
            self.updateStatus(.connected)
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔴 WebSocket closed with code: \(closeCode)")
        handleDisconnection()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            print("❌ Session error: \(error.localizedDescription)")
            print("   Error domain: \(nsError.domain), code: \(nsError.code)")
            
            // Provide helpful hints based on error code
            var hint = ""
            switch nsError.code {
            case -1004: hint = "Server not reachable - check if server is running"
            case -1003: hint = "Cannot find host - check IP address"
            case -1200, -1202: hint = "SSL/TLS error - HTTP connections require ATS settings in Info.plist"
            case -1001: hint = "Connection timeout - server may be slow or blocked"
            case -1005: hint = "Network connection lost"
            case -1009: hint = "No internet connection"
            default: break
            }
            if !hint.isEmpty {
                print("   💡 Hint: \(hint)")
            }
            
            handleConnectionError(error.localizedDescription)
        }
    }
}
