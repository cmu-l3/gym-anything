#!/usr/bin/env python3
"""
Verifier for Drone Wing Rib task.
Verifies DXF geometry based on pre-calculated analysis from inside the container.
"""

import json
import tempfile
import os
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_drone_wing_rib(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    analysis = result.get("dxf_analysis", {})
    file_created = result.get("file_created_during_task", False)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Created (10 pts)
    if analysis.get("file_exists") and file_created:
        score += 10
        feedback_parts.append("DXF file created.")
    elif analysis.get("file_exists"):
        score += 5
        feedback_parts.append("DXF file exists but timestamp suggests pre-existence.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # Criterion 2: Valid DXF (10 pts)
    if analysis.get("valid_dxf"):
        score += 10
    else:
        return {"passed": False, "score": score, "feedback": "File is not a valid DXF."}

    # Criterion 3: Layer Setup (10 pts)
    layers = analysis.get("layers_found", [])
    has_profile_layer = "PROFILE" in layers
    has_cutouts_layer = "CUTOUTS" in layers
    
    if has_profile_layer and has_cutouts_layer:
        score += 10
        feedback_parts.append("Layers correct.")
    elif has_profile_layer or has_cutouts_layer:
        score += 5
        feedback_parts.append("Partial layer match.")
    else:
        feedback_parts.append("Layers missing.")

    # Criterion 4: Airfoil Shape (30 pts)
    # Checked via vertex count and valid flag from internal analysis
    if analysis.get("profile_valid"):
        score += 20
        feedback_parts.append("Airfoil geometry present.")
        if analysis.get("profile_closed"):
            score += 10
            feedback_parts.append("Profile is closed.")
        else:
            feedback_parts.append("Profile is open (should be closed loop).")
    else:
        feedback_parts.append("Airfoil profile missing or too simple.")

    # Criterion 5: Spar Holes (40 pts)
    # Expected: 
    # 1. (50, 0) r=5 (dia 10)
    # 2. (140, 0) r=3 (dia 6)
    # 3. (95, 0) r=12 (dia 24)
    
    holes_found = analysis.get("holes_found", [])
    matched_holes = 0
    
    # Tolerances
    POS_TOL = 1.0 # mm
    RAD_TOL = 0.5 # mm
    
    # Check Hole 1 (Main Spar)
    h1 = any(math.hypot(h["center"][0]-50, h["center"][1]-0) < POS_TOL and abs(h["radius"]-5) < RAD_TOL for h in holes_found)
    if h1:
        score += 15
        matched_holes += 1
        
    # Check Hole 2 (Rear Spar)
    h2 = any(math.hypot(h["center"][0]-140, h["center"][1]-0) < POS_TOL and abs(h["radius"]-3) < RAD_TOL for h in holes_found)
    if h2:
        score += 15
        matched_holes += 1

    # Check Hole 3 (Lightening)
    h3 = any(math.hypot(h["center"][0]-95, h["center"][1]-0) < POS_TOL and abs(h["radius"]-12) < RAD_TOL for h in holes_found)
    if h3:
        score += 10
        matched_holes += 1
        
    if matched_holes > 0:
        feedback_parts.append(f"Found {matched_holes}/3 correct holes.")
    else:
        feedback_parts.append("No correct spar holes found.")

    # Final result
    # Pass threshold: 70 points
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }