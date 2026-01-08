# Tiresias Video Streaming - Testing Guide

## System Overview
This system streams live video from an iPhone camera to a MacBook via USB WebSocket connection using React Native and Python.

**Components:**
- **iOS App** (React Native): Captures camera frames and sends via WebSocket
- **Python Server** (FastAPI): Receives frames and displays them using OpenCV
- **USB Tunnel** (iproxy): Forwards network traffic over USB cable

---

## Prerequisites

### 1. Check iPhone Connection
```bash
xcrun xctrace list devices | grep -i "iphone"
```
**Expected Output:** You should see your iPhone listed (e.g., "iPhone (UDID)")

**If not showing:**
- Physically connect iPhone via USB cable
- Unlock your iPhone
- Tap "Trust This Computer" when prompted

### 2. Install Python Dependencies
```bash
pip install uvicorn fastapi opencv-python numpy
```

### 3. Configure Xcode Code Signing
Open Xcode workspace:
```bash
open /Users/abhiramtel/Developer/tiresias-system/client-ios/ios/TiresiasClient.xcworkspace
```

In Xcode:
1. Click **"TiresiasClient"** project (blue icon, left sidebar)
2. Select **"TiresiasClient"** under TARGETS
3. Go to **"Signing & Capabilities"** tab
4. Check ✅ **"Automatically manage signing"**
5. Select your **Team** (Apple ID) from dropdown
   - If no team exists: Click "Add Account" → Sign in with Apple ID (free)
6. Verify you see: **"Signing Certificate: Apple Development"**

---

## Step-by-Step Testing Process

### Terminal 1: Start Python Video Server

```bash
cd /Users/abhiramtel/Developer/tiresias-system/edge-folder/app
python3 server_vision.py
```

**✅ SUCCESS INDICATOR:**
```
INFO:     Started server process [12345]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

**Keep this terminal open and running!**

---

### Terminal 2: Start USB Port Forwarding

```bash
iproxy 8000 8000
```

**✅ SUCCESS INDICATOR:**
```
waiting for connection
```

**Keep this terminal open and running!**

---

### Terminal 3: Deploy App to iPhone

```bash
cd /Users/abhiramtel/Developer/tiresias-system/client-ios
npx react-native run-ios --udid "YOUR_DEVICE_UDID"
```

**Note:** Replace `YOUR_DEVICE_UDID` with your device UDID from `xcrun xctrace list devices`.

**✅ SUCCESS INDICATORS:**
1. Build completes without errors
2. Terminal shows: `BUILD SUCCEEDED`
3. App installs and launches on your iPhone

---

## What Happens When It Works

### On Your iPhone:
1. App launches automatically
2. **Camera Permission popup** appears → Tap **"Allow"**
3. You'll see the camera viewfinder (or app UI)
4. Frame streaming begins automatically in background

### In Terminal 1 (Python Server):
```
🟢 iPhone Connected: Ready to receive video.
```

### On Your Mac:
- **New window appears:** "Tiresias - iPhone Feed"
- Shows **LIVE video feed** from iPhone camera
- Real-time streaming (you should see movement immediately)

### In Terminal 2 (iproxy):
```
waiting for connection
accepted connection, fd = 5
```

---

## Success Checklist

| Step | Expected Result | Status |
|------|----------------|--------|
| iPhone shows in `xcrun xctrace list devices` | Device name and UDID visible | ⬜ |
| Python packages installed | No errors during `pip install` | ⬜ |
| Xcode signing configured | "Apple Development" certificate shown | ⬜ |
| Python server starts | "Uvicorn running on http://0.0.0.0:8000" | ⬜ |
| iproxy starts | "waiting for connection" | ⬜ |
| iOS app builds | "BUILD SUCCEEDED" | ⬜ |
| Camera permission granted | "Allow" tapped on iPhone | ⬜ |
| Server shows connection | "🟢 iPhone Connected: Ready to receive video." | ⬜ |
| OpenCV window appears | "Tiresias - iPhone Feed" window visible | ⬜ |
| Live video displays | Real-time camera feed on Mac screen | ⬜ |

---

## Controls

**To Stop Viewing:**
- Press **'q'** key while OpenCV window is focused

**To Stop Everything:**
1. Close OpenCV window (or press 'q')
2. Terminal 1: Press `Ctrl+C` (stops Python server)
3. Terminal 2: Press `Ctrl+C` (stops iproxy)
4. iPhone: Swipe up to close app

---

## Troubleshooting

### Problem: "Port 8000 already in use"
```bash
# Find and kill the process
lsof -ti:8000 | xargs kill -9

# Then restart the Python server
```

### Problem: "Could not find physical device"
- Unlock your iPhone
- Check USB cable is securely connected
- Trust the computer on iPhone if prompted
- Verify with: `xcrun xctrace list devices`

### Problem: No video window appears
**Check Terminal 1 logs:**
- If you see "🟢 iPhone Connected" → Server is receiving data
- If window doesn't appear: OpenCV display issue
  - Try reinstalling opencv: `pip3.13 install --upgrade opencv-python`

**Check Terminal 2:**
- Should show "accepted connection, fd = X"
- If not, iproxy isn't forwarding traffic

### Problem: App crashes immediately
- Check Python server is running FIRST
- Check iproxy is running SECOND
- Check iPhone trust settings
- Look at Xcode console for error messages

### Problem: Black screen on Mac
- iPhone camera might be covered
- App might not have camera permission
- Check Settings → TiresiasClient → Camera (should be ON)

### Problem: Signing error during build
```
error Signing for "TiresiasClient" requires a development team
```
**Solution:** Complete Step 3 in Prerequisites (Xcode signing configuration)

---

## Testing Procedure Summary

1. **Verify iPhone connected** → `xcrun xctrace list devices`
2. **Configure Xcode signing** → Open workspace, set Team
3. **Start server** → Terminal 1: `python3.13 server_vision.py`
4. **Start USB tunnel** → Terminal 2: `iproxy 8000 8000`
5. **Deploy app** → Terminal 3: `npm run ios -- --device "Your iPhone Name"`
6. **Grant camera permission** → iPhone: Tap "Allow"
7. **Verify video window** → Mac: "Tiresias - iPhone Feed" appears
8. **Test real-time streaming** → Move iPhone, see movement on Mac immediately

---

## Expected Performance

- **Latency:** ~100-200ms (over USB)
- **Frame Rate:** 15-30 FPS (depends on processing)
- **Resolution:** As configured in iOS app (default: camera native)
- **Connection:** Persistent WebSocket over USB (no WiFi needed)

---

## Architecture Flow

```
┌─────────────┐       USB Cable        ┌──────────────┐
│   iPhone    │◄──────────────────────►│   MacBook    │
│             │                         │              │
│ Camera      │                         │              │
│    ↓        │                         │              │
│ React       │    WebSocket over USB   │              │
│ Native App  │───────────────────────→ │ iproxy :8000 │
│             │   (JPEG binary data)    │      ↓       │
│             │                         │ Python Server│
│             │                         │      ↓       │
│             │                         │ OpenCV Window│
└─────────────┘                         └──────────────┘
```

---

## Quick Test Command Sequence

```bash
# Verify device connected
xcrun xctrace list devices | grep iPhone

# Terminal 1
cd /Users/abhiramtel/Developer/tiresias-system/edge-folder/app
python3 server_vision.py

# Terminal 2 (new window)
iproxy 8000 8000

# Terminal 3 (new window)
cd /Users/abhiramtel/Developer/tiresias-system/client-ios
npx react-native run-ios --udid "YOUR_DEVICE_UDID"
```

**Watch for the video window to appear on your Mac!**

---

## Status Check Commands

```bash
# Check if server is running
lsof -ti:8000

# Check if iproxy is running
ps aux | grep iproxy | grep -v grep

# Check connected devices
xcrun xctrace list devices

# View Python server logs
# (Look at Terminal 1 for connection status)
```

---

## Notes

- **USB connection is required** - WiFi won't work with this setup
- **iproxy must run continuously** during testing
- **Keep iPhone unlocked** during initial connection
- **Camera permission is mandatory** - app won't work without it
- **Development build only** - requires Xcode provisioning

---

## Success Confirmation

**You know everything is working when:**

✅ All 3 terminals show successful startup messages  
✅ iPhone app launches without crashes  
✅ Camera permission granted on iPhone  
✅ OpenCV window "Tiresias - iPhone Feed" appears on Mac  
✅ You see **live, real-time video** from your iPhone camera  
✅ Moving the iPhone shows immediate movement in the Mac window  

**If you see all of the above → SUCCESS! 🎉**
