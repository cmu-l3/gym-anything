#!/usr/bin/env python3
"""
Verifier for Multi-Object Spectroscopy Target Selection (plan_mos_spectroscopy_targets).

Scoring Breakdown (100 points total):
  1. Exported Files exist and were created during task (15 pts)
  2. Correct number of target ROIs (10 pts)
  3. ROI geometry is correct (Area ~78.5 for 10x10 circles) (15 pts)
  4. Isolation constraint met (min pairwise distance >= 100 px) (25 pts)
  5. Real target verification (Peak > local background in FITS) (20 pts)
  6. VLM trajectory verification (15 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing screenshots of an agent performing Multi-Object Spectroscopy (MOS) target selection in AstroImageJ.
Review the sampled chronological frames.

Determine the following:
1. Did the agent use the "ROI Manager" window? (A window managing regions/selections)
2. Are there visible circular or oval Regions of Interest (ROIs - usually yellow outlines) drawn on the stars in the FITS image?

Respond in JSON format exactly like this:
{
    "used_roi_manager": true/false,
    "rois_visible_on_image": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_plan_mos_targets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # 1. Load result payload from container
    result = {}
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # 2. Check File Existence & Timestamps (15 pts)
    csv_ok = result.get("csv_exists", False) and result.get("csv_created_during_task", False)
    zip_ok = result.get("zip_exists", False) and result.get("zip_created_during_task", False)
    
    if csv_ok and zip_ok:
        score += 15
        feedback.append("CSV and ZIP files created successfully.")
    elif csv_ok or zip_ok:
        score += 7
        feedback.append("Only one of CSV or ZIP files was created successfully.")
    else:
        feedback.append("Required export files (CSV/ZIP) were not found or not created during task.")

    # 3. Correct Number of Targets (10 pts)
    num_rows = result.get("num_rows", 0)
    num_rois = result.get("num_rois_in_zip", 0)
    
    if num_rows == 8 and num_rois == 8:
        score += 10
        feedback.append("Exactly 8 target stars selected.")
    elif num_rows >= 8 and num_rois >= 8:
        score += 8
        feedback.append(f"More than 8 targets selected (CSV: {num_rows}, ZIP: {num_rois}).")
    elif num_rows > 0:
        score += int(10 * (num_rows / 8))
        feedback.append(f"Insufficient targets selected ({num_rows}/8).")

    # 4. Correct ROI Geometry (15 pts)
    areas_correct = result.get("areas_correct", False)
    if areas_correct and num_rows >= 8:
        score += 15
        feedback.append("ROI geometries correct (Area ~78.5 for 10x10 circles).")
    elif result.get("areas"):
        feedback.append(f"ROI geometries incorrect (Observed areas: {result.get('areas')[:3]}...).")

    # 5. Isolation Constraint Met (25 pts)
    min_distance = result.get("min_distance", 0.0)
    if num_rows >= 2:
        if min_distance >= 100.0:
            score += 25
            feedback.append(f"Isolation constraint met (Minimum separation: {min_distance:.1f} px).")
        else:
            feedback.append(f"Isolation constraint FAILED (Targets too close: {min_distance:.1f} px).")

    # 6. Real Target Verification (20 pts)
    real_stars = result.get("real_star_count", 0)
    if result.get("all_stars_real", False) or real_stars >= 8:
        score += 20
        feedback.append("Target verification passed (all coordinates correspond to actual stars).")
    elif real_stars > 0:
        score += int(20 * (real_stars / 8))
        feedback.append(f"Target verification partial: only {real_stars} coordinates match real stars.")
    else:
        feedback.append("Target verification FAILED: coordinates do not align with stars in the FITS data.")

    # 7. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                used_manager = parsed.get("used_roi_manager", False)
                rois_visible = parsed.get("rois_visible_on_image", False)
                
                if used_manager and rois_visible:
                    vlm_score = 15
                    feedback.append("VLM verified ROI Manager usage and visual selections.")
                elif used_manager or rois_visible:
                    vlm_score = 7
                    feedback.append("VLM partially verified visual UI usage.")
                else:
                    feedback.append("VLM did not detect ROI Manager or visual selections.")
            else:
                feedback.append("VLM query execution failed.")
    score += vlm_score

    # Final evaluation
    passed = (score >= 70) and (min_distance >= 100.0) and (num_rows >= 8)
    
    if result.get("error"):
        feedback.append(f"Validation warnings: {result['error']}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }