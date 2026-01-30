//
//  PathGuidanceOverlayView.swift
//  TiresiasApp
//
//  Displays real-time path guidance overlay on camera view
//

import SwiftUI
import AVFoundation

struct PathGuidanceOverlayView: View {
    @ObservedObject var webSocketManager: WebSocketManager
    @ObservedObject var cameraManager: CameraManager
    
    @State private var showCameraSelector = false
    
    var body: some View {
        ZStack {
            // Top bar with guidance instruction
            VStack {
                GuidanceInstructionBar(
                    instruction: webSocketManager.guidanceInstruction,
                    direction: webSocketManager.guidanceDirection
                )
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
            }
            
            // Direction arrow overlay
            DirectionArrowOverlay(direction: webSocketManager.guidanceDirection)
            
            // Bottom controls
            VStack {
                Spacer()
                
                HStack(spacing: 20) {
                    // Path clear indicator
                    PathClearIndicator(percentage: webSocketManager.pathClearPercent)
                    
                    Spacer()
                    
                    // Camera zoom selector
                    CameraZoomSelector(
                        currentZoom: cameraManager.currentZoom,
                        isUltraWideAvailable: cameraManager.isUltraWideAvailable,
                        onZoomChange: { zoom in
                            cameraManager.switchCamera(to: zoom)
                        }
                    )
                    
                    Spacer()
                    
                    // Obstacle count badge
                    ObstacleCountBadge(count: webSocketManager.obstacleCount)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
    }
}

// MARK: - Guidance Instruction Bar

struct GuidanceInstructionBar: View {
    let instruction: String
    let direction: String
    
    var backgroundColor: Color {
        switch direction {
        case "path_clear": return .green.opacity(0.9)
        case "move_left", "move_right": return .orange.opacity(0.9)
        case "slight_left", "slight_right": return .yellow.opacity(0.9)
        case "stop": return .red.opacity(0.9)
        case "slow_down": return .orange.opacity(0.9)
        default: return .gray.opacity(0.9)
        }
    }
    
    var textColor: Color {
        switch direction {
        case "path_clear": return .white
        case "slight_left", "slight_right": return .black
        default: return .white
        }
    }
    
    var icon: String {
        switch direction {
        case "path_clear": return "checkmark.circle.fill"
        case "move_left": return "arrow.left.circle.fill"
        case "move_right": return "arrow.right.circle.fill"
        case "slight_left": return "arrow.up.left.circle.fill"
        case "slight_right": return "arrow.up.right.circle.fill"
        case "stop": return "hand.raised.circle.fill"
        case "slow_down": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(textColor)
            
            Text(instruction.isEmpty ? "Analyzing path..." : instruction)
                .font(.headline)
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(backgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Direction Arrow Overlay

struct DirectionArrowOverlay: View {
    let direction: String
    
    @State private var animating = false
    
    var arrowRotation: Double {
        switch direction {
        case "move_left": return -90
        case "move_right": return 90
        case "slight_left": return -45
        case "slight_right": return 45
        case "path_clear": return 0
        default: return 0
        }
    }
    
    var arrowColor: Color {
        switch direction {
        case "path_clear": return .green
        case "move_left", "move_right": return .orange
        case "slight_left", "slight_right": return .yellow
        case "stop": return .red
        case "slow_down": return .orange
        default: return .white
        }
    }
    
    var body: some View {
        if direction == "stop" {
            // Show stop sign for stop direction
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.5), radius: 10)
            .scaleEffect(animating ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animating)
            .onAppear { animating = true }
        } else if direction != "path_clear" {
            // Show directional arrow
            VStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(arrowColor)
                    .rotationEffect(.degrees(arrowRotation))
                    .shadow(color: .black.opacity(0.5), radius: 5)
                    .offset(y: animating ? -10 : 0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animating)
                    .onAppear { animating = true }
            }
        } else {
            // Path clear - subtle forward indicator
            Image(systemName: "chevron.up.circle")
                .font(.system(size: 50))
                .foregroundColor(.green.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 3)
        }
    }
}

// MARK: - Path Clear Indicator

struct PathClearIndicator: View {
    let percentage: Double
    
    var color: Color {
        switch percentage {
        case 80...100: return .green
        case 50..<80: return .yellow
        case 20..<50: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: percentage / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(percentage))%")
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            
            Text("Clear")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Camera Zoom Selector

struct CameraZoomSelector: View {
    let currentZoom: CameraZoomLevel
    let isUltraWideAvailable: Bool
    let onZoomChange: (CameraZoomLevel) -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(CameraZoomLevel.allCases, id: \.self) { zoom in
                let isSelected = currentZoom == zoom
                let isDisabled = zoom == .ultraWide && !isUltraWideAvailable
                
                Button(action: {
                    if !isDisabled {
                        onZoomChange(zoom)
                    }
                }) {
                    Text(zoom.displayName)
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isDisabled ? .gray : (isSelected ? .black : .white))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? Color.yellow : Color.white.opacity(0.2)
                        )
                }
                .disabled(isDisabled)
            }
        }
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Obstacle Count Badge

struct ObstacleCountBadge: View {
    let count: Int
    
    var color: Color {
        switch count {
        case 0: return .green
        case 1...2: return .yellow
        case 3...4: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.8))
                    .frame(width: 50, height: 50)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                }
            }
            
            Text("Objects")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(8)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct PathGuidanceOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            PathGuidanceOverlayView(
                webSocketManager: WebSocketManager(),
                cameraManager: CameraManager()
            )
        }
    }
}
