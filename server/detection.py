#!/usr/bin/env python3
import cv2
import numpy as np
from ultralytics import YOLO
from typing import List, Dict, Any, Tuple

class YOLODetector:
    def __init__(self, model_path: str = "yolov8n.pt", confidence_threshold: float = 0.5):
        # Auto-detect Apple Silicon (MPS)
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold
        print(f"✅ YOLO initialized. Device: {self.model.device}")
        
    def process_and_annotate(self, image_bytes: bytes) -> Tuple[bytes, List[Dict[str, Any]], Tuple[int, int]]:
        """
        Detects objects and returns:
        1. JPEG bytes of the image with boxes drawn on it.
        2. List of detection data (for logic).
        """
        # 1. Decode Bytes -> Numpy Image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return image_bytes, [], (0, 0)

        # 2. Run Inference
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        result = results[0] # We only have 1 frame

        # 3. Generate "Robot Vision" Image
        # plot() draws the boxes, labels, and confidence scores
        annotated_image = result.plot()

        # 4. Extract Data (for safety logic later)
        detections = []
        for box in result.boxes:
            detections.append({
                "class": result.names[int(box.cls[0])],
                "confidence": float(box.conf[0]),
                "bbox": box.xyxy[0].tolist()
            })

        # 5. Encode back to JPEG
        _, buffer = cv2.imencode('.jpg', annotated_image)
        height, width = image.shape[:2]
        return buffer.tobytes(), detections, (width, height)

# Singleton logic (keep existing)
_detector = None
def get_detector() -> YOLODetector:
    global _detector
    if _detector is None:
        _detector = YOLODetector()
    return _detector
