#!/bin/bash
# Setup USB tunneling for iPhone connection
# This allows the iPhone to connect to the Mac server via USB cable

echo "🔌 Tiresias USB Connection Setup"
echo "================================="
echo ""

# Check if iproxy is installed
if ! command -v iproxy &> /dev/null; then
    echo "📦 Installing libimobiledevice (includes iproxy)..."
    echo ""
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew not found!"
        echo ""
        echo "Please install Homebrew first:"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    # Install libimobiledevice
    brew install libimobiledevice
    echo ""
fi

echo "✅ iproxy is installed"
echo ""

# Check if iPhone is connected
echo "🔍 Checking for connected iPhone..."
if idevice_id -l 2>/dev/null | grep -q .; then
    DEVICE_ID=$(idevice_id -l | head -1)
    echo "✅ iPhone found: $DEVICE_ID"
else
    echo "⚠️  No iPhone detected"
    echo ""
    echo "Please:"
    echo "  1. Connect iPhone via USB cable"
    echo "  2. Unlock iPhone"
    echo "  3. Trust this computer if prompted"
    echo "  4. Run this script again"
    exit 1
fi

echo ""
echo "🚀 Starting USB tunnel..."
echo "   Forwarding localhost:8000 -> iPhone -> Mac:8000"
echo ""
echo "Press Ctrl+C to stop"
echo "================================="
echo ""

# Start the tunnel
iproxy 8000 8000
