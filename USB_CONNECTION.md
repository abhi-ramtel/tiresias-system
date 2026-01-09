# USB/Wired Connection Guide

## Overview

The app now **automatically tries USB connection** if WiFi fails! 

When you tap "Connect":
1. 🔵 Tries WiFi first (`your-mac-ip:8000`)
2. 🔌 If WiFi fails, automatically tries USB (`localhost:8000`)
3. ✅ Connects via whichever method works

The UI shows which connection method is active.

---

## Setup USB Tunnel (One-Time)

### Install iproxy

```bash
# Install via Homebrew
brew install libimobiledevice
```

Or use the automated script:
```bash
./setup_usb.sh
```

---

## Using USB Connection

### Option 1: Automatic (Recommended)

1. **Connect iPhone via USB cable**
2. **In one terminal, start the server:**
   ```bash
   ./start_server.sh
   ```

3. **In another terminal, start USB tunnel:**
   ```bash
   iproxy 8000 8000
   ```
   Leave this running!

4. **In the app:**
   - Just tap "Connect"
   - If WiFi fails, it automatically tries USB
   - You'll see "USB" indicator when connected via cable

### Option 2: USB-Only Mode

If you ONLY want to use USB (no WiFi attempt):

1. In the app settings, set IP to: `localhost`
2. Make sure USB tunnel is running
3. Connect!

---

## When to Use USB vs WiFi

| Scenario | Best Method | Why |
|----------|-------------|-----|
| Development/Testing | USB | Faster, more reliable |
| Demo/Presentation | WiFi | No cable needed |
| Network issues | USB | Bypasses firewall/router |
| High bandwidth needs | USB | USB 3.0 is faster than WiFi |
| Battery life priority | USB | Charges while using |

---

## Complete Workflow

### Terminal 1: Server
```bash
cd /Users/abhiramtel/Developer/tiresias-system
./start_server.sh
```

### Terminal 2: USB Tunnel (if using USB)
```bash
iproxy 8000 8000
```

### Xcode: Run App
```bash
open TiresiasApp/TiresiasApp.xcodeproj
# Press ⌘R
```

### iPhone: Connect
- Tap "Connect" button
- App tries WiFi first, then USB automatically
- Check the connection indicator to see which is active

---

## Troubleshooting USB Connection

### "Cannot connect" even with cable

**Check iPhone trust:**
```bash
idevice_id -l
```
Should show your device ID. If not:
- Unlock iPhone
- Tap "Trust" when prompted
- Try again

**Check if tunnel is running:**
```bash
lsof -i :8000
```
Should show both `Python` and `iproxy`

**Test localhost:**
```bash
curl http://localhost:8000/health
```
Should return `{"status":"ok"}`

### "iproxy not found"

Install it:
```bash
brew install libimobiledevice
```

### "Address already in use"

Another process is using port 8000:
```bash
# Find it
lsof -i :8000

# Kill it
kill -9 <PID>

# Or use different port
iproxy 8001 8000
# Then update app to use 8001
```

---

## How It Works

```
Without USB Tunnel:
┌────────┐  WiFi   ┌─────────┐
│ iPhone │ ──────▶ │   Mac   │
└────────┘         └─────────┘

With USB Tunnel:
┌────────┐  USB Cable  ┌─────────┐
│ iPhone │ ═══════════▶│   Mac   │
│        │             │         │
│ App    │             │ iproxy  │
│ ↓      │             │   ↓     │
│ talks  │             │ forwards│
│ to     │             │ to      │
│localhost│            │ server  │
│:8000   │             │ :8000   │
└────────┘             └─────────┘
```

The `iproxy` tool creates a tunnel that forwards connections from the iPhone's localhost to the Mac's localhost through the USB cable.

---

## Connection Fallback Logic

The app automatically tries connections in this order:

```swift
1. Try WiFi (your-mac-ip:8000)
   ├─ Success → Use WiFi ✅
   └─ Fail → Try USB

2. Try USB (localhost:8000)
   ├─ Success → Use USB ✅
   └─ Fail → Show error ❌
```

No manual switching needed! Just make sure:
- Server is running
- For WiFi: Same network
- For USB: Cable connected + iproxy running

---

## Multiple iPhones

You can connect multiple iPhones simultaneously:

**iPhone 1 (WiFi):**
- Use actual Mac IP: `10.84.104.88`

**iPhone 2 (USB):**
- Use different port:
  ```bash
  iproxy 8001 8000
  ```
- In app settings: Use port `8001`

---

## Scripts Summary

| Script | Purpose |
|--------|---------|
| `start_server.sh` | Start the Python server |
| `setup_usb.sh` | Install iproxy and start tunnel |
| `fix_firewall.sh` | Fix WiFi connection issues |

---

## Pro Tips

1. **Always use USB for development** - More reliable, no firewall issues
2. **Keep USB tunnel running** - Start it once, leave it
3. **WiFi for demos** - No cable to trip over
4. **Watch the indicator** - Shows "WiFi" or "USB" when connected
5. **USB charges your iPhone** - Bonus!
