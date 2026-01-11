#!/usr/bin/env python3
import cv2
import numpy as np
import os
from ultralytics import YOLO
from typing import List, Dict, Any, Tuple
from enum import Enum
from dataclasses import dataclass


class HazardLevel(Enum):
    CRITICAL = 1    # Immediate danger - must avoid NOW
    HIGH = 2        # Obstacles in path - need to navigate around
    MEDIUM = 3      # Nearby objects to be aware of
    LOW = 4         # Background objects - informational only


# Objects that are inherently dangerous (can move or cause injury)
MOVING_OBJECTS = {
    'person', 'bicycle', 'car', 'motorcycle', 'bus', 'truck', 'train', 'boat',
    'dog', 'cat', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe',
    'bird'
}

# Objects that are static obstacles (trip/collision hazards)
OBSTACLE_OBJECTS = {
    'fire hydrant', 'stop sign', 'parking meter', 'bench', 'chair', 
    'potted plant', 'suitcase', 'backpack', 'umbrella', 'handbag',
    'skateboard', 'surfboard', 'skis', 'snowboard', 'sports ball',
    'bottle', 'cup', 'bowl', 'vase', 'scissors'
}

# Objects that are typically not in walking path (furniture, mounted items)
BACKGROUND_OBJECTS = {
    'traffic light', 'tv', 'laptop', 'mouse', 'remote', 'keyboard',
    'cell phone', 'microwave', 'oven', 'toaster', 'sink', 'refrigerator',
    'book', 'clock', 'teddy bear', 'hair drier', 'toothbrush',
    'apple', 'orange', 'banana', 'sandwich', 'pizza', 'donut', 'cake',
    'fork', 'knife', 'spoon'
}

# Large objects (used for distance estimation)
LARGE_OBJECTS = {'car', 'bus', 'truck', 'train', 'couch', 'bed', 'dining table', 'boat', 'airplane'}


def select_fast_model() -> str:
    override = os.getenv("TIRESIAS_FAST_MODEL")
    if override:
        return override
    if os.getenv("TIRESIAS_USE_YOLOV10", "0") == "1" and os.path.exists("yolov10n.pt"):
        return "yolov10n.pt"
    return "yolov8n.pt"


class YOLODetector:
    def __init__(self, model_path: str = None, confidence_threshold: float = 0.5):
        model_path = model_path or select_fast_model()
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold
        print(f"✅ Fast lane model: {model_path}")
        
    def run_inference(self, image_bytes: bytes):
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if image is None:
            return None, None, (0, 0)
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        result = results[0]
        height, width = image.shape[:2]
        return image, result, (width, height)

    def detections_from_result(self, result) -> List[Dict[str, Any]]:
        detections = []
        for box in result.boxes:
            detections.append({
                "class": result.names[int(box.cls[0])],
                "confidence": float(box.conf[0]),
                "bbox": box.xyxy[0].tolist()
            })
        return detections

    def annotate_result(self, result) -> bytes:
        annotated_image = result.plot()
        _, buffer = cv2.imencode('.jpg', annotated_image)
        return buffer.tobytes()


class NavigationDetector:
    """Enhanced detector for navigation assistance with hazard analysis"""
     
    def __init__(self, model_path: str = "yolov8n.pt", confidence_threshold: float = 0.35):
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold
    
    def analyse_frame(self, image_bytes: bytes) -> Dict[str, Any]:
        """
        Analyse a frame for navigation assistance.
        
        Args:
            image_bytes: JPEG image data
        Returns:
            Dict with detections, navigation summary, and warnings
        """
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return {"error": "Invalid image data", "detections": [], "summary": "Unable to process image"}
        
        height, width = image.shape[:2]
        
        # Run detection
        results = self.model(image, conf=self.confidence_threshold, verbose=False)
        result = results[0]
        
        # Process detections with navigation context
        detections = []
        for box in result.boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            w, h = x2 - x1, y2 - y1
            center_x = x1 + w / 2
            center_y = y1 + h / 2
            
            label = result.names[int(box.cls[0])]
            confidence = float(box.conf[0])
            
            # Determine position
            position = self._get_position(center_x, width)
            
            # Estimate distance based on size
            area = w * h
            image_area = width * height
            size_ratio = area / image_area
            distance_estimate = self._estimate_distance(size_ratio, label)
            
            # Smart hazard classification based on object type + context
            hazard_level = self._classify_hazard(label, distance_estimate, position, size_ratio)
            
            detections.append({
                "label": label,
                "confidence": round(confidence, 2),
                "bbox": [int(x1), int(y1), int(w), int(h)],
                "position": position,
                "hazard_level": hazard_level.name,
                "hazard_priority": hazard_level.value,
                "distance_estimate": distance_estimate
            })
        
        # Sort by hazard priority and distance
        distance_order = ["very close", "close", "medium", "far"]
        detections.sort(key=lambda x: (
            x["hazard_priority"],
            distance_order.index(x["distance_estimate"]) if x["distance_estimate"] in distance_order else 99
        ))
        
        # Generate navigation summary
        summary = self._generate_navigation_summary(detections)
        warnings = self._generate_warnings(detections)
        
        return {
            "detections": detections,
            "count": len(detections),
            "summary": summary,
            "warnings": warnings,
            "image_size": {"width": width, "height": height}
        }
    
    def _get_position(self, center_x: float, image_width: int) -> str:
        """Determine if object is on left, center, or right"""
        third = image_width / 3
        if center_x < third:
            return "left"
        elif center_x < 2 * third:
            return "center"
        else:
            return "right"
    
    def _classify_hazard(self, label: str, distance: str, position: str, size_ratio: float) -> HazardLevel:
        """
        Smart hazard classification based on:
        1. Object type (moving vs static vs background)
        2. Distance (closer = more dangerous)
        3. Position (center = in your path)
        4. Size (larger objects are harder to avoid)
        """
        is_close = distance in ["very close", "close"]
        is_in_path = position == "center"
        is_large = size_ratio > 0.1
        
        # Moving objects (people, vehicles, animals) - always prioritize
        if label in MOVING_OBJECTS:
            if is_close:
                return HazardLevel.CRITICAL
            elif is_in_path or distance == "medium":
                return HazardLevel.HIGH
            else:
                return HazardLevel.MEDIUM
        
        # Known obstacle objects
        if label in OBSTACLE_OBJECTS:
            if is_close and is_in_path:
                return HazardLevel.CRITICAL
            elif is_close or is_in_path:
                return HazardLevel.HIGH
            else:
                return HazardLevel.MEDIUM
        
        # Background objects (usually not in walking path)
        if label in BACKGROUND_OBJECTS:
            # But if it's close and in path, still warn
            if is_close and is_in_path:
                return HazardLevel.HIGH
            else:
                return HazardLevel.LOW
        
        # UNKNOWN OBJECT - use heuristics
        # If we don't know what it is, err on the side of caution
        if is_close and is_in_path:
            return HazardLevel.CRITICAL
        elif is_close or (is_in_path and is_large):
            return HazardLevel.HIGH
        elif is_in_path or is_large:
            return HazardLevel.MEDIUM
        else:
            return HazardLevel.LOW
    
    def _estimate_distance(self, size_ratio: float, label: str) -> str:
        """Estimate distance based on object size ratio"""
        if label in LARGE_OBJECTS:
            if size_ratio > 0.3: return "very close"
            elif size_ratio > 0.15: return "close"
            elif size_ratio > 0.05: return "medium"
            else: return "far"
        else:
            if size_ratio > 0.15: return "very close"
            elif size_ratio > 0.08: return "close"
            elif size_ratio > 0.03: return "medium"
            else: return "far"
    
    def _generate_warnings(self, detections: List[Dict]) -> List[str]:
        """Generate warning messages for hazards"""
        warnings = []
        
        for det in detections:
            if det["hazard_priority"] == 1:  # CRITICAL
                if det["distance_estimate"] in ["very close", "close"]:
                    warnings.append(f"⚠️ {det['label']} {det['distance_estimate']} on your {det['position']}")
        
        return warnings[:3]  # Top 3 warnings
    
    def _generate_navigation_summary(self, detections: List[Dict]) -> str:
        """Generate human-readable navigation summary"""
        if not detections:
            return "Path appears clear. No obstacles detected."
        
        parts = []
        
        # Critical objects
        critical = [d for d in detections if d["hazard_priority"] == 1]
        if critical:
            for det in critical[:2]:
                parts.append(f"{det['label']} {det['distance_estimate']} on your {det['position']}")
        
        # High priority obstacles
        obstacles = [d for d in detections if d["hazard_priority"] == 2]
        if obstacles:
            parts.append(f"{len(obstacles)} obstacle(s) detected")
        
        # Overall count
        if len(detections) > 5:
            parts.append(f"Busy area with {len(detections)} objects")
        
        return ". ".join(parts) if parts else "Environment scanned."
    
# Singleton instances
_detector = None
_nav_detector = None

def get_detector() -> YOLODetector:
    global _detector
    if _detector is None:
        _detector = YOLODetector()
    return _detector

def get_navigation_detector() -> NavigationDetector:
    global _nav_detector
    if _nav_detector is None:
        _nav_detector = NavigationDetector()
    return _nav_detector
