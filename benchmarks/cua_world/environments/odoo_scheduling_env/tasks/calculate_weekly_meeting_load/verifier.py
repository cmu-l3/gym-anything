#!/usr/bin/env python3
"""
Verifier for calculate_weekly_meeting_load task.

Criteria:
1. File /home/ga/alice_load.txt exists (20 pts)
2. File was created after task start (10 pts)
3. Content is a valid number (10 pts)
4. Value matches Ground Truth (calculated from DB) +/- 0.1 tolerance (60 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_weekly_meeting_load(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    if result.get("output_exists", False):
        score += 20
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Anti-gaming / Freshness (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File creation timestamp predates task")

    # 3. Numeric Validity (10 pts)
    user_val_raw = result.get("user_value_raw", "")
    user_float = None
    try:
        user_float = float(user_val_raw)
        score += 10
    except ValueError:
        feedback_parts.append(f"Content '{user_val_raw}' is not a valid number")

    # 4. Accuracy (60 pts)
    gt_data = result.get("ground_truth", {})
    if gt_data.get("error"):
        return {"passed": False, "score": score, "feedback": f"Ground truth calculation failed: {gt_data['error']}"}
    
    ground_truth = gt_data.get("ground_truth_hours", 0.0)
    
    if user_float is not None:
        diff = abs(user_float - ground_truth)
        tolerance = 0.1
        
        if diff <= tolerance:
            score += 60
            feedback_parts.append(f"Calculation correct (Agent: {user_float}, GT: {ground_truth})")
        else:
            feedback_parts.append(f"Calculation incorrect (Agent: {user_float}, GT: {ground_truth})")
    
    # Final Pass Decision
    passed = (score >= 90) # Requires accuracy + file existence + numeric format
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "agent_value": user_float,
            "ground_truth": ground_truth,
            "events_included": gt_data.get("events_found", [])
        }
    }