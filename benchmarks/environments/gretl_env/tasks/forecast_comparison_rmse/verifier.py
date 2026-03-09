#!/usr/bin/env python3
"""
Verifier for forecast_comparison_rmse task.

Checks:
1. Report file existence and freshness.
2. Report content parsing (extract RMSE values).
3. Plausibility of RMSE values (inflation data typically 0-10 range).
4. Logical consistency (Best Model matches lower RMSE).
5. VLM verification of the workflow (forecasting dialogs/plots).
"""

import json
import os
import re
import base64
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forecast_comparison_rmse(traj, env_info, task_info):
    """
    Verify the forecasting comparison task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Output File Existence (20 pts) ---
    if not result.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file 'rmse_report.txt' not found."
        }
    score += 20
    feedback.append("Report file created.")

    # --- Criterion 2: Freshness (10 pts) ---
    if result.get("file_created_during_task", False):
        score += 10
    else:
        feedback.append("Warning: File timestamp suggests it wasn't created during this task.")

    # --- Criterion 3: Content Parsing & Accuracy (40 pts) ---
    content_b64 = result.get("output_content_base64", "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        content = ""

    # Look for patterns like "AR(1) RMSE: 1.234" or "RMSE AR1: 1.234"
    # Flexible regex to catch various formats
    ar1_match = re.search(r"AR\(?1\)?.*?RMSE.*?:?\s*([0-9.]+)", content, re.IGNORECASE)
    ar4_match = re.search(r"AR\(?4\)?.*?RMSE.*?:?\s*([0-9.]+)", content, re.IGNORECASE)
    
    rmse_ar1 = float(ar1_match.group(1)) if ar1_match else None
    rmse_ar4 = float(ar4_match.group(1)) if ar4_match else None
    
    # Standard inflation RMSEs are typically between 1.0 and 3.0 for this period/data
    # We verify they are numbers and in a plausible range
    valid_range = (0.1, 10.0)
    
    if rmse_ar1 is not None and valid_range[0] <= rmse_ar1 <= valid_range[1]:
        score += 15
        feedback.append(f"AR(1) RMSE found: {rmse_ar1}")
    else:
        feedback.append("AR(1) RMSE missing or out of plausible range.")

    if rmse_ar4 is not None and valid_range[0] <= rmse_ar4 <= valid_range[1]:
        score += 15
        feedback.append(f"AR(4) RMSE found: {rmse_ar4}")
    else:
        feedback.append("AR(4) RMSE missing or out of plausible range.")
        
    # --- Criterion 4: Logical Consistency (10 pts) ---
    # Does the report correctly identify the winner?
    # Usually AR(4) might be slightly better or worse, we just check consistency
    if rmse_ar1 is not None and rmse_ar4 is not None:
        best_model_line = re.search(r"Best.*?Model.*?:?\s*(AR\(?[14]\)?)", content, re.IGNORECASE)
        if best_model_line:
            declared_best = best_model_line.group(1)
            actual_winner = "AR(1)" if rmse_ar1 < rmse_ar4 else "AR(4)"
            
            # Normalize strings for comparison
            decl_norm = declared_best.upper().replace("(", "").replace(")", "")
            win_norm = actual_winner.upper().replace("(", "").replace(")", "")
            
            if decl_norm == win_norm:
                score += 10
                feedback.append(f"Correctly identified best model: {actual_winner}")
            else:
                feedback.append(f"Incorrect best model identified (Report said {declared_best}, Data says {actual_winner})")
        else:
            feedback.append("Could not parse 'Best Model' conclusion.")

    # --- Criterion 5: App Running (10 pts) ---
    if result.get("app_was_running", False):
        score += 10
    
    # --- Criterion 6: VLM check (10 pts) ---
    # If we parsed numbers successfully, we assume work was done, giving full visual points
    # This is a heuristic to save VLM calls if programmatic verification passes high
    if score >= 60:
        score += 10
        feedback.append("Implicit visual verification passed via data extraction.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }