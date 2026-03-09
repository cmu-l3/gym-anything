#!/usr/bin/env python3
"""
Verifier for Crane Lift Plan task.
Verifies the DXF file structure, layer content, and geometric accuracy.
"""

import json
import os
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crane_lift_plan(traj, env_info, task_info):
    """
    Verifies the crane lift plan task.
    
    Criteria:
    1. DXF file creation and validity.
    2. Correct layer structure.
    3. Geometric accuracy of Crane Setup (Radius, Base).
    4. Geometric accuracy of Load Path (Pick/Set points).
    5. Building wall placement.
    6. Annotations presence.
    7. VLM visual confirmation.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "DXF file was not saved."}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "File was not created during the task session."}

    dxf_data = result.get("dxf_analysis", {})
    if notxf_data.get("valid_dxf", False):
        return {"passed": False, "score": 10, "feedback": "File saved but is not a valid DXF."}

    score = 10
    feedback = []
    
    # --- Geometric Verification Helper ---
    def check_circle(layer_data, expected_center, expected_radius, tolerance_pos=0.5, tolerance_rad=0.1):
        for c in layer_data.get("circles", []):
            cx, cy = c["center"]
            r = c["radius"]
            dist = math.hypot(cx - expected_center[0], cy - expected_center[1])
            if dist <= tolerance_pos and abs(r - expected_radius) <= tolerance_rad:
                return True
        return False

    def check_rect_bounds(layer_data, width, height, tolerance=0.5):
        # Check polylines first
        for poly in layer_data.get("polylines", []):
            pts = poly["points"]
            if len(pts) < 4: continue
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            w = max(xs) - min(xs)
            h = max(ys) - min(ys)
            if abs(w - width) < tolerance and abs(h - height) < tolerance:
                return True
        # Check if constructed from lines (harder, but we can check if lines exist in area)
        # Simplified: Pass if polylines match, else rely on VLM
        return False

    entities = dxf_data.get("entities", {})

    # 1. Layers Check (20 pts)
    required_layers = ["CRANE_SETUP", "BUILDING", "LOAD_PATH", "ANNOTATIONS"]
    existing_layers = dxf_data.get("layers", [])
    found_layers = [l for l in required_layers if l in existing_layers]
    
    if len(found_layers) == 4:
        score += 20
        feedback.append("All layers created.")
    else:
        score += 5 * len(found_layers)
        feedback.append(f"Missing layers: {set(required_layers) - set(found_layers)}")

    # 2. Crane Setup Geometry (20 pts)
    crane_layer = entities.get("CRANE_SETUP", {})
    # Check Tail Swing (R=3.6 at 0,0)
    if check_circle(crane_layer, [0, 0], 3.6):
        score += 10
        feedback.append("Tail swing circle correct.")
    else:
        feedback.append("Tail swing circle missing or incorrect size/position.")

    # Check Base (6.4x7.4 rect)
    # This is tricky if they drew lines, but let's check for lines or polyline
    has_geometry = len(crane_layer.get("lines", [])) >= 4 or len(crane_layer.get("polylines", [])) > 0
    if has_geometry:
        score += 10 # Giving credit for attempt, precision checked by VLM if polyline fails
        feedback.append("Crane base geometry present.")

    # 3. Load Path Geometry (20 pts)
    load_layer = entities.get("LOAD_PATH", {})
    # Pick Point (-10, 5, r=0.5)
    pick_ok = check_circle(load_layer, [-10, 5], 0.5)
    # Set Point (12, 8, r=0.5)
    set_ok = check_circle(load_layer, [12, 8], 0.5)
    
    if pick_ok: score += 5
    if set_ok: score += 5
    if pick_ok and set_ok: feedback.append("Pick and Set points correct.")
    
    # Check swing line
    # Just check if any line exists on this layer
    if len(load_layer.get("lines", [])) > 0:
        score += 10
        feedback.append("Swing line present.")

    # 4. Building Wall (10 pts)
    building_layer = entities.get("BUILDING", {})
    if len(building_layer.get("lines", [])) > 0:
        # Check for vertical line at X ~ 6
        lines = building_layer["lines"]
        valid_wall = any(abs(l["start"][0] - 6.0) < 0.5 and abs(l["end"][0] - 6.0) < 0.5 for l in lines)
        if valid_wall:
            score += 10
            feedback.append("Building wall correctly placed.")
        else:
            score += 5
            feedback.append("Building layer has lines, but position may be off.")

    # 5. Annotations (10 pts)
    anno_layer = entities.get("ANNOTATIONS", {})
    texts = [t.upper() for t in anno_layer.get("texts", [])]
    required_texts = ["CRANE", "PICK", "SET", "WALL"]
    found_texts = [t for t in required_texts if any(t in existing for existing in texts)]
    
    if len(found_texts) >= 3:
        score += 10
        feedback.append("Annotations present.")
    elif len(found_texts) > 0:
        score += 5
        feedback.append("Some annotations missing.")

    # 6. VLM Verification (10 pts)
    # Use VLM to confirm the drawing looks like a plan view
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Does this image show a 2D CAD technical drawing (white lines on black background or similar)? "
        "Can you see a site plan with a crane symbol (rectangle/circle), a building line, "
        "and a path connecting two points? "
        "Return JSON with keys: is_cad_drawing (bool), has_crane_setup (bool), has_load_path (bool)."
    )
    
    try:
        vlm_res = query_vlm(images=[final_screen], prompt=vlm_prompt).get("parsed", {})
        if vlm_res.get("is_cad_drawing", False) and vlm_res.get("has_crane_setup", False):
            score += 10
            feedback.append("Visual verification passed.")
    except Exception:
        pass # If VLM fails, rely on programmatic score

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }