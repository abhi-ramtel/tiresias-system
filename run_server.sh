#!/bin/bash
# Tiresias Server Startup Script
# Automatically detects and exports the Mac's IP address

# Get the IP address from en0 (WiFi) or en1 (Ethernet)
SERVER_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
    echo "❌ Could not detect IP address. Make sure you're connected to WiFi."
    exit 1
fi

# Export for the iOS app to use
export SERVER_IP

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Tiresias Server                                  ║"
echo "╠═══════════════════════════════════════════════════════════╣"
echo "║  Server IP: $SERVER_IP                              "
echo "║  Port: 8000                                                ║"
echo "║                                                            ║"
echo "║  iOS App will connect to: ws://$SERVER_IP:8000     "
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Starting server..."
echo ""

cd "$(dirname "$0")/server"

# Check if Python 3.11 is available (required for PyTorch)
if command -v python3.11 &> /dev/null; then
    python3.11 main.py
elif command -v python3 &> /dev/null; then
    python3 main.py
else
    echo "❌ Python not found. Please install Python 3.11"
    exit 1
fi
