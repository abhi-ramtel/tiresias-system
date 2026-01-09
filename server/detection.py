#!/usr/bin/env python3
"""
YOLO Inference Module
Fast object detection using ultralytics YOLO
"""

import cv2
import numpy as np
from PIL import Image
import io
from typing import Optional, List, Dict, Any
from ultralytics import YOLO

class YOLODetector:
    """YOLO-based object detector for real-time inference"""
    
    def __init__(self, model_path: str = "yolov8n.pt", confidence_threshold: float = 0.5):
        """
        Initialize the YOLO detector
        
        Args:
            model_path: Path to YOLO model weights (default: yolov8n for speed)
            confidence_threshold: Minimum confidence for detections
        """
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold
        print(f"✅ YOLO model loaded: {model_path}")
        
    def detect_from_bytes(self, image_bytes: bytes) -> List[Dict[str, Any]]:
        """
        Run detection on JPEG image bytes
        
        Args:
            image_bytes: JPEG image data
            
        Returns:
            List of detection dictionaries with class, confidence, and bbox
        """
        # Convert bytes to numpy array
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return []
            
        return self.detect(image)
        
    def detect(self, image: np.ndarray) -> List[Dict[str, Any]]:
        """
        Run detection on numpy image array
        
        Args:
            image: BGR image as numpy array
            
        Returns:
            List of detection dictionaries
        """
        # Run inference
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        
        detections = []
        for result in results:
            boxes = result.boxes
            for box in boxes:
                detection = {
                    "class": result.names[int(box.cls[0])],
                    "confidence": float(box.conf[0]),
                    "bbox": {
                        "x1": float(box.xyxy[0][0]),
                        "y1": float(box.xyxy[0][1]),
                        "x2": float(box.xyxy[0][2]),
                        "y2": float(box.xyxy[0][3])
                    }
                }
                detections.append(detection)
                
        return detections
        
    def get_class_names(self) -> List[str]:
        """Get list of class names the model can detect"""
        return list(self.model.names.values())


# Singleton instance for global access
_detector: Optional[YOLODetector] = None

def get_detector() -> YOLODetector:
    """Get or create the global YOLO detector instance"""
    global _detector
    if _detector is None:
        _detector = YOLODetector()
    return _detector


def detect_objects(image_bytes: bytes) -> List[Dict[str, Any]]:
    """
    Convenience function to detect objects in image bytes
    
    Args:
        image_bytes: JPEG image data
        
    Returns:
        List of detection dictionaries
    """
    detector = get_detector()
    return detector.detect_from_bytes(image_bytes)


if __name__ == "__main__":
    # Test the detector
    print("Testing YOLO detector...")
    detector = YOLODetector()
    print(f"Available classes: {len(detector.get_class_names())}")
    print(f"First 10 classes: {detector.get_class_names()[:10]}")
