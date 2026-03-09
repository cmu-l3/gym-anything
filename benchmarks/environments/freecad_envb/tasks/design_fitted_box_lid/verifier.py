#!/usr/bin/env python3
"""
Verifier for design_fitted_box_lid task.

Verifies:
1. File creation and validity.
2. Presence of exactly two solid bodies.
3. Geometric properties of the Box (Volume ~15.5k mm3, Dims ~60x40x30).
4. Geometric properties of the Lid (Volume ~15.6k mm3, Dims ~60x40x7).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_fitted_box_lid(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Target values
    # Box: 60x40x30 outer, 2mm wall. Vol ~ 15,552
    # Lid: 60x40x4 plate + 56x36x3 lip. Vol ~ 15,648
    TARGET_BOX_VOL = metadata.get('box_volume_target', 15552)
    TARGET_LID_VOL = metadata.get('lid_volume_target', 15648)
    TOLERANCE = metadata.get('volume_tolerance_percent', 10) / 100.0

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    score += 10
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp invalid")

    # 3. Analyze Geometry
    geo = result.get("geometry_analysis", {})
    bodies = geo.get("bodies", [])
    num_bodies = len(bodies)

    if num_bodies == 2:
        score += 20
        feedback_parts.append("Correctly found 2 bodies")
    elif num_bodies > 0:
        score += 10
        feedback_parts.append(f"Found {num_bodies} bodies (expected 2)")
    else:
        feedback_parts.append("No solid bodies found in file")

    # Identify Box and Lid based on volume/dimensions
    box_found = False
    lid_found = False
    
    for body in bodies:
        vol = body.get("volume", 0)
        dims = body.get("dims", [0,0,0]) # Sorted: [min, mid, max]
        
        # Check Box
        # Box dims should be close to 30, 40, 60
        # Volume should be around 15552
        if (abs(dims[2] - 60) < 2 and abs(dims[0] - 30) < 2) or \
           (abs(vol - TARGET_BOX_VOL) / TARGET_BOX_VOL < TOLERANCE):
            box_found = True
            # Box scoring
            if abs(dims[2] - 60) < 1.0 and abs(dims[1] - 40) < 1.0 and abs(dims[0] - 30) < 1.0:
                score += 10 # Correct outer dims
            if abs(vol - TARGET_BOX_VOL) / TARGET_BOX_VOL < TOLERANCE:
                score += 15 # Correct shelling/thickness
                feedback_parts.append(f"Box geometry correct (Vol: {vol:.0f})")
            else:
                feedback_parts.append(f"Box volume incorrect ({vol:.0f} vs {TARGET_BOX_VOL})")
            continue

        # Check Lid
        # Lid dims: 60x40x7 (4mm plate + 3mm lip) -> Max dim 60, Min dim ~7
        # Volume should be around 15648
        if (abs(dims[2] - 60) < 2 and abs(dims[0] - 7) < 2) or \
           (abs(vol - TARGET_LID_VOL) / TARGET_LID_VOL < TOLERANCE):
            lid_found = True
            # Lid scoring
            if abs(dims[2] - 60) < 1.0 and abs(dims[1] - 40) < 1.0:
                 score += 10 # Correct plate dims
            if abs(vol - TARGET_LID_VOL) / TARGET_LID_VOL < TOLERANCE:
                score += 15 # Correct lip/protrusion features
                feedback_parts.append(f"Lid geometry correct (Vol: {vol:.0f})")
            else:
                feedback_parts.append(f"Lid volume incorrect ({vol:.0f} vs {TARGET_LID_VOL})")
            continue

    if box_found and lid_found:
        feedback_parts.append("Both parts identified")
    elif not box_found:
        feedback_parts.append("Box part not identified")
    elif not lid_found:
        feedback_parts.append("Lid part not identified")

    # 4. VLM Verification (Trajectory)
    # Ensure work was actually done in UI (not just Python script paste)
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Review these screenshots of a FreeCAD session. "
            "Does the user appear to be modeling a box and a lid? "
            "Look for: 1. A rectangular box shape. 2. A hollowing/shelling operation. 3. A separate lid or plate object. "
            "Respond 'YES' if the workflow looks relevant, 'NO' if unrelated."
        )
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success') and "YES" in vlm_res.get('result', '').upper():
                score += 10
                feedback_parts.append("VLM confirms workflow")
            else:
                feedback_parts.append("VLM did not confirm modeling workflow")
        except:
            pass # VLM fail shouldn't crash verifier
    
    return {
        "passed": score >= 70 and box_found and lid_found,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }