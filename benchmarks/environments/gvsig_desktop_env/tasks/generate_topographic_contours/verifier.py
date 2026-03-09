#!/usr/bin/env python3
"""
Verifier for generate_topographic_contours task.
Verifies that a shapefile was created with contour lines at 5m intervals.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_topographic_contours(traj, env_info, task_info):
    """
    Verify the contour generation task.
    
    Criteria:
    1. Output shapefile exists (20 pts)
    2. File created during task (timestamp check) (10 pts)
    3. Feature count is reasonable (not empty, not huge) (20 pts)
    4. Interval Check (Elevation values are multiples of 5) (30 pts)
    5. VLM Visual Verification (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence (20 pts) ---
    if result.get("file_exists", False):
        score += 20
        feedback.append("Output shapefile exists.")
    else:
        feedback.append("Output shapefile NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- Criterion 2: Anti-Gaming / Timestamp (10 pts) ---
    if result.get("file_created_during_task", False):
        score += 10
        feedback.append("File created during task session.")
    else:
        feedback.append("File timestamp indicates it was pre-existing or old.")

    # --- Criterion 3: Feature Count (20 pts) ---
    count = int(result.get("feature_count", 0))
    min_count = task_info.get("metadata", {}).get("min_feature_count", 10)
    # 2x2m DEM subset isn't huge, but should have valid contours
    if count >= min_count:
        score += 20
        feedback.append(f"Feature count ({count}) is valid.")
    elif count > 0:
        score += 10
        feedback.append(f"Feature count ({count}) is low (expected > {min_count}).")
    else:
        feedback.append("Shapefile is empty.")

    # --- Criterion 4: Interval Check (30 pts) ---
    interval_status = result.get("interval_check", "fail")
    if interval_status == "pass":
        score += 30
        feedback.append("Contour interval verified (5m).")
    elif interval_status == "fail_no_field":
        feedback.append("Could not identify elevation field in attribute table.")
    else:
        feedback.append("Contour interval verification failed (values not multiples of 5).")

    # --- Criterion 5: VLM Verification (20 pts) ---
    # Check if agent actually used the tool
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Review these screenshots of a GIS task in gvSIG Desktop. "
        "The goal was to generate contour lines from a DEM raster. "
        "1. Do you see a grayscale raster image (DEM) loaded? "
        "2. Do you see a dialog for 'Contour Lines', 'Isolines', or 'Geoprocessing'? "
        "3. In the final image, are there vector lines (colored lines) overlaid on the map? "
        "Return JSON: { \"raster_visible\": bool, \"tool_dialog_visible\": bool, \"contours_visible\": bool }"
    )
    
    try:
        vlm_resp = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        # Parse simplified JSON response from VLM helper
        # (Assuming query_vlm returns a dict or we parse the string)
        if isinstance(vlm_resp, str):
            # Simple fallback parsing if VLM returns string
            vlm_score = 0
            if "true" in vlm_resp.lower(): vlm_score = 20
        else:
            # Assuming dict
            vlm_score = 0
            if vlm_resp.get("raster_visible"): vlm_score += 5
            if vlm_resp.get("tool_dialog_visible"): vlm_score += 5
            if vlm_resp.get("contours_visible"): vlm_score += 10
            
        score += vlm_score
        feedback.append(f"VLM Verification Score: {vlm_score}/20")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grant partial credit if file checks passed strongly
        if score >= 60:
            score += 10
            feedback.append("VLM check skipped, partial credit granted.")

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }