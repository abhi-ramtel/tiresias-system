//
//  NavigationMapView.swift
//  TiresiasApp
//
//  Full-screen navigation map view similar to Apple Maps
//  Shows walking route with time estimate and directions panel
//

import SwiftUI
import MapKit

struct NavigationMapView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @ObservedObject var navigationManager: RealTimeNavigationManager
    @Binding var isPresented: Bool
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyleOption = .standard
    
    var body: some View {
        ZStack {
            // Full-screen map with route
            Map(position: $cameraPosition) {
                // Walking route polyline
                if let route = navigationManager.currentRoute {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }
                
                // Destination marker
                if let destination = navigationManager.destinationCoordinate {
                    Annotation("", coordinate: destination) {
                        DestinationMarker()
                    }
                }
                
                // User location
                if let location = locationManager.currentLocation {
                    Annotation("", coordinate: location.coordinate) {
                        NavigationUserMarker()
                    }
                }
            }
            .mapStyle(currentMapStyle)
            .mapControls { }
            .ignoresSafeArea()
            
            // Overlay UI
            VStack {
                // Top bar with minimize button
                HStack {
                    // Minimize button (collapse to mini view)
                    Button(action: {
                        isPresented = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.down")
                                .font(.headline)
                            Text("Minimize")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.2).opacity(0.9))
                        .clipShape(Capsule())
                    }
                    .accessibilityLabel("Minimize navigation map")
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 60)
                
                Spacer()
                
                // Time estimate badge on route (floating)
                if let route = navigationManager.currentRoute {
                    HStack {
                        Spacer()
                        TimeBadge(minutes: Int(route.expectedTravelTime / 60))
                            .padding(.trailing, 100)
                        Spacer()
                    }
                    .padding(.bottom, 200)
                }
                
                Spacer()
                
                // Right side controls
                VStack(spacing: 12) {
                    // Map style button
                    Button(action: {
                        withAnimation {
                            mapStyle = mapStyle.next
                        }
                    }) {
                        Image(systemName: "map")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color(white: 0.2).opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    // Re-center button
                    Button(action: centerOnRoute) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color(white: 0.2).opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 180)
                .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Bottom directions panel
                DirectionsPanel(
                    destinationName: navigationManager.destinationName,
                    route: navigationManager.currentRoute,
                    currentInstruction: navigationManager.currentInstruction,
                    distanceToNextTurn: navigationManager.distanceToNextTurn,
                    onMinimize: {
                        // Just minimize, keep navigation running
                        isPresented = false
                    },
                    onStopNavigation: {
                        // Stop navigation entirely
                        navigationManager.stopNavigation()
                        isPresented = false
                    },
                    onStartNavigation: {
                        // Navigation already started, this begins voice guidance
                        navigationManager.announceCurrentStatus()
                    }
                )
            }
        }
        .onAppear {
            centerOnRoute()
        }
        .onChange(of: navigationManager.currentRoute) { _, _ in
            centerOnRoute()
        }
    }
    
    private var currentMapStyle: MapStyle {
        switch mapStyle {
        case .standard:
            return .standard(elevation: .realistic, pointsOfInterest: .including([.university, .library, .museum, .park]), showsTraffic: false)
        case .satellite:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic, pointsOfInterest: .including([.university, .library, .museum, .park]), showsTraffic: false)
        }
    }
    
    private func centerOnRoute() {
        guard let route = navigationManager.currentRoute,
              let userLocation = locationManager.currentLocation else {
            return
        }
        
        // Calculate region to show entire route
        let routeRect = route.polyline.boundingMapRect
        let padding = UIEdgeInsets(top: 100, left: 50, bottom: 250, right: 50)
        
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .rect(MKMapRect(
                x: routeRect.origin.x - padding.left,
                y: routeRect.origin.y - padding.top,
                width: routeRect.width + padding.left + padding.right,
                height: routeRect.height + padding.top + padding.bottom
            ))
        }
    }
}

// MARK: - Time Badge

struct TimeBadge: View {
    let minutes: Int
    
    var body: some View {
        Text("\(minutes) min")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Destination Marker

struct DestinationMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.9))
                    .frame(width: 36, height: 36)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
            }
            
            // Pin stem
            Rectangle()
                .fill(Color.gray.opacity(0.9))
                .frame(width: 3, height: 8)
            
            // Pin point
            Circle()
                .fill(Color.gray.opacity(0.9))
                .frame(width: 6, height: 6)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Navigation User Marker

struct NavigationUserMarker: View {
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
            
            // Main dot
            Circle()
                .fill(Color.blue)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                )
                .shadow(color: .blue.opacity(0.5), radius: 4)
        }
    }
}

// MARK: - Directions Panel

struct DirectionsPanel: View {
    let destinationName: String
    let route: MKRoute?
    let currentInstruction: NavigationDirection
    let distanceToNextTurn: Double
    let onMinimize: () -> Void
    let onStopNavigation: () -> Void
    let onStartNavigation: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)
            
            // Header
            HStack {
                Text("Directions")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Minimize button (just hides the view)
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.5))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Minimize")
                
                // Stop navigation button (X)
                Button(action: onStopNavigation) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.7))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop navigation")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            // Route summary
            if let route = route {
                VStack(spacing: 16) {
                    // Destination info
                    HStack(spacing: 12) {
                        Image(systemName: "figure.walk")
                            .font(.title2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(destinationName)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Text(formatTime(route.expectedTravelTime))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                Text("•")
                                    .foregroundColor(.gray)
                                
                                Text(formatDistance(route.distance))
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    // Current instruction (when navigating)
                    if currentInstruction != .unknown {
                        HStack(spacing: 12) {
                            Image(systemName: directionIcon)
                                .font(.title)
                                .foregroundColor(.green)
                                .frame(width: 44)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currentInstruction.rawValue)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                if distanceToNextTurn > 0 {
                                    Text("in \(formatDistance(distanceToNextTurn))")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                    }
                    
                    // Start button
                    Button(action: onStartNavigation) {
                        HStack {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.title2)
                            Text("Start Walking")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.15))
                .ignoresSafeArea()
        )
    }
    
    private var directionIcon: String {
        switch currentInstruction {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .straight: return "arrow.up"
        case .arrived: return "flag.checkered"
        case .unknown: return "questionmark"
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours) hr \(mins) min"
        }
    }
}

#Preview {
    NavigationMapView(
        navigationManager: RealTimeNavigationManager(),
        isPresented: .constant(true)
    )
}
