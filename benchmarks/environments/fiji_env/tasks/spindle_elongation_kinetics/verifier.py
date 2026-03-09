#!/usr/bin/env python3
"""
Verifier for spindle_elongation_kinetics@1
Tests:
1. Artifact existence (Image + Report)
2. Artifact freshness (Created during task)
3. Measurement Validity (Within expected physical ranges for the sample)
4. Calculation Logic (Velocity matches distance/time)
"""

import json
import os
import logging
import math
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spindle_elongation_kinetics(traj, env_info, task_info):
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (no copy_from_env)."}

    # Load metadata for ranges
    metadata = task_info.get('metadata', {}).get('ground_truth_ranges', {})
    DIST_30_MIN = metadata.get('dist_30_min', 4.0)
    DIST_30_MAX = metadata.get('dist_30_max', 9.0)
    DIST_45_MIN = metadata.get('dist_45_min', 8.0)
    DIST_45_MAX = metadata.get('dist_45_max', 14.0)
    
    # Retrieve result JSON
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    score = 0
    feedback = []
    
    # 2. Check File Artifacts (Start: 0 pts)
    # ----------------------------------------------------------------
    
    # Image check (20 pts)
    if result.get('image_exists') and result.get('image_created_during_task'):
        # Check size to ensure it's not empty
        if result.get('image_size_bytes', 0) > 1000:
            score += 20
            feedback.append("Projection image saved successfully.")
        else:
            feedback.append("Projection image file is empty or too small.")
    else:
        feedback.append("Projection image not found or not created during task.")

    # Report check (10 pts)
    report_values = result.get('report_values', {})
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 10
        feedback.append("Velocity report saved successfully.")
    else:
        feedback.append("Velocity report not found or not created during task.")

    # 3. specific Data Validation (Start: 30 pts)
    # ----------------------------------------------------------------
    
    d30 = report_values.get('dist_f30')
    d45 = report_values.get('dist_f45')
    t_delta = report_values.get('time_delta')
    velocity = report_values.get('velocity')
    
    # Validate extraction
    if None in [d30, d45, t_delta, velocity]:
        feedback.append("Could not parse all values from report. Ensure format: 'Key: Value'.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Validate Ranges (20 pts)
    range_score = 0
    if d30 and DIST_30_MIN <= d30 <= DIST_30_MAX:
        range_score += 5
    else:
        feedback.append(f"Frame 30 distance ({d30}) out of expected range ({DIST_30_MIN}-{DIST_30_MAX}).")
        
    if d45 and DIST_45_MIN <= d45 <= DIST_45_MAX:
        range_score += 5
    else:
        feedback.append(f"Frame 45 distance ({d45}) out of expected range ({DIST_45_MIN}-{DIST_45_MAX}).")
        
    if d45 and d30 and d45 > d30:
        range_score += 10 # Basic logic: spindle elongates
    else:
        feedback.append("Distance did not increase during anaphase.")
        
    score += range_score
    feedback.append(f"Data Plausibility Score: {range_score}/20.")

    # 4. Calculation Logic Validation (50 pts)
    # ----------------------------------------------------------------
    # Formula: V = (d2 - d1) / t
    
    if t_delta and t_delta > 0:
        calculated_velocity = (d45 - d30) / t_delta
        
        # Allow 5% tolerance for rounding errors
        if math.isclose(calculated_velocity, velocity, rel_tol=0.05):
            score += 50
            feedback.append("Velocity calculation is correct.")
        else:
            feedback.append(f"Velocity calculation mismatch. Reported: {velocity}, Expected based on data: {calculated_velocity:.4f}.")
            # Partial credit if they just messed up units or something obvious? 
            # Sticking to strict logic for 'hard' task.
    else:
        feedback.append("Invalid time delta (must be > 0).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }