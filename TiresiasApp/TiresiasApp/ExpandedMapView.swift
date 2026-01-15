//
//  ExpandedMapView.swift
//  TiresiasApp
//
//  Full-screen map view for detailed location awareness
//  Accessibility-optimized: shows only location, no routing UI
//

import SwiftUI
import MapKit

struct ExpandedMapView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @Binding var isPresented: Bool
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyle: MapStyleOption = .standard
    
    var body: some View {
        ZStack {
            // Full map
            Map(position: $cameraPosition) {
                // User location with detailed heading
                if let location = locationManager.currentLocation {
                    Annotation("Your Location", coordinate: location.coordinate) {
                        ExpandedUserMarker(heading: locationManager.headingDegrees)
                    }
                }
            }
            .mapStyle(currentMapStyle)
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea()
            
            // Overlay controls
            VStack {
                // Top bar
                HStack {
                    // Close button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                        announceForAccessibility("Closing map")
                    }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Close map")
                    
                    Spacer()
                    
                    // Map style toggle
                    Button(action: {
                        withAnimation {
                            mapStyle = mapStyle.next
                        }
                    }) {
                        Image(systemName: mapStyle.icon)
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Change map style, current: \(mapStyle.rawValue)")
                }
                .padding()
                .padding(.top, 40) // Safe area
                
                Spacer()
                
                // Bottom info panel
                VStack(spacing: 12) {
                    // Location info
                    if let location = locationManager.currentLocation {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Accuracy")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(Int(location.horizontalAccuracy))m")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .frame(height: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Heading")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("\(Int(locationManager.headingDegrees))°")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            
                            Divider()
                                .frame(height: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Speed")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                let speed = max(0, location.speed)
                                Text("\(String(format: "%.1f", speed)) m/s")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Location accuracy \(Int(location.horizontalAccuracy)) meters, heading \(Int(locationManager.headingDegrees)) degrees")
                    }
                    
                    // Re-center button
                    Button(action: recenterMap) {
                        Label("Re-center", systemImage: "location.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .accessibilityLabel("Re-center map on your location")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .padding()
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            // Don't auto-update camera if user has panned
        }
        .onAppear {
            recenterMap()
        }
    }
    
    private var currentMapStyle: MapStyle {
        switch mapStyle {
        case .standard:
            return .standard(pointsOfInterest: .excludingAll, showsTraffic: false)
        case .satellite:
            return .imagery
        case .hybrid:
            return .hybrid(pointsOfInterest: .excludingAll, showsTraffic: false)
        }
    }
    
    private func recenterMap() {
        guard let location = locationManager.currentLocation else { return }
        
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: location.coordinate,
                    distance: 300,
                    heading: locationManager.headingDegrees,
                    pitch: 45 // Slight tilt for better spatial awareness
                )
            )
        }
        announceForAccessibility("Map centered on your location")
    }
    
    private func announceForAccessibility(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - Map Style Options

enum MapStyleOption: String, CaseIterable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    
    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas"
        case .hybrid: return "map.fill"
        }
    }
    
    var next: MapStyleOption {
        let all = MapStyleOption.allCases
        let currentIndex = all.firstIndex(of: self) ?? 0
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }
}

// MARK: - Expanded User Marker

struct ExpandedUserMarker: View {
    let heading: Double
    
    var body: some View {
        ZStack {
            // Outer pulse ring
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 60, height: 60)
            
            // Heading cone
            HeadingCone()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.4), Color.blue.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 50, height: 70)
                .rotationEffect(.degrees(heading - 90))
                .offset(y: -20)
            
            // Center marker
            Circle()
                .fill(Color.blue)
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                )
                .shadow(color: .blue, radius: 8)
        }
    }
}

// MARK: - Heading Cone Shape

struct HeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.8, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX * 0.2, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 0.8)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ExpandedMapView(isPresented: .constant(true))
}
