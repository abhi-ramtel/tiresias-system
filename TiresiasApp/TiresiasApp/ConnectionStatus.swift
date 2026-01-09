//
//  ConnectionStatus.swift
//  TiresiasApp
//
//  Connection status enum and status view
//

import SwiftUI

enum ConnectionStatus: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
    case reconnecting = "Reconnecting..."
    case error = "Error"
    
    var color: Color {
        switch self {
        case .disconnected:
            return .gray
        case .connecting, .reconnecting:
            return .orange
        case .connected:
            return .green
        case .error:
            return .red
        }
    }
    
    var icon: String {
        switch self {
        case .disconnected:
            return "wifi.slash"
        case .connecting, .reconnecting:
            return "wifi.exclamationmark"
        case .connected:
            return "wifi"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

struct ConnectionStatusView: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
            Text(status.rawValue)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }
}

#Preview {
    VStack(spacing: 10) {
        ConnectionStatusView(status: .disconnected)
        ConnectionStatusView(status: .connecting)
        ConnectionStatusView(status: .connected)
        ConnectionStatusView(status: .reconnecting)
        ConnectionStatusView(status: .error)
    }
    .padding()
    .background(Color.gray)
}
