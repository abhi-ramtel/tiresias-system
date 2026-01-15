//
//  MiniMapView.swift
//  TiresiasApp
//
//  Compact map view showing current location and heading only
//  Optimized for accessibility - minimal UI, just location awareness
//

import SwiftUI
import MapKit

struct MiniMapView: View {
    @ObservedObject var locationManager = LocationManager.shared
    @Binding var isExpanded: Bool
    
    // Map camera position
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        ZStack {
            // Map content
            Map(position: $cameraPosition) {
                // User location with heading indicator
                if let location = locationManager.currentLocation {
                    Annotation("You", coordinate: location.coordinate) {
                        UserLocationMarker(heading: locationManager.headingDegrees)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { } // Remove all default controls for cleaner accessibility UI
            .allowsHitTesting(false) // Disable map interaction, tap goes to expansion
            
            // Tap overlay to expand
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded = true
                    }
                    announceForAccessibility("Expanding map view")
                }
            
            // Expand indicator
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(4)
                }
            }
        }
        .frame(width: 120, height: 120)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mini map showing your location")
        .accessibilityHint("Double tap to expand to full map")
        .accessibilityAddTraits(.isButton)
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            updateCameraPosition(for: newLocation)
        }
        .onAppear {
            locationManager.requestPermissions()
            if let location = locationManager.currentLocation {
                updateCameraPosition(for: location)
            }
        }
    }
    
    private func updateCameraPosition(for location: CLLocation?) {
        guard let location = location else { return }
        
        cameraPosition = .camera(
            MapCamera(
                centerCoordinate: location.coordinate,
                distance: 200, // Close zoom for pedestrian navigation
                heading: locationManager.headingDegrees,
                pitch: 0
            )
        )
    }
    
    private func announceForAccessibility(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

// MARK: - User Location Marker with Heading

struct UserLocationMarker: View {
    let heading: Double
    
    var body: some View {
        ZStack {
            // Heading direction cone
            Triangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 30, height: 40)
                .rotationEffect(.degrees(heading))
                .offset(y: -15)
            
            // Center dot
            Circle()
                .fill(Color.blue)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: .blue.opacity(0.5), radius: 4)
        }
    }
}

// MARK: - Triangle Shape for Heading

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray
        MiniMapView(isExpanded: .constant(false))
    }
}
