#!/usr/bin/env python3
"""
Path Guidance Module
Real-time path detection and navigation guidance for walking assistance
"""

import cv2
import numpy as np
from typing import List, Dict, Any, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class GuidanceDirection(Enum):
    """Navigation guidance directions"""
    CLEAR = "path_clear"
    MOVE_LEFT = "move_left"
    MOVE_RIGHT = "move_right"
    MOVE_SLIGHTLY_LEFT = "slight_left"
    MOVE_SLIGHTLY_RIGHT = "slight_right"
    STOP = "stop"
    SLOW_DOWN = "slow_down"
    

@dataclass
class PathZone:
    """Represents a zone in the path analysis grid"""
    x_start: int
    x_end: int
    y_start: int
    y_end: int
    obstacle_score: float  # 0.0 = clear, 1.0 = blocked
    obstacles: List[Dict[str, Any]]


@dataclass
class GuidanceResult:
    """Result of path analysis with guidance instruction"""
    direction: GuidanceDirection
    instruction: str
    confidence: float
    path_clear_percentage: float
    obstacles_detected: List[Dict[str, Any]]
    zones: List[Dict[str, Any]]
    annotated_frame: Optional[bytes] = None


class PathGuidanceEngine:
    """
    Real-time path guidance engine that analyzes camera frames
    to detect obstacles and provide walking navigation instructions.
    """
    
    # Object classes that are obstacles for walking
    OBSTACLE_CLASSES = {
        'person', 'bicycle', 'car', 'motorcycle', 'bus', 'truck',
        'dog', 'cat', 'horse', 'cow', 'sheep',
        'chair', 'couch', 'potted plant', 'bed', 'dining table',
        'bench', 'backpack', 'umbrella', 'handbag', 'suitcase',
        'fire hydrant', 'stop sign', 'parking meter', 'traffic light',
        'skateboard', 'surfboard', 'sports ball'
    }
    
    # High priority obstacles (immediate danger)
    HIGH_PRIORITY_OBSTACLES = {
        'person', 'car', 'bicycle', 'motorcycle', 'bus', 'truck', 'dog'
    }
    
    def __init__(
        self,
        grid_cols: int = 5,  # Divide width into 5 zones (left, mid-left, center, mid-right, right)
        grid_rows: int = 3,  # Divide height into 3 zones (far, mid, near)
        near_zone_weight: float = 3.0,  # Weight for obstacles in near zone
        mid_zone_weight: float = 1.5,
        far_zone_weight: float = 0.5,
        obstacle_threshold: float = 0.3,  # Zone blocked if score > threshold
    ):
        self.grid_cols = grid_cols
        self.grid_rows = grid_rows
        self.near_zone_weight = near_zone_weight
        self.mid_zone_weight = mid_zone_weight
        self.far_zone_weight = far_zone_weight
        self.obstacle_threshold = obstacle_threshold
        
        # Zone weights by row (bottom = near, top = far)
        self.row_weights = [far_zone_weight, mid_zone_weight, near_zone_weight]
        
        # Smoothing for stable guidance
        self._last_directions = []
        self._direction_history_size = 3
        
    def analyze_frame(
        self,
        image_bytes: bytes,
        detections: List[Dict[str, Any]],
        annotate: bool = True
    ) -> GuidanceResult:
        """
        Analyze a frame and provide path guidance
        
        Args:
            image_bytes: Raw JPEG image data
            detections: List of YOLO detections with class, confidence, bbox
            annotate: Whether to draw guidance overlay on frame
            
        Returns:
            GuidanceResult with direction, instruction, and optional annotated frame
        """
        # Decode image
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return GuidanceResult(
                direction=GuidanceDirection.STOP,
                instruction="Cannot process camera feed",
                confidence=0.0,
                path_clear_percentage=0.0,
                obstacles_detected=[],
                zones=[]
            )
        
        height, width = image.shape[:2]
        
        # Filter obstacles
        obstacles = self._filter_obstacles(detections)
        
        # Create zone grid
        zones = self._create_zone_grid(width, height)
        
        # Assign obstacles to zones
        self._assign_obstacles_to_zones(zones, obstacles, width, height)
        
        # Calculate zone scores
        zone_data = self._calculate_zone_scores(zones)
        
        # Determine guidance direction
        direction, confidence = self._determine_direction(zone_data, width)
        
        # Generate human-readable instruction
        instruction = self._generate_instruction(direction, obstacles, zone_data)
        
        # Calculate path clear percentage
        path_clear = self._calculate_path_clear_percentage(zone_data)
        
        # Annotate frame if requested
        annotated_frame = None
        if annotate:
            annotated = self._draw_guidance_overlay(image, zone_data, direction, obstacles)
            _, buffer = cv2.imencode('.jpg', annotated, [cv2.IMWRITE_JPEG_QUALITY, 85])
            annotated_frame = buffer.tobytes()
        
        return GuidanceResult(
            direction=direction,
            instruction=instruction,
            confidence=confidence,
            path_clear_percentage=path_clear,
            obstacles_detected=obstacles,
            zones=zone_data,
            annotated_frame=annotated_frame
        )
    
    def _filter_obstacles(self, detections: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter detections to only include obstacle classes"""
        obstacles = []
        for det in detections:
            obj_class = det.get('class', '').lower()
            if obj_class in self.OBSTACLE_CLASSES:
                det['is_high_priority'] = obj_class in self.HIGH_PRIORITY_OBSTACLES
                obstacles.append(det)
        return obstacles
    
    def _create_zone_grid(self, width: int, height: int) -> List[List[PathZone]]:
        """Create grid of path zones"""
        zones = []
        zone_width = width // self.grid_cols
        zone_height = height // self.grid_rows
        
        for row in range(self.grid_rows):
            row_zones = []
            for col in range(self.grid_cols):
                zone = PathZone(
                    x_start=col * zone_width,
                    x_end=(col + 1) * zone_width if col < self.grid_cols - 1 else width,
                    y_start=row * zone_height,
                    y_end=(row + 1) * zone_height if row < self.grid_rows - 1 else height,
                    obstacle_score=0.0,
                    obstacles=[]
                )
                row_zones.append(zone)
            zones.append(row_zones)
        return zones
    
    def _assign_obstacles_to_zones(
        self,
        zones: List[List[PathZone]],
        obstacles: List[Dict[str, Any]],
        width: int,
        height: int
    ):
        """Assign each obstacle to zones it overlaps"""
        for obstacle in obstacles:
            bbox = obstacle.get('bbox', [])
            if len(bbox) != 4:
                continue
                
            x1, y1, x2, y2 = [int(v) for v in bbox]
            center_x = (x1 + x2) // 2
            center_y = (y1 + y2) // 2
            
            # Calculate obstacle size relative to frame
            obstacle_area = (x2 - x1) * (y2 - y1)
            frame_area = width * height
            obstacle['relative_size'] = obstacle_area / frame_area
            
            # Find which zones this obstacle overlaps
            for row_idx, row in enumerate(zones):
                for col_idx, zone in enumerate(row):
                    # Check if obstacle center or bbox overlaps zone
                    if self._bbox_overlaps_zone(x1, y1, x2, y2, zone):
                        zone.obstacles.append(obstacle)
    
    def _bbox_overlaps_zone(
        self,
        x1: int, y1: int, x2: int, y2: int,
        zone: PathZone
    ) -> bool:
        """Check if bounding box overlaps with zone"""
        return not (x2 < zone.x_start or x1 > zone.x_end or
                   y2 < zone.y_start or y1 > zone.y_end)
    
    def _calculate_zone_scores(self, zones: List[List[PathZone]]) -> List[Dict[str, Any]]:
        """Calculate obstacle scores for each zone"""
        zone_data = []
        
        for row_idx, row in enumerate(zones):
            row_weight = self.row_weights[row_idx] if row_idx < len(self.row_weights) else 1.0
            
            for col_idx, zone in enumerate(row):
                # Base score from number of obstacles
                base_score = 0.0
                
                for obstacle in zone.obstacles:
                    # Weight by obstacle priority and size
                    priority_weight = 2.0 if obstacle.get('is_high_priority', False) else 1.0
                    size_weight = min(obstacle.get('relative_size', 0.1) * 10, 2.0)
                    confidence = obstacle.get('confidence', 0.5)
                    
                    base_score += priority_weight * size_weight * confidence
                
                # Apply row weight (near obstacles weighted more)
                final_score = min(base_score * row_weight, 1.0)
                zone.obstacle_score = final_score
                
                zone_data.append({
                    'row': row_idx,
                    'col': col_idx,
                    'x_start': zone.x_start,
                    'x_end': zone.x_end,
                    'y_start': zone.y_start,
                    'y_end': zone.y_end,
                    'score': final_score,
                    'blocked': final_score > self.obstacle_threshold,
                    'obstacle_count': len(zone.obstacles)
                })
        
        return zone_data
    
    def _determine_direction(
        self,
        zone_data: List[Dict[str, Any]],
        width: int
    ) -> Tuple[GuidanceDirection, float]:
        """Determine the best direction based on zone analysis"""
        
        # Group zones by column
        col_scores = {}
        for zone in zone_data:
            col = zone['col']
            if col not in col_scores:
                col_scores[col] = []
            col_scores[col].append(zone['score'])
        
        # Calculate average score per column
        col_avg = {col: sum(scores) / len(scores) for col, scores in col_scores.items()}
        
        # Identify center column(s)
        center_col = self.grid_cols // 2
        left_cols = list(range(0, center_col))
        right_cols = list(range(center_col + 1, self.grid_cols))
        
        # Check if center path is clear
        center_score = col_avg.get(center_col, 0.0)
        left_avg = sum(col_avg.get(c, 0) for c in left_cols) / len(left_cols) if left_cols else 0
        right_avg = sum(col_avg.get(c, 0) for c in right_cols) / len(right_cols) if right_cols else 0
        
        # Check immediate danger (bottom row, center columns)
        bottom_center_blocked = any(
            z['blocked'] and z['row'] == self.grid_rows - 1 and 
            center_col - 1 <= z['col'] <= center_col + 1
            for z in zone_data
        )
        
        # Decision logic
        if bottom_center_blocked:
            # Immediate obstacle ahead - need to move
            if left_avg < right_avg:
                direction = GuidanceDirection.MOVE_LEFT
                confidence = 1.0 - left_avg
            else:
                direction = GuidanceDirection.MOVE_RIGHT
                confidence = 1.0 - right_avg
        elif center_score > self.obstacle_threshold:
            # Path ahead is blocked but not immediate
            if left_avg < right_avg - 0.1:
                direction = GuidanceDirection.MOVE_SLIGHTLY_LEFT
                confidence = 0.8
            elif right_avg < left_avg - 0.1:
                direction = GuidanceDirection.MOVE_SLIGHTLY_RIGHT
                confidence = 0.8
            else:
                direction = GuidanceDirection.SLOW_DOWN
                confidence = 0.7
        elif center_score < 0.1 and left_avg < 0.3 and right_avg < 0.3:
            direction = GuidanceDirection.CLEAR
            confidence = 1.0 - max(center_score, left_avg, right_avg)
        else:
            direction = GuidanceDirection.CLEAR
            confidence = 1.0 - center_score
        
        # Smooth direction changes
        direction = self._smooth_direction(direction)
        
        return direction, confidence
    
    def _smooth_direction(self, direction: GuidanceDirection) -> GuidanceDirection:
        """Smooth direction changes to avoid jitter"""
        self._last_directions.append(direction)
        if len(self._last_directions) > self._direction_history_size:
            self._last_directions.pop(0)
        
        # If same direction appears most often, use it
        if len(self._last_directions) >= 2:
            from collections import Counter
            most_common = Counter(self._last_directions).most_common(1)[0][0]
            return most_common
        
        return direction
    
    def _generate_instruction(
        self,
        direction: GuidanceDirection,
        obstacles: List[Dict[str, Any]],
        zone_data: List[Dict[str, Any]]
    ) -> str:
        """Generate human-readable navigation instruction"""
        
        # Get primary obstacle if any
        primary_obstacle = None
        if obstacles:
            # Find closest obstacle (bottom-most in frame)
            sorted_obs = sorted(obstacles, key=lambda o: o.get('bbox', [0,0,0,0])[3], reverse=True)
            primary_obstacle = sorted_obs[0].get('class', 'obstacle')
        
        instructions = {
            GuidanceDirection.CLEAR: "Path clear. Keep going straight.",
            GuidanceDirection.MOVE_LEFT: f"Move left. {primary_obstacle or 'Obstacle'} ahead on right.",
            GuidanceDirection.MOVE_RIGHT: f"Move right. {primary_obstacle or 'Obstacle'} ahead on left.",
            GuidanceDirection.MOVE_SLIGHTLY_LEFT: "Slight left. Path clearer on left side.",
            GuidanceDirection.MOVE_SLIGHTLY_RIGHT: "Slight right. Path clearer on right side.",
            GuidanceDirection.STOP: f"Stop. {primary_obstacle or 'Obstacle'} directly ahead.",
            GuidanceDirection.SLOW_DOWN: f"Slow down. {primary_obstacle or 'Obstacle'} approaching.",
        }
        
        return instructions.get(direction, "Processing...")
    
    def _calculate_path_clear_percentage(self, zone_data: List[Dict[str, Any]]) -> float:
        """Calculate what percentage of the path is clear"""
        # Focus on center columns for walking path
        center_col = self.grid_cols // 2
        center_zones = [z for z in zone_data if center_col - 1 <= z['col'] <= center_col + 1]
        
        if not center_zones:
            return 0.0
        
        clear_zones = sum(1 for z in center_zones if not z['blocked'])
        return (clear_zones / len(center_zones)) * 100
    
    def _draw_guidance_overlay(
        self,
        image: np.ndarray,
        zone_data: List[Dict[str, Any]],
        direction: GuidanceDirection,
        obstacles: List[Dict[str, Any]]
    ) -> np.ndarray:
        """Draw guidance visualization on frame"""
        overlay = image.copy()
        height, width = image.shape[:2]
        
        # Draw zone grid with color coding
        for zone in zone_data:
            # Color based on obstruction (green=clear, yellow=caution, red=blocked)
            if zone['blocked']:
                color = (0, 0, 200)  # Red
                alpha = 0.4
            elif zone['score'] > 0.1:
                color = (0, 200, 255)  # Yellow
                alpha = 0.2
            else:
                color = (0, 200, 0)  # Green
                alpha = 0.1
            
            # Draw zone rectangle
            cv2.rectangle(
                overlay,
                (zone['x_start'], zone['y_start']),
                (zone['x_end'], zone['y_end']),
                color,
                -1
            )
        
        # Blend overlay
        cv2.addWeighted(overlay, 0.3, image, 0.7, 0, image)
        
        # Draw zone borders
        for zone in zone_data:
            cv2.rectangle(
                image,
                (zone['x_start'], zone['y_start']),
                (zone['x_end'], zone['y_end']),
                (100, 100, 100),
                1
            )
        
        # Draw direction arrow
        arrow_color = (255, 255, 255)
        arrow_center = (width // 2, height - 100)
        arrow_length = 80
        
        if direction == GuidanceDirection.MOVE_LEFT:
            end_point = (arrow_center[0] - arrow_length, arrow_center[1])
            cv2.arrowedLine(image, arrow_center, end_point, arrow_color, 4, tipLength=0.3)
        elif direction == GuidanceDirection.MOVE_RIGHT:
            end_point = (arrow_center[0] + arrow_length, arrow_center[1])
            cv2.arrowedLine(image, arrow_center, end_point, arrow_color, 4, tipLength=0.3)
        elif direction == GuidanceDirection.MOVE_SLIGHTLY_LEFT:
            end_point = (arrow_center[0] - arrow_length//2, arrow_center[1] - arrow_length//2)
            cv2.arrowedLine(image, arrow_center, end_point, arrow_color, 4, tipLength=0.3)
        elif direction == GuidanceDirection.MOVE_SLIGHTLY_RIGHT:
            end_point = (arrow_center[0] + arrow_length//2, arrow_center[1] - arrow_length//2)
            cv2.arrowedLine(image, arrow_center, end_point, arrow_color, 4, tipLength=0.3)
        elif direction == GuidanceDirection.CLEAR:
            end_point = (arrow_center[0], arrow_center[1] - arrow_length)
            cv2.arrowedLine(image, arrow_center, end_point, (0, 255, 0), 4, tipLength=0.3)
        elif direction == GuidanceDirection.STOP:
            cv2.circle(image, arrow_center, 40, (0, 0, 255), -1)
            cv2.putText(image, "STOP", (arrow_center[0]-30, arrow_center[1]+10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        
        # Draw obstacle boxes
        for obstacle in obstacles:
            bbox = obstacle.get('bbox', [])
            if len(bbox) == 4:
                x1, y1, x2, y2 = [int(v) for v in bbox]
                color = (0, 0, 255) if obstacle.get('is_high_priority') else (0, 165, 255)
                cv2.rectangle(image, (x1, y1), (x2, y2), color, 2)
                
                label = f"{obstacle.get('class', '')} {obstacle.get('confidence', 0):.0%}"
                cv2.putText(image, label, (x1, y1 - 10),
                           cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
        
        # Draw instruction text
        instruction = self._generate_instruction(direction, obstacles, zone_data)
        
        # Background for text
        text_bg_y = 30
        cv2.rectangle(image, (10, 5), (width - 10, 60), (0, 0, 0), -1)
        
        # Direction-based text color
        text_color = {
            GuidanceDirection.CLEAR: (0, 255, 0),
            GuidanceDirection.MOVE_LEFT: (0, 200, 255),
            GuidanceDirection.MOVE_RIGHT: (0, 200, 255),
            GuidanceDirection.MOVE_SLIGHTLY_LEFT: (0, 255, 255),
            GuidanceDirection.MOVE_SLIGHTLY_RIGHT: (0, 255, 255),
            GuidanceDirection.STOP: (0, 0, 255),
            GuidanceDirection.SLOW_DOWN: (0, 165, 255),
        }.get(direction, (255, 255, 255))
        
        cv2.putText(image, instruction, (20, 40),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, text_color, 2)
        
        return image


# Singleton instance
_guidance_engine = None

def get_guidance_engine() -> PathGuidanceEngine:
    """Get or create the global path guidance engine"""
    global _guidance_engine
    if _guidance_engine is None:
        _guidance_engine = PathGuidanceEngine()
    return _guidance_engine
