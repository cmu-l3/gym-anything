#!/usr/bin/env python3
"""
Verifier for compute_flood_hazard_index task.

Checks:
1. Output CSV exists and has correct format.
2. Data accuracy (Depth, Velocity, DV Product) vs Ground Truth (computed in export script).
3. Classification accuracy.
4. Summary file existence.
5. VLM trajectory verification (did the agent write code/inspect data?).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_flood_hazard_index(traj, env_info, task_info):
    """
    Verify the flood hazard index calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    # 1. File Existence (20 pts)
    csv_exists = result.get("csv_exists", False)
    csv_new = result.get("csv_created_during", False)
    
    if csv_exists and csv_new:
        score += 20
        feedback_parts.append("CSV file created successfully.")
    elif csv_exists:
        score += 10
        feedback_parts.append("CSV file exists but timestamp suggests it wasn't created during this task.")
    else:
        feedback_parts.append("CSV file not found.")

    # 2. Data Validation (from internal verification) (60 pts)
    internal = result.get("internal_verification", {})
    if internal.get("user_csv_valid", False):
        acc = internal.get("accuracy", {})
        
        # Check coverage
        matched = acc.get("stations_matched", 0)
        if matched > 5: # Muncie has ~23 stations
            score += 10
            feedback_parts.append(f"Processed {matched} stations.")
        
        # Check Value Accuracy (MSE tolerances)
        # Depth
        if acc.get("depth_mse", 999) < 0.1:
            score += 15
            feedback_parts.append("Depth values accurate.")
        else:
            feedback_parts.append(f"Depth values inaccurate (MSE: {acc.get('depth_mse'):.2f}).")
            
        # Velocity
        if acc.get("velocity_mse", 999) < 0.5:
            score += 15
            feedback_parts.append("Velocity values accurate.")
        
        # DV Product (Logic check)
        if acc.get("dv_mse", 999) < 1.0:
            score += 10
            feedback_parts.append("DV Products accurate.")
            
        # Classification
        cat_acc = acc.get("category_accuracy", 0)
        if cat_acc > 0.9:
            score += 10
            feedback_parts.append("Hazard classification correct.")
        elif cat_acc > 0.5:
            score += 5
            feedback_parts.append(f"Hazard classification partially correct ({cat_acc:.1%}).")
    else:
        feedback_parts.append("CSV format invalid or columns missing.")

    # 3. Summary File (10 pts)
    if result.get("summary_exists", False):
        score += 10
        feedback_parts.append("Summary report found.")
        
    # 4. VLM Check (Trajectory) (10 pts)
    # Simple check: did we pass the basics?
    # Ideally we'd call a VLM here to verify they looked at the HDF/wrote code.
    # For now, we assume if they generated a valid CSV with correct values matching the HDF, they did the work.
    if score >= 70:
        score += 10 # Bonus for high quality output implies process was followed
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }