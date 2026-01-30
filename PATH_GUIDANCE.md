# Path Guidance System Documentation

## Overview

The Tiresias Path Guidance System provides real-time, camera-based navigation assistance for visually impaired users. It uses computer vision to detect obstacles and provide directional guidance through both visual and voice feedback.

## Architecture

```
┌─────────────────┐     WebSocket      ┌─────────────────┐
│   iOS App       │ ◄──────────────── │  Python Server  │
│  (Camera Feed)  │ ────────────────► │  (AI Pipeline)  │
└─────────────────┘     Guidance       └─────────────────┘
        │                                      │
        ▼                                      ▼
┌─────────────────┐                   ┌─────────────────┐
│ PathGuidance    │                   │ YOLO Detection  │
│ Overlay View    │                   │ Path Analysis   │
└─────────────────┘                   └─────────────────┘
```

## Components

### Server-Side (Python)

#### `path_guidance.py`
- **PathGuidanceEngine**: Main class for path analysis
- **Zone Grid Analysis**: Divides frame into 5x3 grid (columns x rows)
- **Obstacle Scoring**: Weights obstacles by proximity, size, and priority
- **Direction Logic**: Determines safest path based on zone analysis

**Guidance Directions:**
| Direction | Description |
|-----------|-------------|
| `path_clear` | No obstacles, safe to proceed straight |
| `move_left` | Obstacle on right, move significantly left |
| `move_right` | Obstacle on left, move significantly right |
| `slight_left` | Minor adjustment left recommended |
| `slight_right` | Minor adjustment right recommended |
| `stop` | Immediate obstacle directly ahead |
| `slow_down` | Obstacle approaching, reduce speed |

#### `main.py` (Updated)
- Integrates PathGuidanceEngine into WebSocket pipeline
- Sends guidance JSON messages to iOS app
- Throttles guidance messages to 100ms intervals

### iOS App (Swift)

#### `CameraManager.swift`
- **CameraZoomLevel enum**: `.ultraWide` (0.5x) and `.wide` (1x)
- **switchCamera(to:)**: Hot-swaps between camera lenses
- **isUltraWideAvailable**: Checks device capability

#### `WebSocketManager.swift`
- **Published guidance properties**: direction, instruction, obstacles
- **Voice synthesis**: Announces critical direction changes
- **setGuidanceEnabled()**: Toggles server-side guidance

#### `PathGuidanceOverlayView.swift`
- **GuidanceInstructionBar**: Top bar with direction and instruction
- **DirectionArrowOverlay**: Animated direction indicator
- **PathClearIndicator**: Circular percentage gauge
- **CameraZoomSelector**: 0.5x/1x toggle buttons
- **ObstacleCountBadge**: Shows number of detected obstacles

#### `ContentView.swift` (Updated)
- Toggle button to show/hide path guidance overlay
- Integration with existing navigation features

## Usage

### Starting Path Guidance

1. **Connect to Server**: Tap the WiFi button to connect
2. **Start Streaming**: Tap the Play button to start camera streaming
3. **Enable Guidance**: Tap the "Guidance" button (eye icon)

### Camera Controls

- **0.5x (Ultra-Wide)**: Wider field of view, captures more scene
- **1x (Standard)**: Default camera, better detail

### Voice Announcements

Voice guidance is enabled by default and announces:
- "Move left" / "Move right" when direction change needed
- "Stop. Obstacle ahead" for immediate dangers
- "Path clear" when transitioning from blocked state

### Visual Indicators

| Color | Meaning |
|-------|---------|
| Green | Path clear, safe |
| Yellow | Caution, minor adjustment |
| Orange | Warning, significant obstacle |
| Red | Stop, immediate danger |

## API Reference

### WebSocket Messages (Server → iOS)

```json
{
  "type": "guidance",
  "direction": "move_left",
  "instruction": "Move left. Person ahead on right.",
  "confidence": 0.85,
  "path_clear_percent": 45.0,
  "obstacle_count": 2,
  "obstacles": [
    {"class": "person", "priority": true},
    {"class": "chair", "priority": false}
  ]
}
```

### WebSocket Commands (iOS → Server)

```json
{
  "type": "set_guidance",
  "enabled": true
}
```

## Obstacle Classification

### High Priority (Immediate Danger)
- person, car, bicycle, motorcycle, bus, truck, dog

### Standard Obstacles
- chair, couch, potted plant, bench, backpack, umbrella, suitcase
- fire hydrant, stop sign, parking meter, skateboard

## Performance Considerations

- **Frame Rate**: 30 FPS camera capture
- **Guidance Rate**: 10 Hz (100ms intervals)
- **Voice Throttle**: 2 seconds minimum between announcements
- **Direction Smoothing**: 3-frame history for stable guidance

## Files Modified/Created

### New Files
- `server/path_guidance.py` - Path analysis engine
- `TiresiasApp/PathGuidanceOverlayView.swift` - iOS overlay UI

### Modified Files
- `server/main.py` - Added guidance integration
- `TiresiasApp/CameraManager.swift` - Added camera switching
- `TiresiasApp/WebSocketManager.swift` - Added guidance handling
- `TiresiasApp/ContentView.swift` - Added guidance toggle

## Future Enhancements

1. **Haptic Feedback**: Vibration patterns for directions
2. **Distance Estimation**: How far obstacles are
3. **Terrain Analysis**: Detect stairs, curbs, uneven surfaces
4. **Indoor Navigation**: Combine with indoor positioning
5. **Custom Obstacle Profiles**: User-defined important objects
