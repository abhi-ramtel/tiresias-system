//
//  LocationManager.swift
//  TiresiasApp
//
//  Centralized location and heading manager for real-time navigation
//

import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var currentHeading: CLHeading?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationAvailable = false
    
    // Computed heading in degrees (0-360)
    var headingDegrees: Double {
        guard let heading = currentHeading else { return 0 }
        // Use true heading if available, otherwise magnetic
        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    
    private override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0 // Update every meter
        locationManager.headingFilter = 5.0 // Update every 5 degrees
        locationManager.activityType = .fitness // Walking navigation
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    // MARK: - Public Methods
    
    func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        print("📍 Location tracking started")
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        print("📍 Location tracking stopped")
    }
    
    /// Calculate bearing from current location to a destination
    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        guard let current = currentLocation?.coordinate else { return 0 }
        
        let lat1 = current.latitude.toRadians()
        let lat2 = destination.latitude.toRadians()
        let deltaLon = (destination.longitude - current.longitude).toRadians()
        
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        var bearing = atan2(y, x).toDegrees()
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)
        
        return bearing
    }
    
    /// Get relative direction (left/right/straight) to a bearing
    func relativeDirection(toBearing targetBearing: Double) -> NavigationDirection {
        let currentBearing = headingDegrees
        var diff = targetBearing - currentBearing
        
        // Normalize to -180 to 180
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        
        if abs(diff) < 20 {
            return .straight
        } else if diff > 0 {
            return .right
        } else {
            return .left
        }
    }
    
    /// Distance to a coordinate in meters
    func distance(to coordinate: CLLocationCoordinate2D) -> Double {
        guard let current = currentLocation else { return Double.infinity }
        let destination = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return current.distance(from: destination)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Filter out inaccurate readings
        guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy < 50 else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
            self.isLocationAvailable = true
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Filter out inaccurate readings
        guard newHeading.headingAccuracy >= 0 else { return }
        
        DispatchQueue.main.async {
            self.currentHeading = newHeading
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.startTracking()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
    }
}

// MARK: - Navigation Direction

enum NavigationDirection: String {
    case left = "Go left"
    case right = "Go right"
    case straight = "Go straight"
    case arrived = "You have arrived"
    case unknown = ""
    
    var accessibilityLabel: String {
        return rawValue
    }
}

// MARK: - Helpers

extension Double {
    func toRadians() -> Double {
        return self * .pi / 180.0
    }
    
    func toDegrees() -> Double {
        return self * 180.0 / .pi
    }
}
