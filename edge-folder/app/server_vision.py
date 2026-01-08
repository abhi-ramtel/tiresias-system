# TCP/Socket Handler
# server_vision.py
import uvicorn
from fastapi import FastAPI, WebSocket
import cv2
import numpy as np
import asyncio

app = FastAPI()

@app.websocket("/ws/video")
async def video_stream(websocket: WebSocket):
    await websocket.accept()
    print("🟢 iPhone Connected: Ready to receive video.")
    
    try:
        while True:
            # Receive binary data (the JPEG image)
            data = await websocket.receive_bytes()
            
            # Convert bytes to numpy array
            nparr = np.frombuffer(data, np.uint8)
            
            # Decode JPEG to Image Frame
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            # (Optional) Display for debugging - remove in production!
            if frame is not None:
                cv2.imshow("Tiresias - iPhone Feed", frame)
                if cv2.waitKey(1) & 0xFF == ord('q'):
                    break
                    
    except Exception as e:
        print(f"🔴 Connection Closed: {e}")
    finally:
        cv2.destroyAllWindows()

if __name__ == "__main__":
    # Listen on all interfaces so the USB tunnel catches it
    uvicorn.run(app, host="0.0.0.0", port=8000)