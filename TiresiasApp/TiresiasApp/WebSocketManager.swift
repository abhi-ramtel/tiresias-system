//
//  WebSocketManager.swift
//  TiresiasApp
//
//  Manages WebSocket connection to the Python edge server
//

import Foundation
import Network

class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var framesSent: Int = 0
    @Published var latencyMs: Int = 0
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var connectionMethod: String = "WiFi"
    @Published var analysisSummary: String = ""
    @Published var analysisWarnings: [String] = []
    @Published var analysisLocation: String = ""
    @Published var analysisAction: String = ""
    @Published var analysisPath: String = ""
    @Published var analysisObstacles: [String] = []
    @Published var decisionAction: String = "CLEAR"
    @Published var lastAlert: AlertMessage? = nil
    
    // Default to your Mac's current IP address
    var serverIP: String = "10.84.104.88"
    
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
            self.analysisSummary = ""
            self.analysisWarnings = []
            self.analysisLocation = ""
            self.analysisAction = ""
            self.analysisPath = ""
            self.analysisObstacles = []
            self.decisionAction = "CLEAR"
            self.lastAlert = nil
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

        // Fallback: mark connected on successful ping if delegate doesn't fire
        probeConnection()
    }
    
    // MARK: - Frame Sending
    
    func sendFrame(_ imageData: Data, depth: DepthPacket?) {
        guard isConnected, let task = webSocketTask else { return }
        
        let messageData: Data
        if let depth = depth {
            var payload = Data()
            payload.append(contentsOf: [0x54, 0x53, 0x46, 0x31]) // "TSF1"
            payload.appendUInt32(UInt32(imageData.count))
            payload.appendUInt32(UInt32(depth.data.count))
            payload.appendUInt16(UInt16(depth.width))
            payload.appendUInt16(UInt16(depth.height))
            payload.append(imageData)
            payload.append(depth.data)
            messageData = payload
        } else {
            messageData = imageData
        }

        let message = URLSessionWebSocketTask.Message.data(messageData)
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

    func sendJSON(_ payload: [String: Any]) {
        guard isConnected, let task = webSocketTask else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(text)) { error in
            if let error = error {
                print("❌ Send error: \(error.localizedDescription)")
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
            handleJSONMessage(text)
            
        case .data(let data):
            print("📦 Received data: \(data.count) bytes")
            
        @unknown default:
            break
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

    private func probeConnection() {
        webSocketTask?.sendPing { [weak self] error in
            guard let self = self else { return }
            if error == nil && !self.isConnected {
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.updateStatus(.connected)
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

    private func handleJSONMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            print("📨 Received: \(text)")
            return
        }

        if type == "analysis" {
            let summary = object["summary"] as? String ?? ""
            let warnings = object["warnings"] as? [String] ?? []
            let location = object["location"] as? String ?? ""
            let action = object["action"] as? String ?? "CLEAR"
            let path = object["path"] as? String ?? ""
            let obstacles = object["nearby_obstacles"] as? [String] ?? []
            DispatchQueue.main.async { [weak self] in
                self?.analysisSummary = summary
                self?.analysisWarnings = warnings
                self?.analysisLocation = location
                self?.analysisAction = action
                self?.analysisPath = path
                self?.analysisObstacles = obstacles
            }
        } else if type == "decision" {
            let action = object["action"] as? String ?? "CLEAR"
            DispatchQueue.main.async { [weak self] in
                self?.decisionAction = action
            }
        } else if type == "alert" {
            let level = object["level"] as? String ?? "MEDIUM"
            let text = object["text"] as? String ?? "Hazard detected"
            let message = AlertMessage(level: level, text: text)
            DispatchQueue.main.async { [weak self] in
                self?.lastAlert = message
            }
        } else {
            print("📨 Received: \(text)")
        }
    }
}

struct AlertMessage: Equatable {
    let id = UUID()
    let level: String
    let text: String
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
