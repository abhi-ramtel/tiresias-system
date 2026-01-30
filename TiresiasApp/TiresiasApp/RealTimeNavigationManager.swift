//
//  RealTimeNavigationManager.swift
//  TiresiasApp
//
//  Provides continuous, real-time voice navigation with simple directional cues
//  Optimized for accessibility: "Go left", "Go right", "Go straight"
//

import Foundation
import CoreLocation
import MapKit
import AVFoundation
import Combine

final class RealTimeNavigationManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isNavigating = false
    @Published var currentInstruction: NavigationDirection = .unknown
    @Published var distanceToNextTurn: Double = 0
    @Published var destinationName: String = ""
    @Published var hasActiveRoute = false
    
    // Route waypoints
    @Published private(set) var routeSteps: [RouteStep] = []
    @Published private(set) var currentStepIndex = 0
    
    // Route visualization
    @Published var currentRoute: MKRoute?
    @Published var destinationCoordinate: CLLocationCoordinate2D?
    
    // MARK: - Private Properties
    private let locationManager = LocationManager.shared
    private let synthesizer = AVSpeechSynthesizer()
    private var cancellables = Set<AnyCancellable>()
    
    // Navigation settings
    private let turnAnnouncementDistance: Double = 15.0 // meters before turn
    private let arrivalThreshold: Double = 10.0 // meters to consider arrived
    private let repeatInterval: TimeInterval = 5.0 // seconds between repeated cues
    private var lastAnnouncementTime = Date.distantPast
    private var lastAnnouncedDirection: NavigationDirection?
    
    // Audio session configuration
    private var isAudioConfigured = false
    
    override init() {
        super.init()
        setupAudioSession()
        observeLocationUpdates()
    }
    
    // MARK: - Audio Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try audioSession.setActive(true)
            isAudioConfigured = true
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Location Observation
    
    private func observeLocationUpdates() {
        locationManager.$currentLocation
            .compactMap { $0 }
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.processLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Navigation Control
    
    func startNavigation(to destination: String) {
        destinationName = destination
        searchAndNavigate(to: destination)
    }
    
    func stopNavigation() {
        isNavigating = false
        hasActiveRoute = false
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = .unknown
        currentRoute = nil
        destinationCoordinate = nil
        synthesizer.stopSpeaking(at: .immediate)
        speak("Navigation stopped")
    }
    
    // MARK: - Route Calculation
    
    private func searchAndNavigate(to destination: String) {
        guard let userLocation = locationManager.currentLocation else {
            speak("Cannot get your current location")
            return
        }
        
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = destination
        searchRequest.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        
        MKLocalSearch(request: searchRequest).start { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Search error: \(error)")
                self.speak("Could not find \(destination)")
                return
            }
            
            guard let place = response?.mapItems.first else {
                self.speak("No results found for \(destination)")
                return
            }
            
            self.calculateRoute(to: place, from: userLocation)
        }
    }
    
    private func calculateRoute(to destination: MKMapItem, from userLocation: CLLocation) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = destination
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        
        MKDirections(request: request).calculate { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Directions error: \(error)")
                self.speak("Could not calculate route")
                return
            }
            
            guard let route = response?.routes.first else {
                self.speak("No walking route available")
                return
            }
            
            // Store route for visualization
            DispatchQueue.main.async {
                self.currentRoute = route
                self.destinationCoordinate = destination.placemark.coordinate
            }
            
            // Convert MKRoute.Step to our RouteStep
            self.routeSteps = route.steps.enumerated().compactMap { index, step in
                guard !step.instructions.isEmpty else { return nil }
                return RouteStep(
                    coordinate: step.polyline.coordinate,
                    instruction: step.instructions,
                    distance: step.distance,
                    direction: self.parseDirection(from: step.instructions)
                )
            }
            
            guard !self.routeSteps.isEmpty else {
                self.speak("Route has no steps")
                return
            }
            
            DispatchQueue.main.async {
                self.isNavigating = true
                self.hasActiveRoute = true
                self.currentStepIndex = 0
            }
            
            // Announce start
            let totalDistance = route.distance
            let distanceText = self.formatDistance(totalDistance)
            self.speak("Starting navigation to \(self.destinationName). Total distance: \(distanceText)")
        }
    }
    
    // MARK: - Real-Time Location Processing
    
    private func processLocationUpdate(_ location: CLLocation) {
        guard isNavigating, !routeSteps.isEmpty else { return }
        guard currentStepIndex < routeSteps.count else {
            announceArrival()
            return
        }
        
        let currentStep = routeSteps[currentStepIndex]
        let distanceToStep = locationManager.distance(to: currentStep.coordinate)
        
        DispatchQueue.main.async {
            self.distanceToNextTurn = distanceToStep
            self.currentInstruction = currentStep.direction
        }
        
        // Check if we've reached the current waypoint
        if distanceToStep < arrivalThreshold {
            advanceToNextStep()
            return
        }
        
        // Announce upcoming turn
        if distanceToStep < turnAnnouncementDistance {
            announceDirection(currentStep.direction, distance: distanceToStep)
        } else {
            // Periodic "go straight" reminder
            let timeSinceLastAnnouncement = Date().timeIntervalSince(lastAnnouncementTime)
            if timeSinceLastAnnouncement > repeatInterval {
                announceDirection(.straight, distance: nil)
            }
        }
    }
    
    private func advanceToNextStep() {
        currentStepIndex += 1
        
        if currentStepIndex >= routeSteps.count {
            announceArrival()
        } else {
            let nextStep = routeSteps[currentStepIndex]
            announceDirection(nextStep.direction, distance: nextStep.distance, immediate: true)
        }
    }
    
    private func announceArrival() {
        DispatchQueue.main.async {
            self.isNavigating = false
            self.hasActiveRoute = false
            self.currentInstruction = .arrived
        }
        speak("You have arrived at \(destinationName)")
    }
    
    // MARK: - Voice Announcements
    
    private func announceDirection(_ direction: NavigationDirection, distance: Double?, immediate: Bool = false) {
        let now = Date()
        
        // Don't repeat the same direction too frequently unless immediate
        if !immediate {
            if direction == lastAnnouncedDirection &&
               now.timeIntervalSince(lastAnnouncementTime) < repeatInterval {
                return
            }
        }
        
        var message = direction.rawValue
        
        if let dist = distance, dist > 5 {
            let distanceText = formatDistance(dist)
            if direction != .straight {
                message = "\(direction.rawValue) in \(distanceText)"
            }
        }
        
        speak(message)
        lastAnnouncementTime = now
        lastAnnouncedDirection = direction
    }
    
    func speak(_ text: String) {
        // Stop current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1 // Slightly faster for real-time
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // High priority for navigation
        utterance.prefersAssistiveTechnologySettings = true
        
        synthesizer.speak(utterance)
        
        // Also announce to VoiceOver users
        UIAccessibility.post(notification: .announcement, argument: text)
    }
    
    // MARK: - Helpers
    
    private func parseDirection(from instruction: String) -> NavigationDirection {
        let lowercased = instruction.lowercased()
        
        if lowercased.contains("left") {
            return .left
        } else if lowercased.contains("right") {
            return .right
        } else if lowercased.contains("straight") || lowercased.contains("continue") || lowercased.contains("head") {
            return .straight
        } else if lowercased.contains("arrive") || lowercased.contains("destination") {
            return .arrived
        }
        
        return .straight
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 10 {
            return "a few steps"
        } else if meters < 100 {
            return "\(Int(meters)) meters"
        } else if meters < 1000 {
            let rounded = Int((meters / 10).rounded()) * 10
            return "\(rounded) meters"
        } else {
            let km = meters / 1000
            return String(format: "%.1f kilometers", km)
        }
    }
}

// MARK: - Route Step Model

struct RouteStep {
    let coordinate: CLLocationCoordinate2D
    let instruction: String
    let distance: Double
    let direction: NavigationDirection
}

// MARK: - Quick Navigation Commands

extension RealTimeNavigationManager {
    /// Announce current status on demand (for accessibility)
    func announceCurrentStatus() {
        guard isNavigating else {
            speak("No active navigation")
            return
        }
        
        let direction = currentInstruction.rawValue
        let distance = formatDistance(distanceToNextTurn)
        speak("\(direction). \(distance) to next turn. Heading to \(destinationName)")
    }
    
    /// Quick left/right check based on current heading
    func announceHeading() {
        let heading = locationManager.headingDegrees
        let cardinal = cardinalDirection(from: heading)
        speak("You are facing \(cardinal)")
    }
    
    private func cardinalDirection(from degrees: Double) -> String {
        let directions = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}
