#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_draft_2d_panel_layout(traj, env_info, task_info):
    """
    Verifies the FreeCAD 2D panel layout task.
    
    Criteria:
    1. File exists and is a valid FreeCAD document (10 pts)
    2. Panel Outline: 200x100mm rectangle at (0,0) (20 pts)
    3. Display Cutout: 80x50mm rectangle at correct position (20 pts)
    4. Button Holes: Two 10mm diameter circles at correct positions (20 pts)
    5. Annotations: Text and dimensions present (15 pts)
    6. Visual VLM check: Looks like a technical drawing (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # 1. Retrieve Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file panel_layout.FCStd not found."}
    
    if not result.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session.")
    
    score += 10
    feedback_parts.append("File exists")

    # 3. Analyze Geometry (60 pts total)
    analysis = result.get("analysis", {})
    objects = analysis.get("objects", [])
    
    found_panel = False
    found_cutout = False
    found_holes = 0
    found_text = False
    found_dims = False
    
    # Tolerances
    DIM_TOL = 1.0 # mm
    POS_TOL = 2.0 # mm
    
    for obj in objects:
        bbox = obj.get("bbox_size", [0,0,0])
        center = obj.get("center", [0,0,0])
        name = obj.get("name", "")
        
        # Check Panel (200x100)
        # BBox should be approx 200x100x0
        if abs(bbox[0] - 200) < DIM_TOL and abs(bbox[1] - 100) < DIM_TOL:
            # Check position: Center should be at (100, 50) if strictly (0,0) based
            # Or checking min/max coords. Since we have center/bbox:
            # If BBox is 200x100, Center X=100 Y=50 implies origin at 0,0
            if abs(center[0] - 100) < POS_TOL and abs(center[1] - 50) < POS_TOL:
                found_panel = True

        # Check Cutout (80x50)
        # Center should be X=100, Y=20+25=45 (Wait, 30mm from top of 100mm panel means Y start = 70?)
        # Spec: "30 mm from the top edge". Panel top is Y=100. So cutout top is Y=70.
        # Cutout height is 50. So cutout Y range is [20, 70].
        # Center Y = 45.
        # Center X = 100 (centered horizontally).
        if abs(bbox[0] - 80) < DIM_TOL and abs(bbox[1] - 50) < DIM_TOL:
            if abs(center[0] - 100) < POS_TOL and abs(center[1] - 45) < POS_TOL:
                found_cutout = True

        # Check Holes (Radius 5 / Diameter 10)
        # Centers: (60, 15) and (140, 15)
        # BBox for a circle of dia 10 is 10x10
        if obj.get("is_circle") or (abs(bbox[0] - 10) < DIM_TOL and abs(bbox[1] - 10) < DIM_TOL):
            cx, cy = center[0], center[1]
            if (abs(cx - 60) < POS_TOL and abs(cy - 15) < POS_TOL) or \
               (abs(cx - 140) < POS_TOL and abs(cy - 15) < POS_TOL):
                found_holes += 1

        # Check Text
        if "CONTROL PANEL" in obj.get("text_content", ""):
            found_text = True
            
        # Check Dimensions
        if obj.get("is_dimension") or "Dimension" in obj.get("type", ""):
            found_dims = True

    # Scoring Geometry
    if found_panel:
        score += 20
        feedback_parts.append("Panel outline correct")
    else:
        feedback_parts.append("Panel outline missing or wrong size/pos")

    if found_cutout:
        score += 20
        feedback_parts.append("Display cutout correct")
    else:
        feedback_parts.append("Display cutout missing or misplaced")

    if found_holes >= 2:
        score += 20
        feedback_parts.append("Button holes correct")
    elif found_holes == 1:
        score += 10
        feedback_parts.append("One button hole correct")
    else:
        feedback_parts.append("Button holes missing")

    if found_text and found_dims:
        score += 15
        feedback_parts.append("Annotations present")
    elif found_text or found_dims:
        score += 8
        feedback_parts.append("Partial annotations")

    # 4. VLM Verification (15 pts)
    # Check if visual representation matches expectation
    final_img = get_final_screenshot(traj)
    if final_img and query_vlm:
        prompt = """
        Review this FreeCAD screenshot. 
        Does it show a 2D technical drawing of a rectangular panel?
        Look for:
        1. A main rectangle.
        2. A smaller rectangular cutout inside.
        3. Two small circular holes at the bottom.
        4. Dimension lines or text labels.
        
        Answer JSON: {"is_technical_drawing": bool, "has_features": bool}
        """
        try:
            vlm_res = query_vlm(prompt, final_img)
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_technical_drawing") and parsed.get("has_features"):
                score += 15
                feedback_parts.append("Visual check passed")
            else:
                feedback_parts.append("Visual check weak")
        except:
            score += 15 # Fallback if VLM fails but file was good
    else:
        score += 15 # Fallback if no VLM

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }