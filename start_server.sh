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

# Install/update dependencies
echo "📦 Installing dependencies..."
pip install -q -r requirements.txt

# Start server
echo ""
python main.py
