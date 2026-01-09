#!/bin/bash
# Automatic Firewall Fix for Tiresias Server

echo "🔥 Tiresias Firewall Fix"
echo "========================"
echo ""

# Find Python path
PYTHON_PATH=$(which python3)
echo "📍 Found Python at: $PYTHON_PATH"
echo ""

# Check if firewall is enabled
FIREWALL_STATE=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -o "enabled\|disabled")

if [[ "$FIREWALL_STATE" == "enabled" ]]; then
    echo "🔥 Firewall is ENABLED - adding Python exception..."
    echo ""
    
    # Add Python to firewall exceptions
    echo "1. Adding Python to firewall allowlist..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$PYTHON_PATH" 2>/dev/null
    
    echo "2. Allowing incoming connections for Python..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$PYTHON_PATH" 2>/dev/null
    
    echo "3. Reloading firewall..."
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null
    
    echo ""
    echo "✅ Firewall configured!"
else
    echo "✅ Firewall is disabled - no changes needed"
fi

echo ""
echo "🧪 Testing connection..."
echo ""

# Get IP
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
echo "📍 Your Mac's IP: $IP"
echo ""

# Test localhost
echo "Testing localhost..."
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "  ✅ Localhost OK"
else
    echo "  ❌ Localhost failed - is server running?"
    echo "     Run: ./start_server.sh"
    exit 1
fi

# Test network IP
echo "Testing network IP ($IP)..."
if curl -s http://$IP:8000/health > /dev/null 2>&1; then
    echo "  ✅ Network IP OK"
else
    echo "  ❌ Network IP failed"
    echo ""
    echo "Other possible issues:"
    echo "  - Router has AP Isolation enabled"
    echo "  - VPN is active"
    echo "  - Different network than iPhone"
    exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📱 Next steps:"
echo "1. On iPhone Safari, open: http://$IP:8000/health"
echo "2. You should see: {\"status\":\"ok\"}"
echo "3. Then try connecting from the app"
echo ""
echo "If iPhone Safari can't reach it:"
echo "  - Check Settings → Privacy → Local Network"
echo "  - Make sure iPhone is on same WiFi network"
echo "  - Try disabling VPN"
