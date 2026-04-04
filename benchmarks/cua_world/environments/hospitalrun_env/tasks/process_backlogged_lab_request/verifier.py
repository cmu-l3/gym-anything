#!/usr/bin/env python3
"""
Verifier for process_backlogged_lab_request task.
Checks if the specific older lab request was completed while the newer one was left alone.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_backlogged_lab_request(traj, env_info, task_info):
    """
    Verifies the lab backlog task.
    
    Criteria:
    1. Target request (Old) must be 'Completed' (40 pts)
    2. Target request (Old) must have result 'Negative' (20 pts)
    3. Distractor request (New) must be 'Requested' (30 pts)
    4. Anti-gaming: No unexpected data loss (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Target (Old Request)
    target_status = result.get('target_status', '').strip()
    target_result = result.get('target_result', '').strip().lower()
    
    if target_status == "Completed":
        score += 40
        feedback_parts.append("Target request marked Completed.")
    else:
        feedback_parts.append(f"Target status is '{target_status}' (expected 'Completed').")

    if "negative" in target_result:
        score += 20
        feedback_parts.append("Target result correct.")
    else:
        feedback_parts.append(f"Target result is '{target_result}' (expected 'Negative').")

    # 2. Check Distractor (New Request)
    distractor_status = result.get('distractor_status', '').strip()
    
    if distractor_status == "Requested":
        score += 30
        feedback_parts.append("Distractor request correctly left untouched.")
    elif distractor_status == "Completed":
        # Major penalty for doing the wrong one
        score = max(0, score - 20) 
        feedback_parts.append("FAIL: You processed the NEW request instead of the old one!")
    else:
        feedback_parts.append(f"Distractor status changed to '{distractor_status}'.")

    # 3. Clean Execution Bonus
    if score >= 90:
        score += 10
        feedback_parts.append("Bonus: Clean execution.")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }