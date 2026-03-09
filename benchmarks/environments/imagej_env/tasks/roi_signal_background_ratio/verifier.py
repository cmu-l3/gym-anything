#!/usr/bin/env python3
"""
Verifier for ROI Signal-to-Background Ratio task.

Scoring Criteria:
1.  CSV file exists and created during task (15 pts)
2.  Measurement data quality (Rows >= 4, Labels, Mean, Area) (30 pts)
    - Row count >= 4 (15 pts)
    - Has descriptive labels (signal/bg) (5 pts)
    - Has Mean/Area columns (10 pts)
3.  Sanity Check (Signal > Background) (20 pts)
4.  SBR value present and valid (15 pts)
5.  ROI Set ZIP file saved (10 pts)
6.  VLM Process Verification (10 pts)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_roi_signal_background_ratio(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/roi_sbr_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. File Existence & Anti-Gaming (15 pts)
    if data.get("csv_exists") and data.get("file_created_during_task"):
        score += 15
        feedback.append("Measurements CSV created.")
    elif data.get("csv_exists"):
        score += 5
        feedback.append("Measurements CSV exists but timestamp is old.")
    else:
        feedback.append("Measurements CSV not found.")

    # 2. Data Quality (30 pts)
    row_count = data.get("row_count", 0)
    if row_count >= 4:
        score += 15
        feedback.append(f"Sufficient ROIs measured ({row_count}).")
    elif row_count > 0:
        score += 5
        feedback.append(f"Insufficient ROIs ({row_count}, expected 4+).")

    if data.get("label_compliance"):
        score += 5
        feedback.append("ROIs labeled correctly (signal/bg).")
    else:
        feedback.append("ROI labels missing or generic.")

    if data.get("has_mean") and data.get("has_area"):
        score += 10
        feedback.append("Mean and Area columns present.")
    else:
        feedback.append("Missing required columns (Mean/Area).")

    # 3. Sanity Check (20 pts)
    if data.get("sanity_check_passed"):
        score += 20
        feedback.append("Intensity validation passed (Signal > Background).")
    else:
        sig = data.get("signal_mean", 0)
        bg = data.get("bg_mean", 0)
        feedback.append(f"Intensity validation failed or missing (Signal:{sig:.1f} vs Bg:{bg:.1f}).")

    # 4. SBR Value (15 pts)
    if data.get("sbr_found"):
        sbr = data.get("sbr_value", 0)
        if 1.0 < sbr < 1000:
            score += 15
            feedback.append(f"Valid SBR found: {sbr:.2f}.")
        else:
            score += 5
            feedback.append(f"SBR found but suspicious value: {sbr}.")
    else:
        feedback.append("No Signal-to-Background Ratio found in file.")

    # 5. ROI Zip (10 pts)
    if data.get("zip_exists") and data.get("roi_count", 0) > 0:
        score += 10
        feedback.append("ROI Set saved.")

    # 6. VLM Process Verification (10 pts)
    # Check if we can see ROI manager usage in trajectory
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Review these screenshots of an ImageJ task.
        Look for:
        1. An open microscopy image (cells).
        2. The "ROI Manager" window open.
        3. Yellow outline drawings (ROIs) on the image.
        
        Does the user appear to be defining regions of interest?
        Return JSON: {"roi_manager_visible": bool, "rois_drawn": bool}
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("roi_manager_visible") or parsed.get("rois_drawn"):
            score += 10
            feedback.append("VLM confirmed ROI workflow.")
        else:
            feedback.append("VLM did not observe ROI Manager usage.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grant points if programmatic evidence is strong (zip file exists)
        if data.get("zip_exists"):
            score += 10

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }