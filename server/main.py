#!/usr/bin/env python3
"""
Tiresias Edge Server
FastAPI WebSocket server for receiving video frames from iOS app
"""

import uvicorn
import asyncio
import time
from datetime import datetime
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Tiresias Edge Server",
    description="Video streaming server for visual AI assistance",
    version="2.0.0"
)

# Add CORS middleware for potential web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global stats
class ServerStats:
    def __init__(self):
        self.total_connections = 0
        self.active_connections = 0
        self.total_frames_received = 0
        self.start_time = datetime.now()
        
    def to_dict(self):
        uptime = (datetime.now() - self.start_time).total_seconds()
        return {
            "total_connections": self.total_connections,
            "active_connections": self.active_connections,
            "total_frames_received": self.total_frames_received,
            "uptime_seconds": int(uptime)
        }

stats = ServerStats()


@app.get("/")
async def root():
    """Root endpoint with server info"""
    return JSONResponse({
        "status": "online",
        "service": "Tiresias Edge Server",
        "version": "2.0.0",
        "endpoints": {
            "health": "/health",
            "stats": "/stats",
            "websocket": "/ws/video"
        }
    })


@app.get("/health")
async def health():
    """Health check endpoint for connection testing"""
    return JSONResponse({
        "status": "ok",
        "timestamp": datetime.now().isoformat()
    })


@app.get("/stats")
async def get_stats():
    """Server statistics endpoint"""
    return JSONResponse(stats.to_dict())


@app.websocket("/ws/video")
async def video_stream(websocket: WebSocket):
    """
    WebSocket endpoint for video frame streaming
    Receives binary JPEG frames from iOS app
    """
    await websocket.accept()
    
    stats.total_connections += 1
    stats.active_connections += 1
    
    client_info = f"{websocket.client.host}:{websocket.client.port}" if websocket.client else "unknown"
    print(f"🟢 Client Connected: {client_info}")
    print(f"   Active connections: {stats.active_connections}")
    
    frame_count = 0
    start_time = time.time()
    last_fps_update = start_time
    fps_frame_count = 0
    
    try:
        while True:
            # Receive message (can be text or binary)
            message = await websocket.receive()
            
            if "bytes" in message:
                # Binary frame data (JPEG image)
                frame_data = message["bytes"]
                frame_count += 1
                fps_frame_count += 1
                stats.total_frames_received += 1
                
                # Calculate and display FPS every second
                current_time = time.time()
                if current_time - last_fps_update >= 1.0:
                    fps = fps_frame_count / (current_time - last_fps_update)
                    print(f"📹 Receiving: {fps:.1f} FPS | Frame #{frame_count} | Size: {len(frame_data):,} bytes")
                    fps_frame_count = 0
                    last_fps_update = current_time
                
                # TODO: Process frame here
                # - Run YOLO detection
                # - Run LLM analysis
                # - Send results back to client
                
            elif "text" in message:
                # Text message (commands, etc.)
                text_data = message["text"]
                print(f"📨 Text message: {text_data}")
                
                # Echo back for testing
                await websocket.send_text(f"Received: {text_data}")
                
    except WebSocketDisconnect:
        elapsed = time.time() - start_time
        avg_fps = frame_count / elapsed if elapsed > 0 else 0
        print(f"🔴 Client Disconnected: {client_info}")
        print(f"   Session stats: {frame_count} frames in {elapsed:.1f}s ({avg_fps:.1f} avg FPS)")
        
    except Exception as e:
        print(f"❌ Error: {type(e).__name__}: {e}")
        
    finally:
        stats.active_connections -= 1
        print(f"   Active connections: {stats.active_connections}")


def main():
    """Main entry point"""
    print("=" * 60)
    print("🚀 Tiresias Edge Server v2.0")
    print("=" * 60)
    print("📡 Server: http://0.0.0.0:8000")
    print("🔌 WebSocket: ws://0.0.0.0:8000/ws/video")
    print("❤️  Health: http://0.0.0.0:8000/health")
    print("📊 Stats: http://0.0.0.0:8000/stats")
    print("=" * 60)
    print("📱 Connect from iOS using your Mac's IP address")
    print("   Find IP: ipconfig getifaddr en0")
    print("=" * 60)
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )


if __name__ == "__main__":
    main()
