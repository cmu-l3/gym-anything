#!/usr/bin/env python3
"""
Verifier for create_master_dark task.
Uses programmatic validation of FITS file arrays to prove the agent
mathematically performed a Z-Project > Median stacking operation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_master_dark(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve the programmatic evaluation calculated inside the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Base error check
    if result.get("error_msg"):
        feedback.append(f"Evaluation encountered a reading error: {result['error_msg']}")

    # Criteria 1: Output File Exists (15 points)
    if result.get("output_exists"):
        score += 15
        feedback.append("FITS output file exists.")
    else:
        feedback.append("FITS output file NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criteria 2: Anti-Gaming timestamp (15 points)
    if result.get("created_after_start"):
        score += 15
        feedback.append("File created during task session.")
    else:
        feedback.append("File existed before task started (Potential cheat/failure to overwrite).")

    # Criteria 3: 2D Projection Format (10 points)
    if result.get("is_2d"):
        score += 10
        feedback.append("Stack was correctly collapsed to 2D.")
    else:
        feedback.append("Output is not 2D. Did not Z-Project correctly.")

    # Mathematical Verification of the Array
    mae_median = result.get("mae_median", float('inf'))
    mae_average = result.get("mae_average", float('inf'))
    mae_single = result.get("mae_single", 0.0)
    
    # Check if a mathematical combination happened (not just saving one frame)
    stacking_executed = False
    
    # Criteria 4: Combined arrays logically (20 points)
    if mae_single > 1.0 and (mae_median < 10.0 or mae_average < 10.0):
        stacking_executed = True
        score += 20
        feedback.append("Stacking operation confirmed (output varies from a single raw frame).")
    elif mae_single <= 1.0:
        feedback.append("Output identical to a single raw frame (Stacking bypassed).")

    # Criteria 5: Specifically used MEDIAN (40 points)
    # Median is critical in dark frames to eliminate transient cosmic rays.
    # We allow a small float error tolerance (<0.5) for 32/64 bit conversion in saving FITS.
    if stacking_executed:
        if mae_median < 0.5 and mae_median < mae_average:
            score += 40
            feedback.append(f"Successfully used Median Projection. (MAE vs Median: {mae_median:.3f})")
        elif mae_average < 0.5:
            # They combined it, but selected Average instead of Median.
            feedback.append(f"Incorrectly used Average Projection instead of Median. (MAE vs Average: {mae_average:.3f})")
        else:
            feedback.append(f"Output array does not match expected Median or Average calculations.")

    # To pass, they must have executed the stack AND used Median (Total >= 80 required)
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }