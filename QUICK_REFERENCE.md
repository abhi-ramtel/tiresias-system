# Quick Reference Card

## 🚀 Start Server
```bash
./start_server.sh
```
Note your IP address!

## 🔌 Setup USB Connection (Optional)
```bash
# One-time install
brew install libimobiledevice

# Start USB tunnel (keep running)
iproxy 8000 8000
```
App automatically uses USB if WiFi fails!

## 📱 Install on iPhone (First Time Only)

1. **Xcode → Settings → Accounts**
   - Add your Apple ID

2. **Open Project**
   ```bash
   open TiresiasApp/TiresiasApp.xcodeproj
   ```

3. **Select Target**
   - Top bar: Select your iPhone

4. **Run**
   - Press ▶︎ or ⌘R

5. **Trust Certificate** (iPhone)
   - Settings → General → VPN & Device Management
   - Tap your certificate → Trust

## 📋 Testing Workflow

```
┌─────────────────────────────────────────────┐
│  Terminal 1: Start Server                  │
│  ./start_server.sh                          │
│  Note: IP = 10.84.104.88                    │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│  Xcode: Run App (⌘R)                        │
│  App installs on iPhone                     │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│  iPhone: Trust Developer                    │
│  Settings → General → VPN & Device Mgmt     │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│  App: Configure IP                          │
│  Tap ⚙️ → Enter 10.84.104.88 → Save        │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│  App: Connect & Stream                      │
│  Tap Connect → Tap Stream                   │
└─────────────────────────────────────────────┘
              ↓
┌─────────────────────────────────────────────┐
│  Terminal: See Logs                         │
│  📹 Receiving: 30.0 FPS | Frame #123        │
└─────────────────────────────────────────────┘
```

## 🔧 Common Commands

| Command | Purpose |
|---------|---------|
| `./start_server.sh` | Start the Python server |
| `iproxy 8000 8000` | Start USB tunnel for wired connection |
| `./setup_usb.sh` | Auto-install iproxy and start tunnel |
| `./test_server.sh` | Test server endpoints |
| `./fix_firewall.sh` | Fix WiFi firewall issues |
| `ipconfig getifaddr en0` | Get Mac's IP address |
| `open TiresiasApp/TiresiasApp.xcodeproj` | Open in Xcode |
| `⌘R` in Xcode | Build and run |
| `⇧⌘K` in Xcode | Clean build folder |

## 📊 Status Indicators

| Status | Meaning |
|--------|---------|
| 🟢 Connected | WebSocket active |
| 🟠 Connecting... | Attempting connection |
| 🔴 Disconnected | No connection |
| � WiFi | Connected via wireless |
| 🔌 USB | Connected via cable (fallback) |
| �📹 30 FPS | Streaming at 30 frames/sec |
| 📦 Frames: 1234 | Total frames sent |
| ⏱️ 25ms | Network latency |

## 🐛 Quick Fixes

**Can't connect?**
```bash
# Test server from iPhone Safari:
http://YOUR_MAC_IP:8000/health
```

**Need to find IP?**
```bash
ipconfig getifaddr en0
```

**Server won't start?**
```bash
cd server
source venv/bin/activate
python main.py
```

**Build errors in Xcode?**
- Product → Clean Build Folder (⇧⌘K)
- Restart Xcode

**"Untrusted Developer"?**
- Settings → General → VPN & Device Management
- Trust your Apple ID

## 📁 Key Files

| File | What to Edit |
|------|--------------|
| [ContentView.swift](TiresiasApp/TiresiasApp/ContentView.swift) | UI and layout |
| [CameraManager.swift](TiresiasApp/TiresiasApp/CameraManager.swift) | Camera settings (FPS, quality) |
| [WebSocketManager.swift](TiresiasApp/TiresiasApp/WebSocketManager.swift) | Network configuration |
| [server/main.py](server/main.py) | Server logic |
| [server/detection.py](server/detection.py) | YOLO integration |

## 💡 Tips

- **Wireless debugging**: After first install, disconnect cable. Window → Devices → Connect via Network
- **Change FPS**: Edit `targetFPS` in CameraManager.swift
- **Change quality**: Edit `jpegQuality` in CameraManager.swift (0.1-1.0)
- **View logs**: Xcode → Window → Devices and Simulators → Open Console
- **Server stats**: Open http://YOUR_IP:8000/stats in browser
