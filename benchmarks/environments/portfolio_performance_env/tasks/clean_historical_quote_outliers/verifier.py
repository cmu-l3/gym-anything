#!/usr/bin/env python3
"""Verifier for clean_historical_quote_outliers task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_historical_quote_outliers(traj, env_info, task_info):
    """
    Verify that the outlier data point was removed from the portfolio file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
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
    feedback = []
    
    # 1. File Modification (20 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 20
        feedback.append("File saved successfully")
    elif result.get('file_exists'):
        feedback.append("File exists but was NOT modified/saved")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}

    # 2. Outlier Removal (50 pts)
    outliers = result.get('outliers_found', 0)
    outlier_removed = result.get('outlier_removed', False)
    
    if outlier_removed:
        score += 50
        feedback.append("Outlier removed successfully")
    else:
        min_val = result.get('min_price_val', 0)
        # PP internal units: 5000000000 = $50.00
        min_val_usd = min_val / 100000000.0
        feedback.append(f"Outlier still present (found price ${min_val_usd:.2f})")

    # 3. Data Preservation (30 pts)
    # Don't award if they just deleted everything
    final_count = result.get('final_count', 0)
    initial_count = result.get('initial_count', 20)
    
    # We expect 1 deletion. 
    # Perfect: Initial - 1. 
    # Acceptable: Initial - 2 to Initial (maybe they edited value instead of delete)
    if 10 <= final_count <= initial_count + 1:
        score += 30
        feedback.append(f"Valid data preserved ({final_count} records)")
    elif final_count < 10:
        feedback.append(f"Too much data deleted! ({final_count} records remaining)")
    else:
        feedback.append(f"Data count check failed ({final_count} records)")

    # Pass threshold
    passed = (score >= 90) # Requires save + remove + preserve

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }