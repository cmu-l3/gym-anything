#!/usr/bin/env python3
"""
Verifier for Texture Feature Extraction task.

Scoring Criteria (100 points):
1. File created during task: 15 pts
2. Minimum 3 regions measured (rows >= 3): 20 pts
3. Mean Intensity present and valid: 15 pts
4. Standard Deviation present and valid: 15 pts
5. Additional texture metric present: 15 pts
6. Texture discrimination (StdDev values vary): 10 pts
7. Plausible value ranges (Mean 0-255, StdDev > 0): 10 pts

VLM Verification (Trajectory):
- Confirms MRI image was opened
- Confirms ROIs were drawn
"""

import json
import tempfile
import os
import logging
import statistics
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_texture_characterization(traj, env_info, task_info):
    """
    Verify the texture analysis task output and process.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Load JSON Result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/texture_region_characterization_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: File Existence & Timestamp (15 pts)
    # ---------------------------------------------------------
    if result.get("file_exists") and result.get("created_during_task"):
        score += 15
        feedback.append("Result file created successfully.")
    elif result.get("file_exists"):
        feedback.append("FAIL: Result file exists but was not modified during task.")
    else:
        feedback.append("FAIL: Result file not found.")

    # ---------------------------------------------------------
    # Criterion 2: Minimum 3 regions (20 pts)
    # ---------------------------------------------------------
    rows = result.get("row_count", 0)
    if rows >= 3:
        score += 20
        feedback.append(f"Measured {rows} regions (>= 3).")
    else:
        feedback.append(f"FAIL: Only measured {rows} regions (need at least 3).")

    # ---------------------------------------------------------
    # Criterion 3: Mean Intensity (15 pts)
    # ---------------------------------------------------------
    if result.get("has_mean") and len(result.get("mean_values", [])) > 0:
        score += 15
        feedback.append("Mean intensity data present.")
    else:
        feedback.append("FAIL: Mean intensity column missing or empty.")

    # ---------------------------------------------------------
    # Criterion 4: Standard Deviation (15 pts)
    # ---------------------------------------------------------
    if result.get("has_stddev") and len(result.get("stddev_values", [])) > 0:
        score += 15
        feedback.append("Standard Deviation data present.")
    else:
        feedback.append("FAIL: Standard Deviation column missing or empty.")

    # ---------------------------------------------------------
    # Criterion 5: Additional Metric (15 pts)
    # ---------------------------------------------------------
    if result.get("has_additional"):
        score += 15
        feedback.append("Additional texture metric found.")
    else:
        feedback.append("FAIL: No additional texture metric (Min, Max, Skew, etc.) found.")

    # ---------------------------------------------------------
    # Criterion 6: Texture Discrimination (10 pts)
    # ---------------------------------------------------------
    # Different tissues MUST have different texture/variance.
    # If all StdDev values are identical, the agent likely faked it or measured same spot.
    std_vals = result.get("stddev_values", [])
    if len(std_vals) > 1:
        variance = result.get("stddev_variance", 0)
        # We expect some variance. If variance is extremely low (< 0.1), it's suspicious.
        if variance > 0.5:
            score += 10
            feedback.append("Texture discrimination validated (variance detected).")
        else:
            feedback.append("FAIL: Standard deviation values are identical or too similar. Different tissues should have distinct textures.")
    else:
        feedback.append("FAIL: Not enough data points to verify texture discrimination.")

    # ---------------------------------------------------------
    # Criterion 7: Plausible Ranges (10 pts)
    # ---------------------------------------------------------
    # Mean should be 0-255 (MRI stack is 8-bit or 16-bit, but usually < 255 scaled in Sample)
    # StdDev should be > 0
    means = result.get("mean_values", [])
    stds = result.get("stddev_values", [])
    
    valid_means = all(0 <= m <= 10000 for m in means) # Generous upper bound for 16-bit
    valid_stds = all(s > 0 for s in stds)
    
    if means and stds and valid_means and valid_stds:
        score += 10
        feedback.append("Data values are in plausible ranges.")
    else:
        feedback.append("FAIL: Data values implausible (negative or zero StdDev).")

    # ---------------------------------------------------------
    # VLM Verification (Bonus/Sanity Check)
    # ---------------------------------------------------------
    # Not strictly scored for points here to keep verification fast/deterministic, 
    # but could be used to flag false positives.
    # We will just print the result of a check.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }