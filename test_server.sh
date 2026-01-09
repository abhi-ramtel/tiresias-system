#!/bin/bash
# Quick test script to verify server is working

echo "🧪 Testing Tiresias Server..."
echo ""

# Test health endpoint
echo "1. Testing health endpoint..."
response=$(curl -s http://localhost:8000/health)
if [[ $response == *"ok"* ]]; then
    echo "   ✅ Health check passed"
else
    echo "   ❌ Health check failed"
    echo "   Response: $response"
    exit 1
fi

# Test root endpoint
echo "2. Testing root endpoint..."
response=$(curl -s http://localhost:8000/)
if [[ $response == *"Tiresias"* ]]; then
    echo "   ✅ Root endpoint passed"
else
    echo "   ❌ Root endpoint failed"
    exit 1
fi

# Test stats endpoint
echo "3. Testing stats endpoint..."
response=$(curl -s http://localhost:8000/stats)
if [[ $response == *"active_connections"* ]]; then
    echo "   ✅ Stats endpoint passed"
else
    echo "   ❌ Stats endpoint failed"
    exit 1
fi

echo ""
echo "✅ All tests passed! Server is ready."
echo ""
echo "📱 Your Mac's IP: $(ipconfig getifaddr en0 2>/dev/null || echo 'Not found')"
echo "   Use this IP in the iOS app"
