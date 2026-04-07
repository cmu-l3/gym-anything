#!/usr/bin/env python3
"""
Verifier for log_project_expenses task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_project_expenses(traj, env_info, task_info):
    """
    Verify that the 'Costs' module was enabled and the expense was logged.
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Internal verification error: {result['error']}"}

    # Extract data
    module_enabled = result.get("module_enabled", False)
    entry_found = result.get("entry_found", False)
    entry_data = result.get("entry_data", {})
    expected_cost_type_id = result.get("expected_cost_type_id")
    task_start = result.get("task_start", 0)

    score = 0
    feedback = []

    # Criterion 1: Module Enabled (30 pts)
    if module_enabled:
        score += 30
        feedback.append("Success: 'Costs' module is enabled for the project.")
    else:
        feedback.append("Fail: 'Costs' module is NOT enabled.")

    # Criterion 2: Cost Entry Exists (30 pts)
    if entry_found and entry_data:
        # Check timestamp (Anti-gaming)
        created_at = entry_data.get("created_at_unixtime", 0)
        if created_at > task_start:
            score += 30
            feedback.append("Success: A new cost entry was found.")
            
            # Criterion 3: Correct Cost Type (15 pts)
            actual_type = entry_data.get("cost_type_id")
            if actual_type == expected_cost_type_id:
                score += 15
                feedback.append("Success: Correct Cost Type selected.")
            else:
                feedback.append(f"Fail: Incorrect Cost Type (Expected ID {expected_cost_type_id}, Got {actual_type}).")

            # Criterion 4: Correct Units (15 pts)
            units = entry_data.get("units", 0.0)
            if abs(units - 1.0) < 0.01:
                score += 15
                feedback.append("Success: Correct units (1.0).")
            else:
                feedback.append(f"Fail: Incorrect units. Expected 1.0, got {units}.")

            # Criterion 5: Comment Check (10 pts)
            comments = (entry_data.get("comments") or "").lower()
            if "invoice #9942" in comments:
                score += 10
                feedback.append("Success: Comment contains invoice number.")
            else:
                feedback.append("Fail: Comment does not contain 'invoice #9942'.")
        else:
            feedback.append("Fail: A cost entry exists, but it was created before the task started (stale data).")
    else:
        feedback.append("Fail: No cost entry found on the work package.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }