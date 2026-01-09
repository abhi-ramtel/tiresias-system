# Tiresias iOS App - Installation & Testing Guide

## Prerequisites

### On Mac
- ✅ Python 3.10+ installed
- ✅ Xcode 15+ installed
- ✅ Mac and iPhone on same WiFi network

### On iPhone
- ✅ iOS 17.0 or later
- ✅ Lightning/USB-C cable for initial installation

---

## Step 1: Start the Python Server

### Option A: Using the Start Script (Recommended)
```bash
cd /Users/abhiramtel/Developer/tiresias-system
./start_server.sh
```

This script will:
- Show your Mac's IP address (you'll need this!)
- Create a Python virtual environment
- Install all dependencies
- Start the server on port 8000

### Option B: Manual Start
```bash
cd server
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python main.py
```

You should see:
```
🚀 Tiresias Edge Server v2.0
📡 Server: http://0.0.0.0:8000
📱 Connect from iOS using your Mac's IP address
```

**Important:** Note your Mac's IP address! You'll need it in the app.

To find it manually:
```bash
ipconfig getifaddr en0
```

---

## Step 2: Configure Your Development Certificate

### First Time Setup in Xcode

1. **Open Xcode Preferences**
   - Xcode → Settings (⌘,)
   - Go to "Accounts" tab
   
2. **Add Your Apple ID**
   - Click the "+" button
   - Sign in with your Apple ID
   - Select your account → click "Manage Certificates"
   - Click "+" → "iOS Development" (if not already there)

3. **Enable Developer Mode on iPhone** (iOS 16+)
   - Settings → Privacy & Security → Developer Mode
   - Toggle ON and restart iPhone

---

## Step 3: Open the Project in Xcode

```bash
cd /Users/abhiramtel/Developer/tiresias-system
open TiresiasApp/TiresiasApp.xcodeproj
```

Or double-click the `.xcodeproj` file in Finder.

---

## Step 4: Configure the Project

### 1. Select Your Team
- Click on "TiresiasApp" in the project navigator (left sidebar)
- Select the "TiresiasApp" target
- Go to "Signing & Capabilities" tab
- Under "Team", select your Apple ID / Personal Team

### 2. Change Bundle Identifier (if needed)
If you get a signing error, change the bundle ID:
- In "Signing & Capabilities"
- Change `com.tiresias.app` to `com.yourname.tiresias`

### 3. Connect Your iPhone
- Plug iPhone into Mac with USB cable
- Unlock your iPhone
- Trust this computer if prompted

### 4. Select iPhone as Target
- At the top of Xcode, click the device menu (next to the play button)
- Select your iPhone from the list

---

## Step 5: Build and Run

### First Run
1. Click the **Play** button (▶︎) or press **⌘R**
2. Xcode will compile and install the app
3. First time: You'll see "Untrusted Developer" error on iPhone

### Trust the Developer Certificate
1. On your iPhone:
   - Settings → General → VPN & Device Management
   - Find your Apple ID / certificate
   - Tap "Trust [Your Name]"
   - Confirm "Trust"

2. Return to the app and launch it

---

## Step 6: Use the App

**Need to find IP?**
```bash
ipconfig getifaddr en0
```

### Connect to Server

1. **Tap the gear icon** (⚙️) in top-right
2. **Enter your Mac's IP address** (from Step 1)
   - Example: `LOCAL_MAC_IP`
3. **Tap "Save"**

### Start Streaming

1. **Tap "Connect"** (green button)
   - Wait for status to show "Connected" ✅
   
2. **Tap "Stream"** (blue button)
   - Camera preview should appear
   - You'll see FPS counter and frame statistics

### On the Server
You should see in the terminal:
```
🟢 Client Connected: [iPhone IP]
📹 Receiving: 30.0 FPS | Frame #123 | Size: 15,234 bytes
```

---

## Troubleshooting

### "Code Signing Error"
**Solution:** 
- Make sure you're signed in to Xcode with your Apple ID
- Change the bundle identifier to something unique
- Select your Personal Team in Signing & Capabilities

### "Cannot connect to server"
**Solution:**
1. Verify server is running: Open http://[YOUR_MAC_IP]:8000/health in Safari on iPhone
2. Check firewall: System Settings → Network → Firewall → Allow port 8000
3. Verify same WiFi network
4. Try disabling VPN if active

### "Camera Permission Denied"
**Solution:**
- iPhone Settings → TiresiasApp → Camera → Enable

### "Low FPS" or "Laggy"
**Solution:**
- Move closer to WiFi router
- Reduce JPEG quality in [CameraManager.swift](TiresiasApp/TiresiasApp/CameraManager.swift) line 15:
  ```swift
  private let jpegQuality: CGFloat = 0.15  // Lower = faster
  ```

### "Build Failed"
**Solution:**
- Make sure all files are saved
- Clean build folder: Product → Clean Build Folder (⇧⌘K)
- Quit and restart Xcode

---

## Testing Checklist

- [ ] Server starts and shows IP address
- [ ] Xcode builds successfully
- [ ] App installs on iPhone
- [ ] Camera permission granted
- [ ] Can connect to server (green Connected status)
- [ ] Can start streaming (see FPS counter)
- [ ] Server receives frames (see terminal logs)
- [ ] Stats update in real-time
- [ ] Can disconnect/reconnect successfully

---

## Development Tips

### Running Without Cable (Wireless Debugging)

After first USB install:
1. Window → Devices and Simulators
2. Right-click your iPhone → Connect via Network
3. Now you can run without cable! (on same WiFi)

### Viewing Logs
- Window → Devices and Simulators
- Select your iPhone
- Click "Open Console" to see app logs

### Debugging
- Set breakpoints in Swift code
- Use `print()` statements
- Check Xcode console for errors

---

## Next Steps

Once basic streaming works:

1. **Add AI Detection**: Uncomment YOLO code in [server/main.py](server/main.py)
2. **Add LLM Analysis**: Install Ollama and enable scene descriptions
3. **Improve UI**: Customize SwiftUI views
4. **Add Features**: Voice feedback, haptics, notifications

---

## Need Help?

Check the logs:
- **iOS App**: Xcode console
- **Python Server**: Terminal output
- **Network**: Use iPhone Safari to test http://[MAC_IP]:8000/health
