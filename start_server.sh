#!/bin/bash
# Start the Tiresias edge server

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              TIRESIAS EDGE SERVER                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get Mac's IP address
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
if [ -n "$IP" ]; then
    echo "📍 Your Mac's IP address: $IP"
    echo "   Use this IP in the iOS app settings"
    echo ""
fi

# Change to server directory
cd "$(dirname "$0")/server" || exit 1

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install/update dependencies (skip by default to avoid heavy import delays)
if [[ "$FORCE_INSTALL" == "1" ]]; then
    echo "📦 Installing dependencies (FORCE_INSTALL=1)..."
    pip install -r requirements.txt
else
    echo "📦 Skipping dependency install (set FORCE_INSTALL=1 to install)"
fi

# Firewall check
echo "🔥 Checking firewall configuration..."
PYTHON_PATH=$(which python)

# Check if firewall is enabled
FIREWALL_STATE=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -o "enabled\|disabled")

if [[ "$FIREWALL_STATE" == "enabled" ]]; then
    echo "   Firewall is ENABLED - adding Python exception..."
    
    # Add Python to firewall exceptions
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$PYTHON_PATH" >/dev/null 2>&1
    
    # Allow incoming connections for Python
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$PYTHON_PATH" >/dev/null 2>&1
    
    echo "   ✅ Firewall configured for Python!"
else
    echo "   ✅ Firewall is disabled - no changes needed"
fi

# Start server
echo ""
echo "🚀 Starting server..."
python main.py
