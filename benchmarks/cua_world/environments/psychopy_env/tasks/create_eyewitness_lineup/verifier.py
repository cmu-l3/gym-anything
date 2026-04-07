#!/usr/bin/env python3
"""
Verifier for Eyewitness Lineup Task.

Evaluates:
1. Experiment Structure (Routines exist)
2. Lineup Composition (6 images present)
3. Grid Layout (2x3 arrangement, no overlaps)
4. Mouse Interaction (Restricted to valid clicks on images)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_eyewitness_lineup(traj, env_info, task_info):
    """Verify the eyewitness lineup experiment creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/eyewitness_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []
    
    # 1. Basic File Checks (10 pts)
    if result.get("file_exists") and result.get("valid_xml"):
        score += 10
        feedback.append("Experiment file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Experiment file not found or invalid."}

    # 2. Structure Checks (20 pts)
    routines = [r.lower() for r in result.get("routines", [])]
    has_encoding = any("encoding" in r for r in routines)
    has_delay = any("delay" in r for r in routines)
    has_lineup = any("lineup" in r for r in routines)
    
    if has_encoding and has_delay and has_lineup:
        score += 20
        feedback.append("All three routines (Encoding, Delay, Lineup) found.")
    elif has_lineup:
        score += 10
        feedback.append("Lineup routine found, but others missing.")
    else:
        feedback.append("Critical 'Lineup' routine missing.")

    # 3. Lineup Content (20 pts)
    img_count = result.get("lineup_image_count", 0)
    if img_count == 6:
        score += 20
        feedback.append("Lineup contains exactly 6 images.")
    elif img_count >= 6:
        score += 10
        feedback.append(f"Lineup contains {img_count} images (expected 6).")
    else:
        feedback.append(f"Lineup contains only {img_count} images (expected 6).")

    # 4. Grid Layout Analysis (25 pts)
    unique_x = result.get("unique_x_coords", 0)
    unique_y = result.get("unique_y_coords", 0)
    has_overlaps = result.get("has_overlaps", False)
    
    # A 2x3 grid means 3 columns (3 unique X) and 2 rows (2 unique Y)
    # Or rotated: 2 cols (2 unique X) and 3 rows (3 unique Y)
    is_grid = (unique_x >= 3 and unique_y >= 2) or (unique_x >= 2 and unique_y >= 3)
    
    if is_grid and not has_overlaps:
        score += 25
        feedback.append(f"Valid grid layout detected ({unique_x} cols x {unique_y} rows coordinates).")
    elif is_grid:
        score += 15
        feedback.append("Grid coordinates detected, but image overlap detected.")
    else:
        feedback.append(f"Grid layout not detected (found {unique_x} unique X, {unique_y} unique Y positions).")

    # 5. Mouse Interaction (25 pts)
    # Must click on images, and force end on valid click
    clickable_count = result.get("mouse_clickable_count", 0)
    valid_click = result.get("mouse_valid_click", False)
    
    if clickable_count >= 6 and valid_click:
        score += 25
        feedback.append("Mouse correctly configured for valid clicks on all 6 faces.")
    elif clickable_count >= 6:
        score += 15
        feedback.append("Mouse clickable objects set, but 'End Routine' not set to 'Valid Click'.")
    elif valid_click:
        score += 10
        feedback.append("Mouse ends on valid click, but clickable objects list is incomplete/missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }