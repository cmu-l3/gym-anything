#!/usr/bin/env python3
"""
Verifier for configure_system_default_columns task.
Verifies that the system-wide default columns setting in OpenProject
matches the specified list and was updated during the task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_default_columns(traj, env_info, task_info):
    """
    Verify the OpenProject system setting for work package columns.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_columns = metadata.get('expected_columns', 
        ["id", "subject", "status", "assigned_to", "duedate", "done_ratio"])
    forbidden_columns = metadata.get('forbidden_columns', ["type", "priority"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    task_start = result.get('task_start', 0)
    setting_data = result.get('setting_data', {})
    current_columns = setting_data.get('value', [])
    updated_at = setting_data.get('updated_at', 0)
    
    # Normalize column names (just in case)
    # OpenProject internal names are usually snake_case strings
    current_columns = [str(c).lower() for c in current_columns]
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Setting was updated during task (Anti-gaming) (20 pts)
    # Allow a small buffer for clock skew, though docker vs host usually syncs well
    if updated_at >= task_start:
        score += 20
        feedback_parts.append("Settings updated during task")
    else:
        feedback_parts.append("Settings NOT updated during task (timestamp check failed)")
        
    # CRITERION 2: Core required columns present (40 pts)
    # Specifically check for Due date (duedate) and % Complete (done_ratio)
    # as these were the specific goal of the task
    core_present = True
    missing_core = []
    for col in ["duedate", "done_ratio"]:
        if col not in current_columns:
            core_present = False
            missing_core.append(col)
    
    if core_present:
        score += 40
        feedback_parts.append("Required columns (Due date, % Complete) present")
    else:
        feedback_parts.append(f"Missing required columns: {', '.join(missing_core)}")
        
    # CRITERION 3: Forbidden columns removed (20 pts)
    forbidden_present = []
    for col in forbidden_columns:
        if col in current_columns:
            forbidden_present.append(col)
            
    if not forbidden_present:
        score += 20
        feedback_parts.append("Unwanted columns (Type, Priority) removed")
    else:
        feedback_parts.append(f"Unwanted columns still present: {', '.join(forbidden_present)}")
        
    # CRITERION 4: Exact Match & Order (20 pts)
    # Checks if the list is exactly what was requested
    if current_columns == expected_columns:
        score += 20
        feedback_parts.append("Column order matches exactly")
    else:
        feedback_parts.append(f"Column order mismatch. Expected: {expected_columns}, Got: {current_columns}")

    # Pass logic
    # Must have updated the setting AND have core columns present AND removed forbidden ones
    # Exact order is a "nice to have" for full points but maybe not strictly fail-worthy if close?
    # Threshold: 80 points (meaning everything except maybe exact order or timestamp must be right)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "current": current_columns,
            "expected": expected_columns,
            "updated_during_task": updated_at >= task_start
        }
    }