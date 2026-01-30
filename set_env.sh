#!/bin/bash
# Run this before launching Xcode to set the SERVER_IP environment variable
# Usage: source set_env.sh && open TiresiasApp/TiresiasApp.xcodeproj

# Get Mac's IP address
export SERVER_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en0 2>/dev/null)

if [ -z "$SERVER_IP" ]; then
    echo "⚠️  Could not detect IP. Using default."
    export SERVER_IP="192.168.1.219"
else
    echo "✅ SERVER_IP set to: $SERVER_IP"
fi

# Optionally write to a plist that iOS can read (for launch args)
defaults write ~/Library/Preferences/com.tiresias.config SERVER_IP "$SERVER_IP"

echo ""
echo "To start the server, run:"
echo "  ./run_server.sh"
echo ""
echo "Or manually:"
echo "  export SERVER_IP=\$(ipconfig getifaddr en0) && cd server && python3.11 main.py"
