//
//  SocketManager.swift
//  
//
//  Created by Abhi Ramtel on 1/7/26.
//

// ios/SocketManager.swift
import Foundation

@objc(SocketManager)
class SocketManager: NSObject {
    static let shared = SocketManager()
    private var webSocketTask: URLSessionWebSocketTask?
    var isConnected = false

    func connect() {
        // Connect to localhost (mapped via USB)
        guard let url = URL(string: "ws://localhost:8000/ws/video") else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        print("⚡️ Swift Socket Connecting...")
        
        receiveMessage() // Keep the connection alive
    }

    func sendFrame(_ imageData: Data) {
        guard isConnected, let socket = webSocketTask else { return }
        
        // Send as pure binary message
        let message = URLSessionWebSocketTask.Message.data(imageData)
        socket.send(message) { error in
            if let error = error {
                print("Socket Error: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { result in
            // Recursively listen for responses (Keep-Alive)
            self.receiveMessage()
        }
    }
}
