#!/usr/bin/env python3
"""
Verifier for Morphological Series Analysis task.

Verification Strategy:
1. Programmatic Checks (75 pts):
   - Result file existence & creation time (15 pts)
   - Completeness: 5 conditions present (Original, Erode, Dilate, Open, Close) (20 pts)
   - Columns: Count, Area, Avg Size present (15 pts)
   - Logic: Erosion reduces area, Dilation increases area (20 pts)
   - Consistency: Values are positive numbers (5 pts)

2. VLM Checks (25 pts):
   - Verify workflow progression using trajectory frames.
   - Confirm ImageJ/Fiji usage and distinct operations.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

def _vlm_query(query_vlm, prompt, images):
    """Run VLM query with multiple images."""
    if not query_vlm or not images:
        return None
    try:
        result = query_vlm(prompt=prompt, images=images)
        if result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

VLM_PROMPT = """You are verifying an image analysis task in Fiji/ImageJ.
The user was supposed to:
1. Open the 'Blobs' image.
2. Apply a threshold (binary).
3. Perform a series of operations: Erode, Dilate, Open, Close.
4. Record measurements for each.

Look at the sequence of screenshots.
1. Do you see the 'Blobs' image (black spots on white or white on black)?
2. Do you see any evidence of morphological operations (menu usage like Process > Binary > Erode/Dilate, or changing blob shapes)?
3. Do you see a 'Results' table window appearing?

Respond in JSON:
{
    "blobs_image_seen": true/false,
    "operations_evidence": true/false,
    "results_table_seen": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_morphological_series(traj, env_info, task_info):
    """
    Verify morphological series analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    score = 0
    feedback_parts = []
    
    # 1. Load JSON Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/morphological_series_analysis_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 2. Programmatic Verification (75 pts max)
    
    # File exists and created during task (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("Result file created successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("Result file exists but timestamp check failed.")
    else:
        feedback_parts.append("Result file not found.")

    # Completeness (20 pts)
    conditions_found = result.get("conditions_found", [])
    unique_conditions = len(set([c.lower() for c in conditions_found]))
    
    if unique_conditions >= 5:
        score += 20
        feedback_parts.append("All 5 conditions found.")
    elif unique_conditions >= 3:
        score += 10
        feedback_parts.append(f"Found {unique_conditions}/5 conditions.")
    else:
        feedback_parts.append(f"Only {unique_conditions} conditions found (need 5).")

    # Columns (15 pts)
    cols_score = 0
    if result.get("has_count"): cols_score += 5
    if result.get("has_area"): cols_score += 5
    if result.get("has_avg_size"): cols_score += 5
    score += cols_score
    if cols_score == 15:
        feedback_parts.append("All required columns present.")
    else:
        feedback_parts.append("Some columns missing.")

    # Logical Trends (20 pts)
    # This is critical anti-gaming: Erode MUST reduce area, Dilate MUST increase it.
    trends_score = 0
    if result.get("trend_erode_reduces_area"):
        trends_score += 10
        feedback_parts.append("Trend verified: Erosion reduced area.")
    else:
        feedback_parts.append("Trend FAIL: Erosion did not reduce area (or data missing).")

    if result.get("trend_dilate_increases_area"):
        trends_score += 10
        feedback_parts.append("Trend verified: Dilation increased area.")
    else:
        feedback_parts.append("Trend FAIL: Dilation did not increase area (or data missing).")
    
    score += trends_score

    # Data Consistency (5 pts)
    if result.get("data_consistency_score", 0) >= 3:
        score += 5
    
    # 3. VLM Verification (25 pts max)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, 5)
        vlm_res = _vlm_query(query_vlm, VLM_PROMPT, frames)
        
        if vlm_res:
            if vlm_res.get("blobs_image_seen"): vlm_score += 10
            if vlm_res.get("operations_evidence"): vlm_score += 10
            if vlm_res.get("results_table_seen"): vlm_score += 5
            
            if vlm_score > 0:
                feedback_parts.append(f"VLM Verification passed ({vlm_score}/25 pts).")
    else:
        # Grace points if VLM not available but Programmatic is perfect
        if score >= 70:
            vlm_score = 25
            feedback_parts.append("VLM skipped (auto-pass based on strong data).")

    score += vlm_score

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }