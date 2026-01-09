//
//  WebSocketManager.swift
//  TiresiasApp
//
//  Manages WebSocket connection to the Python edge server
//

import Foundation

class WebSocketManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var framesSent: Int = 0
    @Published var latencyMs: Int = 0
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var connectionMethod: String = "WiFi"
    
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
    
    // Session that bypasses proxy (for local network)
    private lazy var directSession: URLSession = {
        let config = URLSessionConfiguration.default
        // Disable proxy using string keys for iOS compatibility
        config.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0
        ] as [String: Any]
        config.timeoutIntervalForRequest = 5
        return URLSession(configuration: config)
    }()
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        // Disable proxy for WebSocket connection too
        config.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0
        ] as [String: Any]
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }
    
    var webSocketURL: URL {
        URL(string: "ws://\(serverIP):\(serverPort)/ws/video")!
    }
    
    var healthCheckURL: URL {
        URL(string: "http://\(serverIP):\(serverPort)/health")!
    }
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        updateStatus(.connecting)
        usingUSBFallback = false
        
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
        
        // Try common USB tethering IPs
        let usbIPs = ["172.20.10.1", "192.168.2.1", serverIP]
        
        print("🔍 Attempting USB connection...")
        tryNextUSBIP(ips: usbIPs, index: 0)
    }
    
    private func tryNextUSBIP(ips: [String], index: Int) {
        guard index < ips.count else {
            // All IPs failed
            print("❌ All connection attempts failed")
            usingUSBFallback = false
            handleConnectionError(
                "Cannot reach server.\n\n" +
                "WiFi: Check same network & firewall\n" +
                "USB: Connect iPhone via cable\n\n" +
                "Make sure server is running:\n" +
                "./start_server.sh"
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
                // Try next IP
                self.tryNextUSBIP(ips: ips, index: index + 1)
            }
        }.resume()
    }
    
    func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        reconnectAttempts = 0
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.updateStatus(.disconnected)
            self.framesSent = 0
        }
        print("🔴 Disconnected from server")
    }
    
    private func testServerConnection(completion: @escaping (Bool) -> Void) {
        print("🔍 Testing server connection to: \(healthCheckURL)")
        
        var request = URLRequest(url: healthCheckURL)
        request.timeoutInterval = 5
        
        // Use direct session to bypass iCloud Private Relay
        directSession.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Health check failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    print("✅ Server is reachable")
                    completion(true)
                } else {
                    print("⚠️ Server responded with unexpected status")
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
            print("📨 Received: \(text)")
            // Handle text responses from server (e.g., AI analysis results)
            
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
    
    // MARK: - Status Management
    
    private func updateStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async {
            self.connectionStatus = status
        }
    }
    
    private func handleConnectionError(_ message: String) {
        DispatchQueue.main.async {
            let method = self.usingUSBFallback ? "USB" : "WiFi"
        print("🟢 WebSocket connected via \(method)")
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
        
        attemptReconnect()
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
        print("🟢 WebSocket connected")
        reconnectAttempts = 0
        let method = usingUSBFallback ? "USB" : "WiFi"
        print("🟢 WebSocket connected via \(method)")
        reconnectAttempts = 0
        
        DispatchQueue.main.async {
            self.isConnected = true
            self.connectionMethod = method
        }
        
        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
            print("🔴 WebSocket closed with code: \(closeCode)")
            handleDisconnection()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                print("❌ Session error: \(error.localizedDescription)")
                handleConnectionError(error.localizedDescription)
            }
        }
    }
}
