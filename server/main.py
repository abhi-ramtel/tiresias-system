#!/usr/bin/env python3
"""
Tiresias Edge Server
FastAPI WebSocket server for receiving video frames from iOS app
"""

import uvicorn
import time
from datetime import datetime
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile
from fastapi.responses import JSONResponse, HTMLResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from detection import get_detector, get_navigation_detector

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
        self.latest_frame: bytes = None  # Store latest frame for preview
        self.latest_frame_time: datetime = None
        
    def to_dict(self):
        uptime = (datetime.now() - self.start_time).total_seconds()
        return {
            "total_connections": self.total_connections,
            "active_connections": self.active_connections,
            "total_frames_received": self.total_frames_received,
            "uptime_seconds": int(uptime),
            "has_frame": self.latest_frame is not None
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
            "websocket": "/ws/video",
            "analyse": "/analyse (POST image)",
            "analyse_latest": "/analyse/frame"
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


@app.get("/frame")
async def get_latest_frame():
    """Return the latest received frame as JPEG"""
    if stats.latest_frame is None:
        return Response(content="No frame available", status_code=404)
    return Response(content=stats.latest_frame, media_type="image/jpeg")


@app.post("/analyse")
async def analyse_frame(image: UploadFile = File(...)):
    """
    Analyse a single image for navigation assistance.
    
    Args:
        image: JPEG image file
        
    Returns:
        JSON with detections, navigation summary, and warnings
    """
    try:
        # Read image bytes
        image_bytes = await image.read()
        
        # Get navigation detector
        detector = get_navigation_detector()
        
        # Analyse frame
        result = detector.analyse_frame(image_bytes)
        
        if "error" in result:
            return JSONResponse({"error": result["error"]}, status_code=400)
        
        return JSONResponse({
            "success": True,
            "detections": result["detections"],
            "count": result["count"],
            "summary": result["summary"],
            "warnings": result["warnings"],
            "image_size": result["image_size"]
        })
        
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.get("/analyse/frame")
async def analyse_latest_frame():
    """
    Analyse the latest received frame from the video stream.
    
    Returns:
        JSON with detections, navigation summary, and warnings
    """
    if stats.latest_frame is None:
        return JSONResponse({"error": "No frame available"}, status_code=404)
    
    try:
        detector = get_navigation_detector()
        result = detector.analyse_frame(stats.latest_frame)
        
        if "error" in result:
            return JSONResponse({"error": result["error"]}, status_code=400)
        
        return JSONResponse({
            "success": True,
            "detections": result["detections"],
            "count": result["count"],
            "summary": result["summary"],
            "warnings": result["warnings"],
            "image_size": result["image_size"]
        })
        
    except Exception as e:
        return JSONResponse({"error": str(e)}, status_code=500)


@app.get("/view")
async def view_stream():
    """Simple HTML page to view the live stream"""
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Tiresias Live View</title>
        <style>
            body { 
                background: #1a1a1a; 
                color: white; 
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                margin: 0;
                padding: 20px;
                display: flex;
                flex-direction: column;
                align-items: center;
            }
            h1 { margin-bottom: 10px; }
            #stats { color: #888; margin-bottom: 20px; }
            #frame { 
                max-width: 90vw; 
                max-height: 70vh; 
                border: 2px solid #333;
                border-radius: 8px;
            }
            .no-stream {
                padding: 100px 50px;
                background: #333;
                border-radius: 8px;
                color: #666;
            }
        </style>
    </head>
    <body>
        <h1>📹 Tiresias Live View</h1>
        <div id="stats">Connecting...</div>
        <img id="frame" class="no-stream" alt="Waiting for stream...">
        
        <script>
            const img = document.getElementById('frame');
            const statsDiv = document.getElementById('stats');
            let frameCount = 0;
            let lastUpdate = Date.now();
            
            async function updateFrame() {
                try {
                    const response = await fetch('/frame?' + Date.now());
                    if (response.ok) {
                        const blob = await response.blob();
                        img.src = URL.createObjectURL(blob);
                        img.classList.remove('no-stream');
                        frameCount++;
                    }
                } catch (e) {}
            }
            
            async function updateStats() {
                try {
                    const response = await fetch('/stats');
                    const data = await response.json();
                    const fps = frameCount / ((Date.now() - lastUpdate) / 1000);
                    statsDiv.textContent = `Connections: ${data.active_connections} | Frames: ${data.total_frames_received} | View FPS: ${fps.toFixed(1)}`;
                    frameCount = 0;
                    lastUpdate = Date.now();
                } catch (e) {}
            }
            
            // Update frame every 33ms (~30fps)
            setInterval(updateFrame, 33);
            // Update stats every second
            setInterval(updateStats, 1000);
            updateFrame();
            updateStats();
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html)


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
            message = await websocket.receive()
            
            if "bytes" in message:
                frame_data = message["bytes"]
                stats.total_frames_received += 1
                
                # --- START AI PIPELINE ---
                
                # 1. Get the global detector
                detector = get_detector()
                
                # 2. Process the frame (Detect & Paint)
                # This returns the image with boxes AND the data list
                annotated_frame, detections = detector.process_and_annotate(frame_data)
                
                # 3. Update the global view
                # Now /view will show the boxes!
                stats.latest_frame = annotated_frame
                stats.latest_frame_time = datetime.now()
                
                # --- END AI PIPELINE ---

                # (Optional) Log significant detections
                if len(detections) > 0:
                    # Just print to console for now so you see it working
                    labels = [d['class'] for d in detections]
                    print(f"👀 Saw: {', '.join(labels)}")

                # Performance Stats Update (Keep your existing FPS code here)
                current_time = time.time()
                # ... existing FPS logic ...
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
    print("👁️  Live View: http://0.0.0.0:8000/view")
    print("🎯 Analyse: POST http://0.0.0.0:8000/analyse")
    print("🎯 Analyse Latest: GET http://0.0.0.0:8000/analyse/frame")
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
