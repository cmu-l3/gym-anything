#!/usr/bin/env python3
"""
Verifier for create_office_layout task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_office_layout(traj, env_info, task_info):
    """
    Verifies the office layout creation task.
    
    Criteria:
    1. FCStd file creation (10 pts)
    2. Room Geometry: 5000x4000 rectangle (30 pts)
    3. Table Geometry: Hexagon at (2500,2000) (30 pts)
    4. Dimension object exists (20 pts)
    5. DXF Export exists (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Fetch Basic Result Metadata
    # ----------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # 2. Fetch Geometry Analysis
    # ----------------------------
    analysis = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/geometry_analysis.json", f.name)
            f.seek(0)
            analysis = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load geometry analysis: {e}")

    # 3. Score Calculation
    # ----------------------------
    
    # Criterion 1: FCStd File Exists (10 pts)
    if task_result.get("fcstd_exists") and task_result.get("fcstd_created_during"):
        score += 10
        feedback.append("File 'office_layout.FCStd' created successfully.")
    elif task_result.get("fcstd_exists"):
        score += 5
        feedback.append("File exists but timestamp is suspect.")
    else:
        feedback.append("File 'office_layout.FCStd' not found.")
        
    # Criterion 2: Room Geometry (30 pts)
    if analysis.get("room_found"):
        score += 30
        dims = analysis.get("room_dims", [0, 0])
        feedback.append(f"Room rectangle found ({int(dims[0])}x{int(dims[1])} mm).")
    else:
        feedback.append("Room rectangle (5000x4000 mm) not found in file.")

    # Criterion 3: Table Geometry (30 pts)
    if analysis.get("table_found"):
        score += 30
        center = analysis.get("table_center", [0, 0])
        feedback.append(f"Hexagonal table found at ({int(center[0])}, {int(center[1])}).")
    else:
        feedback.append("Hexagonal table (Radius 600) at center (2500,2000) not found.")

    # Criterion 4: Dimension Object (20 pts)
    if analysis.get("dimension_found"):
        score += 20
        feedback.append("Dimension object detected.")
    else:
        feedback.append("No dimension object found.")

    # Criterion 5: DXF Export (10 pts)
    if task_result.get("dxf_exists") and task_result.get("dxf_created_during"):
        score += 10
        feedback.append("DXF export created successfully.")
    else:
        feedback.append("DXF export file not found.")

    # 4. VLM Verification (Visual Check for Safety)
    # ---------------------------------------------
    # If programmatic check failed significantly, give VLM a chance to catch "visual only" work
    # OR confirm programmatic success is not a hack (though geometric analysis is robust)
    
    if score < 70:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a FreeCAD task.
        The goal was to draw a rectangle and a hexagon inside it, and add a dimension line.
        
        1. Do you see a rectangle?
        2. Do you see a hexagon inside the rectangle?
        3. Do you see a dimension line/measurement?
        4. Does the interface look like the FreeCAD Draft workbench (grid, 2D tools)?
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_img], prompt=prompt)
            if vlm_res.get("success"):
                # If visually it looks perfect but file analysis failed (maybe didn't save?), 
                # we can grant partial partial credit, but usually we trust the file.
                # Here we just append feedback.
                feedback.append(f"VLM Visual check: {vlm_res.get('parsed', {}).get('summary', 'Analyzed')}")
        except Exception:
            pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }