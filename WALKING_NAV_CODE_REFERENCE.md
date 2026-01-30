# Walking Navigation - Code Reference

## Quick Reference Guide

### How to Trigger Navigation

```swift
// In ContentView, when user taps "Navigate" button:
realtimeNavManager.startNavigation(to: "Central Park")

// The manager handles:
// 1. Location search via MKLocalSearch
// 2. Walking route calculation via MKDirections  
// 3. Route storage for map visualization
// 4. Voice announcements for turn-by-turn navigation
```

### What Gets Displayed on Map

#### Mini Map (120x120)
```swift
// Blue walking route
MapPolyline(navigationManager.currentRoute!.polyline)
    .stroke(.blue, lineWidth: 3)

// Red destination pin
Annotation("", coordinate: destinationCoordinate) {
    Image(systemName: "mappin.circle.fill")
        .foregroundColor(.red)
}

// Your location with heading
Annotation("You", coordinate: userLocation) {
    UserLocationMarker(heading: currentHeading)
}
```

#### Expanded Map (Full Screen)
```swift
// Same route polyline but thicker
MapPolyline(route.polyline)
    .stroke(.blue, lineWidth: 4)

// Destination with label
Annotation("Destination: \(destinationName)", coordinate: destination) {
    VStack(spacing: 4) {
        Image(systemName: "mappin.circle.fill")
            .foregroundColor(.red)
        Text(destinationName)
            .padding(4)
            .background(Color.red.opacity(0.8))
    }
}

// Route statistics panel
HStack(spacing: 16) {
    Text("\(formatDistance(route.distance))") // "2.3 km"
    Text("\(formatTime(route.expectedTravelTime))") // "28m"
    Text("\(route.steps.count)") // number of turns
}
```

### Route Calculation Logic

```swift
private func calculateRoute(to destination: MKMapItem, from userLocation: CLLocation) {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(
        coordinate: userLocation.coordinate
    ))
    request.destination = destination
    request.transportType = .walking  // ← WALKING ONLY
    request.requestsAlternateRoutes = false
    
    MKDirections(request: request).calculate { response, error in
        guard let route = response?.routes.first else { return }
        
        // Store for visualization
        DispatchQueue.main.async {
            self.currentRoute = route  // ← Published, triggers map update
            self.destinationCoordinate = destination.placemark.coordinate
        }
        
        // Process route steps for turn-by-turn navigation
        self.routeSteps = route.steps.enumerated().compactMap { index, step in
            RouteStep(
                coordinate: step.polyline.coordinate,
                instruction: step.instructions,
                distance: step.distance,
                direction: parseDirection(from: step.instructions)
            )
        }
        
        self.isNavigating = true
        self.hasActiveRoute = true
    }
}
```

### Map Updates on Route Change

```swift
// In MiniMapView and ExpandedMapView
.onChange(of: navigationManager.currentRoute) { _, _ in
    if navigationManager.currentRoute != nil {
        // Route loaded, update camera position
        updateCameraPosition(for: userLocation)
        
        // Announce for accessibility
        announceForAccessibility("Walking route loaded")
    }
}
```

### Data Flow

```
User Input (Voice)
    ↓
NavigationAgent.startListeningWithCallback
    ↓
Destination string (e.g., "Central Park")
    ↓
RealTimeNavigationManager.startNavigation(to: destination)
    ↓
MKLocalSearch.start { response in
    if let place = response?.mapItems.first {
        calculateRoute(to: place, from: userLocation)
    }
}
    ↓
MKDirections.calculate { response in
    currentRoute = response?.routes.first
    destinationCoordinate = place.coordinate
    // ← Triggers map view updates automatically
    
    // Route steps for voice guidance
    routeSteps = route.steps.map { ... }
}
    ↓
Map displays:
    • Blue polyline
    • Red destination pin
    • Route statistics
    ↓
Voice navigation begins
    "Starting navigation to Central Park"
    "In 50 meters, turn right"
    etc.
```

### Key Published Properties

**RealTimeNavigationManager:**
```swift
@Published var currentRoute: MKRoute?
    // The walking route with polyline data
    
@Published var destinationCoordinate: CLLocationCoordinate2D?
    // Final destination location
    
@Published var hasActiveRoute: Bool
    // True when route is ready
    
@Published var isNavigating: Bool
    // True during active turn-by-turn navigation
    
@Published var routeSteps: [RouteStep]
    // Individual turn-by-turn instructions
```

### Cleanup on Stop

```swift
func stopNavigation() {
    isNavigating = false
    hasActiveRoute = false
    routeSteps = []
    currentStepIndex = 0
    currentInstruction = .unknown
    currentRoute = nil  // ← Clear from map
    destinationCoordinate = nil  // ← Remove destination marker
    synthesizer.stopSpeaking(at: .immediate)
    speak("Navigation stopped")
}
```

### MKRoute Properties Available

```swift
if let route = navigationManager.currentRoute {
    // Display on map
    route.polyline  // MKPolyline with all coordinates
    
    // Provide route info
    route.distance  // Double in meters
    route.expectedTravelTime  // TimeInterval in seconds
    
    // Step-by-step details
    route.steps  // [MKRoute.Step]
    
    // Each step contains:
    // - instructions: String ("Turn right on Main Street")
    // - distance: Double (meters)
    // - polyline: MKPolyline (coordinates for that segment)
}
```

### Helper Functions

```swift
// Format meters to readable distance
func formatDistance(_ meters: Double) -> String {
    if meters < 1000 {
        return "\(Int(meters))m"
    } else {
        return String(format: "%.1f km", meters / 1000)
    }
}

// Format seconds to readable time
func formatTime(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 {
        return "\(minutes)m"
    } else {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }
}
```

---

## Design Rationale

### Why Walking-Only Routes?
- Ensures accessibility for blind/low-vision users
- No highways or fast-paced traffic
- Direct pedestrian paths optimal for walking speed
- Safer in urban environments

### Why Store Current Route?
- Map views automatically subscribe to changes
- UI updates reactively when route loads
- Clean separation between navigation logic and UI
- Supports future route recalculation if needed

### Why Both Mini and Expanded Maps?
- **Mini**: Quick glance at route while focusing on camera stream
- **Expanded**: Detailed analysis before starting, during navigation
- Accessibility: Touch-friendly larger map for detailed navigation

### Why Voice Guidance + Visual?
- Voice: Primary for accessibility (blind users)
- Visual: Confirmation and context awareness
- Combined: Better experience for all users

---

## Testing Scenarios

### Scenario 1: Simple Route
```
Destination: "Coffee Shop"
Expected: 
  - Blue line appears on map
  - Distance < 1 km shown
  - Time estimate displayed
  - Voice announces first turn
```

### Scenario 2: Long Route  
```
Destination: "Times Square" (from distance away)
Expected:
  - Long blue polyline on map
  - Multiple turn waypoints visible
  - Distance in km format
  - Time in hours and minutes
  - Multiple voice cues as you progress
```

### Scenario 3: Invalid Destination
```
Destination: "xyz123abc" (not found)
Expected:
  - MKLocalSearch returns no results
  - Voice says "No results found for xyz123abc"
  - No route displayed
  - Maps remain unchanged
```

### Scenario 4: Stop Navigation
```
User taps "Stop" during navigation
Expected:
  - currentRoute becomes nil
  - destinationCoordinate becomes nil
  - Blue polyline disappears from map
  - Red destination pin disappears
  - Voice says "Navigation stopped"
  - Map returns to showing only user location
```
