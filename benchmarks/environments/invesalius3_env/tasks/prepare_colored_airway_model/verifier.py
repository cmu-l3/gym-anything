#!/usr/bin/env python3
"""
Verifier for prepare_colored_airway_model task.

Scoring Criteria (100 pts total):
1. Project Saved (20 pts): Valid .inv3 file created during task.
2. Air Threshold (30 pts): At least one mask has max_HU <= -100 (targeting air/sinuses).
   - If max_HU is > -100 (e.g., bone or soft tissue), this fails.
3. Surface Generated (20 pts): Project contains at least one 3D surface.
4. Color is Blue (30 pts): Surface color property has Blue > Red and Blue > Green.

Pass Threshold: 80 points (Must get Threshold and Color correct essentially).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_colored_airway_model(traj, env_info, task_info):
    """
    Verify the airway segmentation and coloring task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Load File Analysis Result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {e}"
        }

    # Criterion 1: Project Saved (20 pts)
    if result.get("file_exists") and result.get("valid_project"):
        if result.get("file_created_during_task"):
            score += 20
            feedback_parts.append("Project saved successfully")
        else:
            # File exists but old timestamp?
            score += 5
            feedback_parts.append("Project file exists but timestamp is old (did you save?)")
    else:
        feedback_parts.append("Project file not found or invalid")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Air Threshold (30 pts)
    # Check if any mask targets air (max HU <= -100)
    masks = result.get("masks", [])
    air_mask_found = False
    
    for m in masks:
        # Air is typically -1000 to -200. Anything with max > -50 is likely soft tissue or bone.
        # We set strict limit at -100 to ensure they didn't just pick "Soft Tissue" preset (-700 to 225).
        if m["max_hu"] <= -100:
            air_mask_found = True
            feedback_parts.append(f"Air mask found ({m['min_hu']} to {m['max_hu']} HU)")
            break
            
    if air_mask_found:
        score += 30
    else:
        if masks:
            feedback_parts.append(f"Wrong threshold used (Max HU: {masks[0].get('max_hu')}). Need AIR threshold (< -100 HU).")
        else:
            feedback_parts.append("No segmentation masks found")

    # Criterion 3: Surface Generated (20 pts)
    surfaces = result.get("surfaces", [])
    if len(surfaces) > 0:
        score += 20
        feedback_parts.append("3D Surface generated")
    else:
        feedback_parts.append("No 3D surface found in project")

    # Criterion 4: Color is Blue (30 pts)
    # InVesalius color is [R, G, B] floats 0.0-1.0
    color_correct = False
    for s in surfaces:
        color = s.get("color", [1, 1, 1])
        if len(color) == 3:
            r, g, b = color
            # Logic: Blue must be the dominant channel
            if b > r and b > g:
                color_correct = True
                break
    
    if color_correct:
        score += 30
        feedback_parts.append("Surface color set to Blue")
    elif len(surfaces) > 0:
        feedback_parts.append("Surface color is not Blue")

    # Final VLM Sanity Check (Optional but recommended for robust visual verification)
    # Only if we are borderline passing or want to confirm visual state
    if score >= 70:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_res = query_vlm(
                image=final_screenshot,
                prompt="Does this screen show a 3D medical reconstruction of a head/skull where the model color is BLUE? Answer YES or NO."
            )
            if vlm_res.get("success") and "YES" in vlm_res.get("response", "").upper():
                feedback_parts.append("(Visual confirmation passed)")
            else:
                feedback_parts.append("(Visual confirmation ambiguous)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "masks": masks,
            "surfaces": surfaces
        }
    }