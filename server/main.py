#!/usr/bin/env python3
"""
Tiresias Edge Server
FastAPI WebSocket server for receiving video frames from iOS app
"""

import uvicorn
import time
import asyncio
import json
import numpy as np
from collections import deque
from typing import Optional
from datetime import datetime
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, File, UploadFile
from fastapi.responses import JSONResponse, HTMLResponse, Response
from fastapi.middleware.cors import CORSMiddleware
from detection import get_detector, get_navigation_detector, MOVING_OBJECTS, OBSTACLE_OBJECTS
import httpx

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
        self.last_gps: Optional[dict] = None
        
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

FRAME_MAGIC = b"TSF1"
FAST_LANE_FPS = 12
SLOW_LANE_INTERVAL_S = 1.0
CRITICAL_DISTANCE_M = 2.0
RING_BUFFER_SECONDS = 5
RING_BUFFER_FPS = 15
RING_BUFFER_SIZE = RING_BUFFER_SECONDS * RING_BUFFER_FPS

frame_buffer = deque(maxlen=RING_BUFFER_SIZE)

def parse_frame_message(payload: bytes):
    if len(payload) >= 2 and payload[0:2] == b"\xff\xd8":
        return payload, None
    if len(payload) < 16 or payload[0:4] != FRAME_MAGIC:
        return None, None

    image_len = int.from_bytes(payload[4:8], "little")
    depth_len = int.from_bytes(payload[8:12], "little")
    depth_width = int.from_bytes(payload[12:14], "little")
    depth_height = int.from_bytes(payload[14:16], "little")

    expected_len = 16 + image_len + depth_len
    if image_len <= 0 or len(payload) < expected_len:
        return None, None

    image_bytes = payload[16:16 + image_len]
    depth_bytes = payload[16 + image_len:16 + image_len + depth_len] if depth_len > 0 else None
    depth_meta = None
    if depth_bytes and depth_width > 0 and depth_height > 0:
        depth_meta = {
            "width": depth_width,
            "height": depth_height,
            "data": depth_bytes
        }
    return image_bytes, depth_meta

def attach_depth_to_detections(detections, depth_meta, image_size):
    if not depth_meta or not detections:
        return
    img_w, img_h = image_size
    if img_w <= 0 or img_h <= 0:
        return

    depth_w = depth_meta["width"]
    depth_h = depth_meta["height"]
    depth = np.frombuffer(depth_meta["data"], dtype=np.uint16)
    if depth.size != depth_w * depth_h:
        return
    depth = depth.reshape((depth_h, depth_w))

    scale_x = depth_w / img_w
    scale_y = depth_h / img_h

    for det in detections:
        x1, y1, x2, y2 = det.get("bbox", [0, 0, 0, 0])
        x1 = max(0, min(img_w - 1, int(x1)))
        x2 = max(0, min(img_w, int(x2)))
        y1 = max(0, min(img_h - 1, int(y1)))
        y2 = max(0, min(img_h, int(y2)))
        if x2 <= x1 or y2 <= y1:
            continue

        dx1 = max(0, min(depth_w - 1, int(x1 * scale_x)))
        dx2 = max(0, min(depth_w, int(x2 * scale_x)))
        dy1 = max(0, min(depth_h - 1, int(y1 * scale_y)))
        dy2 = max(0, min(depth_h, int(y2 * scale_y)))
        if dx2 <= dx1 or dy2 <= dy1:
            continue

        region = depth[dy1:dy2, dx1:dx2].ravel()
        region = region[region > 0]
        if region.size == 0:
            continue

        median_mm = float(np.median(region))
        det["distance_m"] = round(median_mm / 1000.0, 2)

def classify_fast_alert(detections, image_size):
    if not detections:
        return None
    img_w, img_h = image_size
    if img_w <= 0 or img_h <= 0:
        return None

    best = None
    for det in detections:
        label = det["class"]
        if label not in MOVING_OBJECTS and label not in OBSTACLE_OBJECTS:
            continue
        x1, y1, x2, y2 = det["bbox"]
        area_ratio = max(0.0, ((x2 - x1) * (y2 - y1)) / float(img_w * img_h))
        distance_m = det.get("distance_m")
        if distance_m is not None:
            if distance_m <= CRITICAL_DISTANCE_M:
                level = "CRITICAL"
            elif distance_m <= 4.0:
                level = "HIGH"
            else:
                level = "MEDIUM"
        else:
            if area_ratio > 0.2:
                level = "CRITICAL"
            elif area_ratio > 0.08:
                level = "HIGH"
            else:
                level = "MEDIUM"

        if best is None or level == "CRITICAL":
            best = (level, label, det.get("distance_m"))
            if level == "CRITICAL":
                break

    if not best:
        return None

    level, label, distance_m = best
    distance_text = f"{distance_m}m" if distance_m is not None else "nearby"
    return {
        "type": "alert",
        "level": level,
        "text": f"{label} {distance_text}",
        "timestamp": datetime.now().isoformat()
    }

_geocode_cache = {}

async def reverse_geocode(lat: float, lon: float) -> str:
    if not lat or not lon:
        return "Unknown location"
    if str(lat) == "0" and str(lon) == "0":
        return "Unknown location"
    if not bool(int(os.getenv("TIRESIAS_GEOCODE", "0"))):
        return "Unknown location"
    key = (round(lat, 4), round(lon, 4))
    if key in _geocode_cache:
        return _geocode_cache[key]
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            response = await client.get(
                "https://nominatim.openstreetmap.org/reverse",
                params={"format": "json", "lat": lat, "lon": lon},
                headers={"User-Agent": "Tiresias/1.0"}
            )
            if response.status_code != 200:
                return "Unknown location"
            data = response.json()
            value = data.get("display_name", "Unknown location")
            _geocode_cache[key] = value
            return value
    except Exception:
        return "Unknown location"


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
            
            // Update frame every 66ms (~15fps)
            setInterval(updateFrame, 66);
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
    
    fast_queue: asyncio.Queue = asyncio.Queue(maxsize=2)
    latest_frame: Optional[bytes] = None
    stop_event = asyncio.Event()

    async def fast_lane_worker():
        detector = get_detector()
        last_fast = 0.0
        last_view = 0.0
        last_alert_time = {"CRITICAL": 0.0, "HIGH": 0.0, "MEDIUM": 0.0}
        while not stop_event.is_set():
            frame_data, depth_meta = await fast_queue.get()
            now = time.time()
            if now - last_fast < 1.0 / FAST_LANE_FPS:
                continue
            image, result, image_size = detector.run_inference(frame_data)
            if result is None:
                continue
            detections = detector.detections_from_result(result)
            attach_depth_to_detections(detections, depth_meta, image_size)
            
            if now - last_view >= 0.3:
                stats.latest_frame = detector.annotate_result(result)
                stats.latest_frame_time = datetime.now()
                last_view = now
            
            alert = classify_fast_alert(detections, image_size)
            if alert:
                level = alert["level"]
                cooldown = 1.5 if level == "CRITICAL" else 2.5 if level == "HIGH" else 3.5
                if now - last_alert_time.get(level, 0.0) < cooldown:
                    last_fast = now
                    continue
                try:
                    await websocket.send_text(json.dumps(alert))
                    last_alert_time[level] = now
                except Exception:
                    stop_event.set()
                    break
            last_fast = now

    async def slow_lane_worker():
        detector = get_navigation_detector()
        last_run = 0.0
        while not stop_event.is_set():
            await asyncio.sleep(0.05)
            now = time.time()
            if now - last_run < SLOW_LANE_INTERVAL_S:
                continue
            if latest_frame is None:
                continue
            result = detector.analyse_frame(latest_frame)
            if "error" not in result:
                gps = stats.last_gps or {}
                location_text = ""
                if gps:
                    location_text = await reverse_geocode(gps.get("lat", 0.0), gps.get("lon", 0.0))
                action = result.get("action", "CLEAR")
                payload = {
                    "type": "analysis",
                    "summary": result.get("summary", ""),
                    "warnings": result.get("warnings", []),
                    "location": location_text,
                    "action": action,
                    "path": result.get("path", ""),
                    "nearby_obstacles": result.get("nearby_obstacles", []),
                    "timestamp": datetime.now().isoformat()
                }
                try:
                    await websocket.send_text(json.dumps(payload))
                except Exception:
                    stop_event.set()
                    break
            last_run = now

    fast_task = asyncio.create_task(fast_lane_worker())
    slow_task = asyncio.create_task(slow_lane_worker())
    
    try:
        while True:
            message = await websocket.receive()
            
            if "bytes" in message:
                raw_payload = message["bytes"]
                frame_data, depth_meta = parse_frame_message(raw_payload)
                if frame_data is None:
                    continue
                stats.total_frames_received += 1
                
                if fast_queue.full():
                    try:
                        fast_queue.get_nowait()
                    except asyncio.QueueEmpty:
                        pass
                fast_queue.put_nowait((frame_data, depth_meta))

                latest_frame = frame_data

                frame_buffer.append({
                    "timestamp": datetime.now().isoformat(),
                    "frame": frame_data,
                    "depth": depth_meta
                })

                # Performance Stats Update (Keep your existing FPS code here)
                current_time = time.time()
                frame_count += 1
                fps_frame_count += 1
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
                try:
                    data = json.loads(text_data)
                except json.JSONDecodeError:
                    data = {"type": "raw", "value": text_data}

                if data.get("type") == "gps":
                    stats.last_gps = {
                        "lat": data.get("lat", 0.0),
                        "lon": data.get("lon", 0.0),
                        "timestamp": datetime.now().isoformat()
                    }
                elif data.get("type") == "analyze_now":
                    if frame_buffer:
                        latest_frame = frame_buffer[-1]["frame"]
                else:
                    print(f"📨 Text message: {text_data}")
                
    except WebSocketDisconnect:
        elapsed = time.time() - start_time
        avg_fps = frame_count / elapsed if elapsed > 0 else 0
        print(f"🔴 Client Disconnected: {client_info}")
        print(f"   Session stats: {frame_count} frames in {elapsed:.1f}s ({avg_fps:.1f} avg FPS)")
        
    except Exception as e:
        print(f"❌ Error: {type(e).__name__}: {e}")
        
    finally:
        stop_event.set()
        fast_task.cancel()
        slow_task.cancel()
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
