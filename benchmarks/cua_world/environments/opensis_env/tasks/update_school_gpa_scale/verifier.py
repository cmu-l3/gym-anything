#!/usr/bin/env python3
"""
Verifier for update_school_gpa_scale task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_school_gpa_scale(traj, env_info, task_info):
    """
    Verify that the agent updated the school's GPA scale to 5.00.
    
    Verification Logic:
    1. Retrieve the database state exported by export_result.sh.
    2. Check if the final GPA scale matches the target (5.00).
    3. Verify that the value actually changed from the initial state (4.00).
    """
    
    # 1. Setup: Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Critical Error: Copy function not available in environment."
        }

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Extract Values
    initial_scale_str = str(result.get("initial_gpa_scale", "")).strip()
    final_scale_str = str(result.get("final_gpa_scale", "")).strip()
    target_scale_str = str(result.get("target_gpa_scale", "5.00")).strip()
    
    # Clean up values (remove generic trailing zeros for comparison, but keep float precision logic)
    try:
        final_val = float(final_scale_str)
        target_val = float(target_scale_str)
        initial_val = float(initial_scale_str) if initial_scale_str and initial_scale_str != "UNKNOWN" else 4.0
    except ValueError:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid data format in database. Got: '{final_scale_str}'"
        }

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: Database Access (10 pts)
    if result.get("db_service_running", False):
        score += 10
    else:
        feedback.append("Warning: Database service was not running at verification time.")

    # Criterion 2: Value Change Detection (30 pts)
    # Did the value change from the initial state?
    if abs(final_val - initial_val) > 0.01:
        score += 30
        feedback.append("Database record was modified.")
    else:
        feedback.append(f"Value did not change (Initial: {initial_val}, Final: {final_val}).")

    # Criterion 3: Correct Target Value (60 pts)
    # Is the final value 5.0?
    if abs(final_val - target_val) < 0.01:
        score += 60
        feedback.append(f"Success: GPA Scale updated correctly to {final_val}.")
    elif abs(final_val - initial_val) < 0.01:
        # Already handled in Criterion 2, but specific feedback here
        feedback.append("Failure: GPA Scale remains at default value.")
    else:
        feedback.append(f"Failure: GPA Scale updated to incorrect value {final_val} (Expected: {target_val}).")

    # 5. Final Decision
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }