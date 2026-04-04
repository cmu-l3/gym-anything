#!/usr/bin/env python3
"""
Verifier for Stereocilia Orientation Analysis task.

Criteria:
1. Result file existence and creation time (anti-gaming).
2. Histogram data quality (row count, angular range).
3. Summary statistics (Preferred Direction, Dispersion).
4. VLM verification of workflow (Sample opened -> Analysis run).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stereocilia_orientation(traj, env_info, task_info):
    """
    Verify the orientation analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/stereocilia_orientation_analysis_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Timestamp (15 pts) ---
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("Result file created successfully.")
    elif result.get("file_exists"):
        feedback_parts.append("Result file exists but timestamp check failed (pre-existing?).")
    else:
        feedback_parts.append("Result file not found.")

    # --- Criterion 2: Histogram Data (40 pts) ---
    hist_rows = result.get("histogram_rows", 0)
    ang_range = result.get("angular_range", 0)
    has_amts = result.get("has_amount_values", False)
    
    if hist_rows >= 10:
        score += 15
        feedback_parts.append(f"Histogram has sufficient bins ({hist_rows}).")
    else:
        feedback_parts.append(f"Histogram has too few bins ({hist_rows} < 10).")
        
    if ang_range >= 150:
        score += 15
        feedback_parts.append(f"Angular range covers {ang_range:.1f}°.")
    else:
        feedback_parts.append(f"Angular range too narrow ({ang_range:.1f}° < 150°).")
        
    if has_amts:
        score += 10
        feedback_parts.append("Frequency values look valid.")
    else:
        feedback_parts.append("Frequency values missing or trivial.")

    # --- Criterion 3: Summary Statistics (25 pts) ---
    pref_dir = result.get("preferred_direction")
    dispersion = result.get("dispersion")
    
    if pref_dir is not None:
        score += 10
        feedback_parts.append(f"Preferred direction found ({pref_dir}).")
    else:
        feedback_parts.append("Preferred direction not found in CSV.")
        
    if dispersion is not None:
        if 1.0 <= dispersion <= 90.0:
            score += 15
            feedback_parts.append(f"Dispersion value valid ({dispersion}).")
        else:
            feedback_parts.append(f"Dispersion value out of range ({dispersion}).")
    else:
        feedback_parts.append("Dispersion not found in CSV.")

    # --- Criterion 4: VLM Verification (20 pts) ---
    # We check if the "Organ of Corti" image was actually visible
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an ImageJ task. The user should have opened the "Organ of Corti" sample image (a microscopy image of hair cells).
    
    Look at these screenshots.
    1. Do you see a microscopy image that looks like rows of V-shaped hair bundles or cellular structures?
    2. Do you see any "Directionality" or "Orientation" histograms or analysis windows?
    
    Return JSON: {"image_opened": boolean, "analysis_visible": boolean}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        if vlm_res.get("parsed", {}).get("image_opened", False):
            score += 10
            feedback_parts.append("VLM confirmed image opened.")
        if vlm_res.get("parsed", {}).get("analysis_visible", False):
            score += 10
            feedback_parts.append("VLM confirmed analysis tool usage.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if programmatic checks are very strong, allow pass, otherwise penalize
        if score >= 60: 
            score += 10 # Give benefit of doubt if data is good
            feedback_parts.append("VLM skipped (error), assuming valid due to good data.")

    # Final Pass/Fail
    passed = score >= 60 and result.get("file_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }