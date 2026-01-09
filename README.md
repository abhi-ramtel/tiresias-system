# Tiresias System

Visual AI assistance system that streams camera feed from iPhone to a Mac edge server for real-time analysis.

## Architecture

```
┌─────────────────┐     WebSocket      ┌─────────────────┐
│   iOS App       │ ────────────────▶  │  Python Server  │
│   (SwiftUI)     │   JPEG Frames      │   (FastAPI)     │
│                 │ ◀────────────────  │                 │
│   Camera Feed   │   AI Results       │  YOLO + Ollama  │
└─────────────────┘                    └─────────────────┘
```

## Components

### iOS App (`TiresiasApp/`)
Pure Swift/SwiftUI app that:
- Captures camera frames at 30 FPS
- Compresses frames to JPEG (25% quality for speed)
- Streams frames via WebSocket to edge server
- Displays connection status and statistics

### Python Server (`server/`)
FastAPI WebSocket server that:
- Receives JPEG frames from iOS app
- Runs YOLO object detection
- Optionally runs LLM scene analysis via Ollama
- Sends results back to client

## Features

- ✅ Pure Swift/SwiftUI native iOS app
- ✅ 30 FPS camera streaming with adaptive quality
- ✅ **Automatic WiFi/USB fallback** - tries WiFi first, then USB if it fails
- ✅ Real-time connection status and statistics
- ✅ WebSocket streaming with auto-reconnection
- ✅ FastAPI Python backend with YOLO detection ready
- ✅ Optional LLM scene analysis via Ollama
- ✅ Low latency (typically <50ms on local network)

## Quick Start

### 1. Start the Python Server

```bash
./start_server.sh
```

The script will:
- Show your Mac's IP address (you'll need this!)
- Install dependencies automatically
- Start the server on port 8000

You should see:
```
📍 Your Mac's IP address: LOCAL_MAC_IP
🚀 Tiresias Edge Server v2.0
📡 Server: http://0.0.0.0:8000
```

### 2. Install the iOS App

See **[INSTALLATION.md](INSTALLATION.md)** for detailed instructions.

**Quick version:**
1. Open `TiresiasApp/TiresiasApp.xcodeproj` in Xcode
2. Sign in with your Apple ID (Xcode → Settings → Accounts)
3. Connect your iPhone via USB
4. Select your iPhone as the target
5. Click Run (▶︎) or press ⌘R
6. On iPhone: Settings → General → VPN & Device Management → Trust your certificate
7. Launch the app

### 3. Connect and Stream

1. In the app, tap the gear icon ⚙️
2. Enter your Mac's IP address from Step 1
3. Tap "Save"
4. Tap "Connect" (green button)
5. Tap "Stream" (blue button)

You should see frames streaming! Check the server terminal for logs.

**Connection Method:** The app shows "WiFi" or "USB" indicator. It automatically tries WiFi first, then falls back to USB if WiFi fails.

---

## USB Connection (Wired Fallback)

The app **automatically uses USB** if WiFi fails! 

### One-Time Setup:
```bash
# Install iproxy
brew install libimobiledevice
```

### Usage:
1. Connect iPhone via USB cable
2. In a separate terminal:
   ```bash
   iproxy 8000 8000
   ```
3. Tap "Connect" in the app - it will use USB if WiFi fails

See **[USB_CONNECTION.md](USB_CONNECTION.md)** for detailed USB setup guide.

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Server info |
| `/health` | GET | Health check |
| `/stats` | GET | Server statistics |
| `/ws/video` | WebSocket | Video frame streaming |

## Requirements

### iOS
- iOS 17.0+
- iPhone with camera
- Same WiFi network as Mac

### Server
- Python 3.10+
- macOS/Linux
- (Optional) NVIDIA GPU for faster inference
- (Optional) Ollama for LLM analysis

## Optional: Enable LLM Analysis

For natural language scene descriptions:

```bash
# Install Ollama
brew install ollama

# Start Ollama server
ollama serve

# Pull a vision model
ollama pull llava
```

## Project Structure

```
tiresias-system/
├── TiresiasApp/                 # iOS App (Swift/SwiftUI)
│   └── TiresiasApp/
│       ├── TiresiasApp.swift    # App entry point
│       ├── ContentView.swift    # Main UI
│       ├── CameraManager.swift  # Camera capture
│       ├── WebSocketManager.swift # Server connection
│       ├── CameraPreviewView.swift # Camera preview
│       └── ConnectionStatus.swift  # Status UI
├── server/                      # Python Backend
│   ├── main.py                  # FastAPI server
│   ├── detection.py             # YOLO inference
│   ├── analysis.py              # LLM analysis
│   └── requirements.txt         # Python dependencies
└── README.md
```

## Troubleshooting

### Can't connect to server
1. Ensure Mac and iPhone are on the same WiFi network
2. Check firewall isn't blocking port 8000
3. Verify the IP address is correct
4. Make sure the server is running

### Low FPS
1. Ensure good WiFi signal
2. Try reducing image quality in CameraManager.swift
3. Check server CPU usage

### Server not receiving frames
1. Check WebSocket connection status in app
2. Look for errors in server console
3. Try reconnecting

## License

MIT
