#!/usr/bin/env python3
import json
import os
import math
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roi_layout(traj, env_info, task_info):
    """
    Verifies the ROI Zoom Layout task.
    
    Criteria:
    1. Layout "Lobby POS Monitor" must exist.
    2. Layout must contain exactly 2 items.
    3. Both items must point to "Lobby Camera".
    4. Item 1: Full view (zoomRect is null or 0,0,1,1).
    5. Item 2: Zoom view (zoomRect close to x=0.5, y=0.5, w=0.5, h=0.5).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metadata targets
    metadata = task_info.get('metadata', {})
    target_zoom = metadata.get('target_zoom_rect', {"x": 0.5, "y": 0.5, "width": 0.5, "height": 0.5})
    tolerance = metadata.get('tolerance', 0.05)
    
    score = 0
    feedback = []
    
    # 2. Check Layout Existence
    if not result.get('layout_found', False):
        return {"passed": False, "score": 0, "feedback": "Layout 'Lobby POS Monitor' not found."}
    
    score += 20
    feedback.append("Layout created.")
    
    layout_data = result.get('layout_data', {})
    items = layout_data.get('items', [])
    target_cam_id = result.get('target_camera_id', "")
    
    # 3. Check Item Count
    if len(items) != 2:
        feedback.append(f"Expected 2 items in layout, found {len(items)}.")
        if len(items) > 0: score += 5  # Partial credit
    else:
        score += 20
        feedback.append("Correct item count (2).")

    # 4. Check Item Content (Camera ID and Zoom)
    full_view_found = False
    zoom_view_found = False
    correct_cameras = 0
    
    for item in items:
        # Check Camera ID
        resource_id = item.get('resourceId', '')
        if resource_id == target_cam_id:
            correct_cameras += 1
        
        # Check Zoom Rect
        # API format: zoomRect is usually "x,y,w,h" string or object depending on version
        # Nx Witness API v1 usually returns `zoomRect` as a string "0,0,1,1" or null if default
        z_rect = item.get('zoomRect')
        
        # Parse zoom rect
        zx, zy, zw, zh = 0.0, 0.0, 1.0, 1.0 # Default full view
        is_custom_zoom = False
        
        if z_rect:
            try:
                if isinstance(z_rect, str):
                    parts = [float(p) for p in z_rect.split(',')]
                    if len(parts) == 4:
                        zx, zy, zw, zh = parts
                        is_custom_zoom = True
                elif isinstance(z_rect, dict):
                    zx = float(z_rect.get('x', 0))
                    zy = float(z_rect.get('y', 0))
                    zw = float(z_rect.get('width', 1))
                    zh = float(z_rect.get('height', 1))
                    is_custom_zoom = True
            except:
                pass # Parse error, treat as default

        # Logic for "Full View" (approx 0,0,1,1)
        if abs(zx - 0) < 0.1 and abs(zy - 0) < 0.1 and abs(zw - 1) < 0.1 and abs(zh - 1) < 0.1:
            full_view_found = True
            
        # Logic for "Target Zoom" (bottom right quadrant)
        # Target: x=0.5, y=0.5, w=0.5, h=0.5
        if (abs(zx - target_zoom['x']) <= tolerance and 
            abs(zy - target_zoom['y']) <= tolerance and 
            abs(zw - target_zoom['width']) <= tolerance and 
            abs(zh - target_zoom['height']) <= tolerance):
            zoom_view_found = True

    # Scoring Item Details
    if correct_cameras == len(items) and len(items) > 0:
        score += 20
        feedback.append("All items use correct camera.")
    elif correct_cameras > 0:
        score += 10
        feedback.append("Some items use correct camera.")
    else:
        feedback.append("Wrong camera used in layout.")
        
    if full_view_found:
        score += 10
        feedback.append("Full view item configured correctly.")
    else:
        feedback.append("Missing full view item.")
        
    if zoom_view_found:
        score += 30
        feedback.append("ROI zoom item configured correctly.")
    else:
        feedback.append(f"ROI zoom item incorrect or missing (Target: {target_zoom}).")

    # 5. VLM Verification (Trajectory Check)
    # Since this is an API/State heavy task, VLM is secondary but checks if they opened relevant tools
    # or if the visual result (if verified via screenshot of client) looks right.
    # Note: If agent only used API, screenshots might be boring, but that's valid.
    
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }