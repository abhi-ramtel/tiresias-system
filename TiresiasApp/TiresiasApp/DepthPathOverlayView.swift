//
//  DepthPathOverlayView.swift
//  TiresiasApp
//
//  AR-based depth sensing path overlay using LiDAR/TrueDepth
//  Displays a green safe walking path on the camera feed
//  Optimized for accessibility and visually impaired users
//

import SwiftUI
import ARKit
import RealityKit

struct DepthPathOverlayView: View {
    @StateObject private var arManager = ARDepthManager()
    @Binding var isEnabled: Bool
    
    var body: some View {
        ZStack {
            // AR View with depth processing
            ARDepthViewContainer(arManager: arManager)
                .ignoresSafeArea()
            
            // Path overlay drawn on top
            PathOverlayCanvas(pathPoints: arManager.safePath, obstacles: arManager.obstacles)
                .ignoresSafeArea()
            
            // Accessibility status overlay
            VStack {
                Spacer()
                
                if arManager.isProcessing {
                    HStack(spacing: 8) {
                        // Obstacle warnings
                        if !arManager.obstacles.isEmpty {
                            ObstacleWarningView(obstacles: arManager.obstacles)
                        }
                        
                        // Path clarity indicator
                        PathClarityIndicator(clarity: arManager.pathClarity)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(12)
                    .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            if isEnabled {
                arManager.startSession()
            }
        }
        .onDisappear {
            arManager.pauseSession()
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue {
                arManager.startSession()
            } else {
                arManager.pauseSession()
            }
        }
    }
}

// MARK: - AR Depth Manager

class ARDepthManager: NSObject, ObservableObject {
    @Published var safePath: [CGPoint] = []
    @Published var obstacles: [ObstacleInfo] = []
    @Published var pathClarity: Double = 1.0
    @Published var isProcessing = false
    
    private var arView: ARView?
    private var session: ARSession?
    
    // Depth processing settings
    private let maxDepthDistance: Float = 5.0 // meters
    private let obstacleThreshold: Float = 0.5 // meters - closer = obstacle
    private let pathWidth: Float = 1.0 // meters wide path
    
    // Voice feedback
    private var lastObstacleAnnouncement = Date.distantPast
    private let announcementCooldown: TimeInterval = 3.0
    
    // Frame throttling for performance - process only every Nth frame
    private var frameCount: Int = 0
    private let processEveryNthFrame: Int = 8 // Process 1 in 8 frames (~7fps instead of 60)
    private var lastProcessTime = Date.distantPast
    private let minProcessInterval: TimeInterval = 0.15 // Max ~6 updates/sec
    
    func createARView() -> ARView {
        let arView = ARView(frame: .zero)
        arView.automaticallyConfigureSession = false
        self.arView = arView
        self.session = arView.session
        return arView
    }
    
    func startSession() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ||
              ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) else {
            print("⚠️ Device does not support depth sensing")
            // Fall back to basic AR without depth
            startBasicSession()
            return
        }
        
        let configuration = ARWorldTrackingConfiguration()
        
        // Use smoothed depth if available (better for accessibility)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        
        session?.delegate = self
        session?.run(configuration)
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        print("✅ AR Depth session started")
    }
    
    private func startBasicSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        
        session?.delegate = self
        session?.run(configuration)
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        print("✅ Basic AR session started (no depth)")
    }
    
    func pauseSession() {
        session?.pause()
        DispatchQueue.main.async {
            self.isProcessing = false
            self.safePath = []
            self.obstacles = []
        }
    }
    
    // MARK: - Depth Processing
    
    private func processDepthData(_ frame: ARFrame) {
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            // No depth data - generate path from plane detection
            generatePathFromPlanes(frame)
            return
        }
        
        let depthMap = depthData.depthMap
        let confidenceMap = depthData.confidenceMap
        
        // Process depth map to find safe path
        let pathResult = analyzeDepthForPath(
            depthMap: depthMap,
            confidenceMap: confidenceMap,
            frame: frame
        )
        
        DispatchQueue.main.async {
            self.safePath = pathResult.pathPoints
            self.obstacles = pathResult.obstacles
            self.pathClarity = pathResult.clarity
        }
        
        // Voice feedback for obstacles
        announceObstaclesIfNeeded(pathResult.obstacles)
    }
    
    private func analyzeDepthForPath(
        depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer?,
        frame: ARFrame
    ) -> PathAnalysisResult {
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return PathAnalysisResult(pathPoints: [], obstacles: [], clarity: 0)
        }
        
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        var pathPoints: [CGPoint] = []
        var obstacles: [ObstacleInfo] = []
        var totalClarity: Double = 0
        var validSamples = 0
        
        // Sample depth in vertical strips to find clear path
        let stripCount = 9
        let centerStrip = stripCount / 2
        
        for strip in 0..<stripCount {
            let x = (width * strip) / (stripCount - 1)
            var minDepth: Float = Float.infinity
            var obstacleY: Int = -1
            
            // Sample from bottom to top (closer to camera first)
            for y in stride(from: height - 1, through: height / 3, by: -height / 20) {
                let index = y * width + x
                let depth = floatBuffer[index]
                
                // Valid depth reading
                if depth > 0 && depth < maxDepthDistance {
                    validSamples += 1
                    
                    if depth < obstacleThreshold && depth < minDepth {
                        minDepth = depth
                        obstacleY = y
                    }
                }
            }
            
            // Convert to screen coordinates
            let screenX = CGFloat(x) / CGFloat(width)
            
            if obstacleY >= 0 {
                // Obstacle detected in this strip
                let screenY = CGFloat(obstacleY) / CGFloat(height)
                let position: ObstaclePosition = strip < centerStrip ? .left : (strip > centerStrip ? .right : .center)
                
                obstacles.append(ObstacleInfo(
                    screenPosition: CGPoint(x: screenX, y: screenY),
                    distance: minDepth,
                    position: position
                ))
            } else {
                // Clear path in this strip
                // Add point at bottom of screen for this strip
                pathPoints.append(CGPoint(x: screenX, y: 0.9))
                totalClarity += 1.0
            }
        }
        
        // Calculate path clarity (0-1)
        let clarity = validSamples > 0 ? totalClarity / Double(stripCount) : 0.5
        
        // Generate smooth path curve
        let smoothedPath = generateSmoothPath(from: pathPoints, screenHeight: CGFloat(height))
        
        return PathAnalysisResult(
            pathPoints: smoothedPath,
            obstacles: obstacles,
            clarity: clarity
        )
    }
    
    private func generateSmoothPath(from points: [CGPoint], screenHeight: CGFloat) -> [CGPoint] {
        guard points.count >= 1 else {
            // Default center path if not enough data
            return [
                CGPoint(x: 0.5, y: 1.0),
                CGPoint(x: 0.5, y: 0.5),
                CGPoint(x: 0.5, y: 0.3)
            ]
        }
        
        // Find the average clear X position from obstacle-free strips
        let avgX = points.reduce(0.0) { $0 + $1.x } / CGFloat(points.count)
        
        // Generate path centerline points from bottom to middle of screen
        var smoothPath: [CGPoint] = []
        let steps = 15
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let y = 1.0 - (t * 0.65) // From bottom (1.0) to 35% up (0.35)
            
            // Curve toward the clearest area
            let x = 0.5 + (avgX - 0.5) * t * 0.4
            
            smoothPath.append(CGPoint(x: x, y: y))
        }
        
        return smoothPath
    }
    
    private func generatePathFromPlanes(_ frame: ARFrame) {
        // Fallback: use detected horizontal planes to estimate safe walking surface
        var clearX: CGFloat = 0.5
        var planeCount = 0
        
        // Check for detected floor planes
        for anchor in frame.anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor,
               planeAnchor.classification == .floor || planeAnchor.alignment == .horizontal {
                // Use plane center to guide path direction
                let planeCenter = planeAnchor.center
                // Convert to approximate screen X (simplified)
                clearX += CGFloat(planeCenter.x) * 0.1
                planeCount += 1
            }
        }
        
        if planeCount > 0 {
            clearX = min(max(clearX / CGFloat(planeCount), 0.2), 0.8)
        }
        
        // Generate path points based on detected planes
        let pathPoints = [
            CGPoint(x: clearX, y: 1.0),
            CGPoint(x: clearX, y: 0.7),
            CGPoint(x: clearX, y: 0.4)
        ]
        
        DispatchQueue.main.async {
            self.safePath = pathPoints
            self.obstacles = []
            self.pathClarity = planeCount > 0 ? 0.7 : 0.5
        }
    }
    
    // MARK: - Voice Feedback
    
    private func announceObstaclesIfNeeded(_ obstacles: [ObstacleInfo]) {
        guard !obstacles.isEmpty else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastObstacleAnnouncement) > announcementCooldown else { return }
        
        // Find closest obstacle
        let closest = obstacles.min { $0.distance < $1.distance }
        
        guard let obstacle = closest, obstacle.distance < 2.0 else { return }
        
        let message: String
        switch obstacle.position {
        case .left:
            message = "Obstacle on left"
        case .right:
            message = "Obstacle on right"
        case .center:
            message = "Obstacle ahead"
        }
        
        UIAccessibility.post(notification: .announcement, argument: message)
        lastObstacleAnnouncement = now
    }
}

// MARK: - ARSessionDelegate

extension ARDepthManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Frame throttling for performance - skip frames to reduce CPU load
        frameCount += 1
        guard frameCount % processEveryNthFrame == 0 else { return }
        
        // Also enforce minimum time interval
        let now = Date()
        guard now.timeIntervalSince(lastProcessTime) >= minProcessInterval else { return }
        lastProcessTime = now
        
        // Process depth on background thread to avoid UI lag
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.processDepthData(frame)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("❌ AR Session error: \(error)")
    }
}

// MARK: - Supporting Types

struct PathAnalysisResult {
    let pathPoints: [CGPoint]
    let obstacles: [ObstacleInfo]
    let clarity: Double
}

struct ObstacleInfo: Identifiable {
    let id = UUID()
    let screenPosition: CGPoint
    let distance: Float
    let position: ObstaclePosition
}

enum ObstaclePosition {
    case left, center, right
}

// MARK: - AR View Container

struct ARDepthViewContainer: UIViewRepresentable {
    @ObservedObject var arManager: ARDepthManager
    
    func makeUIView(context: Context) -> ARView {
        return arManager.createARView()
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Path Overlay Canvas - Surface-based green walkable area

struct PathOverlayCanvas: View {
    let pathPoints: [CGPoint]
    let obstacles: [ObstacleInfo]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Safe walkable surface area (filled green region)
                if pathPoints.count >= 2 {
                    WalkableSurfacePath(pathPoints: pathPoints)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(0.5),
                                    Color.green.opacity(0.35),
                                    Color.green.opacity(0.15),
                                    Color.green.opacity(0.05)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    
                    // Glowing edge effect
                    WalkableSurfacePath(pathPoints: pathPoints)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.green.opacity(0.8),
                                    Color.green.opacity(0.4),
                                    Color.green.opacity(0.1)
                                ],
                                startPoint: .bottom,
                                endPoint: .top
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 4)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                // Obstacle markers
                ForEach(obstacles) { obstacle in
                    ObstacleMarker(obstacle: obstacle)
                        .position(
                            x: obstacle.screenPosition.x * geometry.size.width,
                            y: obstacle.screenPosition.y * geometry.size.height
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Walkable Surface Path Shape

struct WalkableSurfacePath: Shape {
    let pathPoints: [CGPoint]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        guard pathPoints.count >= 2 else {
            // Default center corridor if not enough points
            return defaultPath(in: rect)
        }
        
        // Calculate the center line average X position
        let avgX = pathPoints.reduce(0.0) { $0 + $1.x } / CGFloat(pathPoints.count)
        
        // Path width expands as it gets closer (perspective)
        // At bottom (y=1.0): wider, at top (y=0.3): narrower
        
        let steps = 20
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let y = 1.0 - (t * 0.65) // From bottom to ~35% up
            
            // Perspective width: wider at bottom, narrower at top
            let perspectiveWidth = 0.35 * (1.0 - t * 0.7) // 35% at bottom, ~10% at top
            
            // Slight curve toward clearest area
            let centerX = 0.5 + (avgX - 0.5) * t * 0.3
            
            let leftX = max(0.05, centerX - perspectiveWidth)
            let rightX = min(0.95, centerX + perspectiveWidth)
            
            leftEdge.append(CGPoint(x: leftX * rect.width, y: y * rect.height))
            rightEdge.append(CGPoint(x: rightX * rect.width, y: y * rect.height))
        }
        
        // Build the filled path: left edge up, then right edge down
        if let first = leftEdge.first {
            path.move(to: first)
        }
        
        // Smooth left edge going up
        for point in leftEdge.dropFirst() {
            path.addLine(to: point)
        }
        
        // Connect top
        if let topLeft = leftEdge.last, let topRight = rightEdge.last {
            path.addQuadCurve(to: topRight, control: CGPoint(x: (topLeft.x + topRight.x) / 2, y: topLeft.y - 10))
        }
        
        // Smooth right edge going down
        for point in rightEdge.reversed().dropFirst() {
            path.addLine(to: point)
        }
        
        // Close path at bottom
        path.closeSubpath()
        
        return path
    }
    
    private func defaultPath(in rect: CGRect) -> Path {
        var path = Path()
        
        // Default center corridor
        let bottomWidth: CGFloat = 0.35
        let topWidth: CGFloat = 0.12
        let topY: CGFloat = 0.35
        
        // Bottom left
        path.move(to: CGPoint(x: (0.5 - bottomWidth) * rect.width, y: rect.height))
        
        // Top left
        path.addLine(to: CGPoint(x: (0.5 - topWidth) * rect.width, y: topY * rect.height))
        
        // Top curve
        path.addQuadCurve(
            to: CGPoint(x: (0.5 + topWidth) * rect.width, y: topY * rect.height),
            control: CGPoint(x: 0.5 * rect.width, y: (topY - 0.03) * rect.height)
        )
        
        // Top right to bottom right
        path.addLine(to: CGPoint(x: (0.5 + bottomWidth) * rect.width, y: rect.height))
        
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Obstacle Marker

struct ObstacleMarker: View {
    let obstacle: ObstacleInfo
    
    var body: some View {
        ZStack {
            // Pulsing warning circle
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 50, height: 50)
            
            Circle()
                .fill(Color.red.opacity(0.6))
                .frame(width: 35, height: 35)
            
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
        }
    }
}

// MARK: - Obstacle Warning View

struct ObstacleWarningView: View {
    let obstacles: [ObstacleInfo]
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            
            let closest = obstacles.min { $0.distance < $1.distance }
            if let obstacle = closest {
                Text("\(obstacle.position == .left ? "Left" : obstacle.position == .right ? "Right" : "Ahead")")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Obstacle warning")
    }
}

// MARK: - Path Clarity Indicator

struct PathClarityIndicator: View {
    let clarity: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: clarity > 0.7 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(clarity > 0.7 ? .green : .yellow)
            
            Text(clarity > 0.7 ? "Clear" : "Caution")
                .font(.caption)
                .foregroundColor(.white)
        }
        .accessibilityLabel(clarity > 0.7 ? "Path is clear" : "Proceed with caution")
    }
}

#Preview {
    DepthPathOverlayView(isEnabled: .constant(true))
}
