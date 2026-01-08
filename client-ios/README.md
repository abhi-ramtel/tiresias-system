# Tiresias Client - iOS

iPhone camera streaming client for the Tiresias assistive navigation system. Captures video from the iPhone camera and streams it via WebSocket to the MacBook edge server for real-time AI processing.

## Architecture

```
┌─────────────────┐         WiFi/WebSocket          ┌─────────────────┐
│   iPhone        │  ──────────────────────────────▶│   MacBook       │
│   (Thin Client) │     JPEG frames @ ~10 FPS       │   (Edge Server) │
│                 │                                  │                 │
│  • Camera       │                                  │  • YOLOv10      │
│  • WebSocket    │                                  │  • Llama 3.2    │
│  • Haptic FB    │◀──────────────────────────────── │  • OpenCV       │
└─────────────────┘     Audio + Haptic Commands      └─────────────────┘
```

## Prerequisites

- **macOS** with Xcode 15+ installed
- **Node.js** 18+ 
- **CocoaPods** (`sudo gem install cocoapods`)
- Physical iPhone (camera not available in simulator)

## Quick Start

### 1. Install Dependencies

```bash
cd client-ios
npm install
cd ios && pod install && cd ..
```

### 2. Configure Edge Server IP

Edit `App.tsx` and update the server URL to your Mac's IP:

```typescript
const EDGE_SERVER_URL = 'ws://YOUR_MAC_IP:8000/ws/video';
```

Find your Mac's IP with: `ipconfig getifaddr en0`

### 3. Start Metro Bundler

```bash
npm start
```

### 4. Build & Run on iPhone

```bash
# Find your iPhone's UDID
xcrun xctrace list devices

# Build and install
npx react-native run-ios --udid YOUR_IPHONE_UDID
```

### 5. Start Edge Server (on Mac)

```bash
cd ../edge-folder/app
python server_vision.py
```

## Usage

1. Open **TiresiasClient** app on your iPhone
2. Grant camera permission when prompted
3. Tap the green **START** button to begin streaming
4. View the live feed in the OpenCV window on your Mac
5. Press **q** in the OpenCV window to close, or tap **STOP** on iPhone

## Features

- 📷 Real-time camera capture using VisionCamera
- 🔌 WebSocket streaming to edge server
- 📊 FPS counter overlay
- 🔴🟢 Connection status indicator
- 🎨 Clean, accessible UI

## Project Structure

```
client-ios/
├── App.tsx              # Main app - camera + WebSocket logic
├── package.json         # Dependencies
├── ios/
│   ├── Podfile          # CocoaPods dependencies
│   ├── TiresiasClient/  # Native iOS project
│   └── Pods/            # Installed pods
└── __tests__/           # Jest tests
```

## Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| react-native | 0.76.1 | Core framework |
| react-native-vision-camera | 4.7.3 | Camera access |
| react-native-worklets-core | 1.6.2 | Frame processing |
| react-native-haptic-feedback | 2.3.3 | Haptic responses |

## Troubleshooting

### Build fails with "PhaseScriptExecution failed"
- Ensure project path has **no spaces** (move to `~/Developer/`)

### "Cannot connect to edge server"
- Verify Mac and iPhone are on the **same WiFi network**
- Check edge server is running: `curl http://YOUR_MAC_IP:8000/`
- Ensure firewall allows port 8000

### Camera permission denied
- Go to iPhone Settings → Privacy → Camera → TiresiasClient → Enable

### Metro bundler port in use
```bash
lsof -ti:8081 | xargs kill -9
npm start --reset-cache
```

## Development

### Reload App
- Shake iPhone → "Reload"
- Or press `r` in Metro terminal

### Debug
- Shake iPhone → "Open DevTools"
- Or press `j` in Metro terminal

## License

Part of the Tiresias assistive navigation system.
