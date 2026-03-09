#!/usr/bin/env python3
"""
Verifier for estimate_reach_residence_time task.

Checks:
1. Did the user create the required CSV and Report files?
2. Are the calculated values (Volume, Residence Time) accurate?
3. Is the CSV structure correct?
"""

import json
import tempfile
import os
import logging
import base64
import math
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_estimate_reach_residence_time(traj, env_info, task_info):
    """
    Verify residence time calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    feedback_parts = []
    
    # 1. File Existence Checks (20 pts)
    csv_exists = result.get('csv_exists', False)
    report_exists = result.get('report_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if csv_exists:
        score += 10
        feedback_parts.append("CSV file created.")
    else:
        feedback_parts.append("CSV file missing.")

    if report_exists:
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing.")

    if not created_during:
        feedback_parts.append("Files were not modified during task (anti-gaming check).")
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: Files not created during task."}

    # 2. Accuracy Checks (60 pts)
    gt = result.get('ground_truth', {})
    if not gt.get('success'):
        return {"passed": False, "score": score, "feedback": f"Ground truth generation failed: {gt.get('error')}"}
        
    gt_vol = gt.get('ground_truth_volume', 0)
    gt_time = gt.get('ground_truth_time_hrs', 0)
    
    # Extract user values from report string
    user_vals_str = result.get('user_report_values_str', "")
    # Parse all floats from the string
    user_floats = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", user_vals_str)]
    
    # We look for values "close" to GT in the list of user numbers
    # This allows flexibility in report formatting
    vol_found = False
    time_found = False
    
    # Tolerance: 5%
    for val in user_floats:
        if abs(val - gt_vol) / (gt_vol + 1e-9) < 0.05:
            vol_found = True
        if abs(val - gt_time) / (gt_time + 1e-9) < 0.05:
            time_found = True
            
    if vol_found:
        score += 30
        feedback_parts.append(f"Volume calculation accurate ({gt_vol:.2f} cu ft).")
    else:
        feedback_parts.append(f"Volume calculation incorrect. Expected approx {gt_vol:.2f}.")
        
    if time_found:
        score += 30
        feedback_parts.append(f"Residence time accurate ({gt_time:.2f} hrs).")
    else:
        feedback_parts.append(f"Residence time incorrect. Expected approx {gt_time:.2f}.")

    # 3. CSV Structure Check (20 pts)
    # Check if header contains required columns
    try:
        csv_head = base64.b64decode(result.get('user_csv_head_b64', '')).decode('utf-8')
        required_cols = ['RiverStation', 'ReachLength', 'AvgArea', 'SegmentVolume']
        missing_cols = [col for col in required_cols if col.lower() not in csv_head.lower()]
        
        if not missing_cols:
            score += 20
            feedback_parts.append("CSV structure looks correct.")
        else:
            # Partial credit if some cols exist
            if len(missing_cols) < len(required_cols):
                score += 10
                feedback_parts.append(f"CSV missing some columns: {missing_cols}")
            else:
                feedback_parts.append("CSV headers unrecognized.")
    except Exception:
        feedback_parts.append("Could not verify CSV structure.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": {
            "ground_truth_volume": gt_vol,
            "ground_truth_time": gt_time,
            "user_values_found": user_floats
        }
    }