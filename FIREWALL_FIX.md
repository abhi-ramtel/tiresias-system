# 🔥 FIREWALL FIX - Cannot Reach Server

## Problem
iPhone can't connect to Mac server at `10.84.104.88:8000`

**Error:** "Cannot reach the server at MACIP:8000"

## ✅ Solution Options

### Option 1: Allow Python Through Firewall (RECOMMENDED)

1. **Open System Settings**
   - Click Apple menu  → System Settings
   
2. **Go to Network Settings**
   - Click "Network" in the sidebar
   - Click "Firewall" (you may need to scroll down)
   
3. **Click "Options..."**
   
4. **Add Python**
   - Click the "+" button
   - Navigate to: `/usr/bin/python3` or wherever Python is installed
   - Or find the running Python process:
     ```bash
     which python3
     ```
   
5. **Allow Incoming Connections**
   - Make sure the Python entry is set to "Allow incoming connections"
   
6. **Click OK**

### Option 2: Temporarily Disable Firewall (FOR TESTING)

⚠️ **WARNING:** This reduces security. Only for testing!

```bash
# Disable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off

# Test your app...

# Re-enable firewall when done
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

### Option 3: Allow Port 8000 Specifically

Create a firewall rule for port 8000:

```bash
# Allow TCP connections on port 8000
echo "rdr pass on lo0 inet proto tcp from any to any port 8000 -> 127.0.0.1 port 8000" | sudo pfctl -ef -
```

### Option 4: Use Different Server Command (EASIEST)

The server is already configured correctly (`0.0.0.0:8000`), but let's add firewall exception.

Add this to your startup script:

```bash
# Allow Python to accept incoming connections
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add $(which python3)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp $(which python3)
```

---

## 🧪 Test After Applying Fix

### 1. From Your Mac Terminal:
```bash
curl http://10.84.104.88:8000/health
```
Should return: `{"status":"ok",...}`

### 2. From iPhone Safari:
Open Safari on your iPhone and go to:
```
http://10.84.104.88:8000/health
```

If you see `{"status":"ok"}` - the firewall is fixed! ✅

If you still see "Cannot Connect" - try the next step.

---

## 🔍 Additional Debugging

### Check if Mac and iPhone are on same WiFi:

**On Mac:**
```bash
ipconfig getifaddr en0
networksetup -getairportnetwork en0
```

**On iPhone:**
- Settings → WiFi → Check network name

They MUST be on the same network!

### Check for VPN:
- Disable any VPN on Mac or iPhone
- Corporate networks may block local connections

### Restart Network Services:
```bash
sudo ifconfig en0 down
sudo ifconfig en0 up
```

---

## ✅ Quick Fix Script

I'll create a script to automatically allow Python through the firewall:

```bash
./fix_firewall.sh
```

This will:
1. Find your Python installation
2. Add it to firewall exceptions
3. Allow incoming connections
4. Test the connection

---

## Still Not Working?

Try these:

1. **Check Router Settings**
   - Some routers block device-to-device communication
   - Look for "AP Isolation" or "Client Isolation" - should be OFF

2. **Use USB Connection Instead**
   - iOS can connect via USB tunnel
   - Run: `iproxy 8000 8000`
   - In app, use IP: `localhost` or `127.0.0.1`

3. **Check iPhone Settings**
   - Settings → Privacy & Security → Local Network
   - Make sure TiresiasApp is allowed

---

## 🎯 What Should Work After Fix

1. iPhone Safari can open `http://10.84.104.88:8000/health`
2. TiresiasApp can connect (green "Connected" status)
3. Server shows: `🟢 Client Connected`
4. Frames stream successfully
