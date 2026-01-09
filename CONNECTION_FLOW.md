# Connection Flow Diagram

## Automatic WiFi → USB Fallback

```
User Taps "Connect"
         ↓
    ┌────────────────────────────────────────┐
    │  STEP 1: Try WiFi Connection           │
    │  Testing: http://YOUR_IP:8000     │
    └────────────────────────────────────────┘
         ↓
    [Success?]
         ├─ YES → ┌──────────────────────────┐
         │        │ ✅ Connected via WiFi    │
         │        │ Show: "WiFi" indicator   │
         │        │ Stream frames via WiFi   │
         │        └──────────────────────────┘
         │
         └─ NO → ┌─────────────────────────────┐
                 │  STEP 2: Try USB Fallback   │
                 │  Testing: http://localhost   │
                 └─────────────────────────────┘
                         ↓
                    [Success?]
                         ├─ YES → ┌──────────────────────────┐
                         │        │ ✅ Connected via USB     │
                         │        │ Show: "USB" indicator    │
                         │        │ Stream frames via USB    │
                         │        └──────────────────────────┘
                         │
                         └─ NO → ┌─────────────────────────────┐
                                 │ ❌ Connection Failed        │
                                 │ Show error with details:    │
                                 │ - WiFi failed               │
                                 │ - USB failed                │
                                 │ - Troubleshooting steps     │
                                 └─────────────────────────────┘
```

## Network Architecture

### WiFi Mode (Wireless)
```
┌──────────────────┐                    ┌─────────────────┐
│                  │   WiFi Network     │                 │
│  iPhone          │◄──────────────────►│  Mac            │
│  TiresiasApp     │                    │  Python Server  │
│                  │    YOUR_MAC_IP_    │  Port 8000      │
│  - Captures      │    :8000           │                 │
│  - Compresses    │                    │  - Receives     │
│  - Streams       │                    │  - Processes    │
│                  │                    │  - Responds     │
└──────────────────┘                    └─────────────────┘
        📱                                      💻
```

### USB Mode (Wired Fallback)
```
┌──────────────────┐                    ┌─────────────────┐
│                  │   USB Cable        │                 │
│  iPhone          │═══════════════════►│  Mac            │
│  TiresiasApp     │                    │                 │
│                  │                    │  ┌────────────┐ │
│  localhost:8000  │                    │  │  iproxy    │ │
│     ↓            │                    │  │  forwards  │ │
│  "Connect to     │                    │  │  port 8000 │ │
│   localhost"     │                    │  └─────┬──────┘ │
│                  │                    │        ↓        │
│                  │                    │  Python Server  │
│                  │                    │  Port 8000      │
└──────────────────┘                    └─────────────────┘
        📱══════════════════════════════►      💻
            Lightning/USB-C Cable
```

## Connection State Machine

```
┌──────────────┐
│ Disconnected │
└──────┬───────┘
       │ User taps "Connect"
       ↓
┌──────────────┐
│ Connecting   │
│ (WiFi Test)  │
└──────┬───────┘
       │
       ├─[WiFi Success]──► ┌────────────┐
       │                   │ Connected  │
       │                   │ (WiFi)     │
       │                   └─────┬──────┘
       │                         │
       ├─[WiFi Failed]───► ┌─────────────┐
       │                   │ Connecting  │
       │                   │ (USB Test)  │
       │                   └──────┬──────┘
       │                          │
       │                          ├─[USB Success]──► ┌────────────┐
       │                          │                   │ Connected  │
       │                          │                   │ (USB)      │
       │                          │                   └─────┬──────┘
       │                          │                         │
       │                          └─[USB Failed]───► ┌──────────┐
       │                                             │  Error   │
       └─────────────────────────────────────────────┤  State   │
                                                     └──────────┘
```

## What The User Sees

### Attempting Connection
```
┌─────────────────────────────────┐
│ 🟠 Connecting...                │  ← Status
│                                 │
│ [Camera View]                   │
│                                 │
│     [●]         [○]             │  ← Buttons disabled
│   Connect      Stream           │
└─────────────────────────────────┘
```

### Connected via WiFi
```
┌─────────────────────────────────┐
│ 🟢 Connected    📡 WiFi         │  ← Status + Method
│                                 │
│ [Camera View]                   │
│                                 │
│ FPS: 30  Frames: 1234  25ms    │  ← Stats
│                                 │
│     [●]         [▶]             │
│  Disconnect    Stream           │
└─────────────────────────────────┘
```

### Connected via USB
```
┌─────────────────────────────────┐
│ 🟢 Connected    🔌 USB          │  ← Status + Method
│                                 │
│ [Camera View]                   │
│                                 │
│ FPS: 30  Frames: 1234  15ms    │  ← Stats (lower latency!)
│                                 │
│     [●]         [▶]             │
│  Disconnect    Stream           │
└─────────────────────────────────┘
```

### Connection Failed
```
┌─────────────────────────────────┐
│      ⚠️ Connection Error         │
│                                 │
│  Cannot reach server.           │
│                                 │
│  WiFi: Failed to connect        │
│  USB: Failed to connect         │
│                                 │
│  Make sure:                     │
│  1. Server is running           │
│  2. For WiFi: Same network      │
│  3. For USB: iproxy running     │
│                                 │
│     [Cancel]      [Retry]       │
└─────────────────────────────────┘
```

## Reconnection Logic

```
Connection Lost
      ↓
┌─────────────────┐
│ Reconnecting... │
│ Attempt 1/5     │
└────────┬────────┘
         │
         ├─[Success]──► Back to Connected
         │
         ├─[Failed]───► Wait 2 seconds
         │              ↓
         │         ┌─────────────────┐
         │         │ Reconnecting... │
         │         │ Attempt 2/5     │
         │         └────────┬────────┘
         │                  │
         │                  └─ (repeat until 5 attempts)
         │
         └─[5 Failures]──► ┌──────────────┐
                           │ Disconnected │
                           │ Show error   │
                           └──────────────┘
```

## Benefits of Each Method

### WiFi
- ✅ No cable needed
- ✅ Freedom of movement
- ✅ Good for demos
- ❌ Depends on network
- ❌ Firewall can block
- ❌ ~25-50ms latency

### USB
- ✅ Always works (no firewall)
- ✅ Lower latency (~15-25ms)
- ✅ Charges iPhone
- ✅ More bandwidth
- ✅ Reliable for development
- ❌ Cable required
- ❌ Limited mobility
