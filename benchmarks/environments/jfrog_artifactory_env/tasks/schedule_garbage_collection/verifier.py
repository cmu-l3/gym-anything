#!/usr/bin/env python3
"""
Verifier for schedule_garbage_collection task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_garbage_collection(traj, env_info, task_info):
    """
    Verify that the Garbage Collection cron expression was updated to the target value.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON
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

    initial_cron = result.get('initial_cron', 'UNKNOWN')
    final_cron = result.get('final_cron', 'NOT_FOUND')
    
    # Metadata target
    target_cron = task_info.get('metadata', {}).get('target_cron', '0 0 2 ? * SUN')

    score = 0
    feedback_parts = []
    
    # CRITERION 1: Value changed (Anti-gaming) - 40 pts
    if initial_cron != final_cron and final_cron != "NOT_FOUND":
        score += 40
        feedback_parts.append("Configuration was modified")
    elif initial_cron == final_cron:
        feedback_parts.append("Configuration was NOT modified")
    else:
        feedback_parts.append("Could not determine configuration state")

    # CRITERION 2: Correct Value - 60 pts
    # Allow loose matching on spacing if necessary, though Cron usually strict
    if final_cron.strip() == target_cron.strip():
        score += 60
        feedback_parts.append(f"Correct cron expression set: '{final_cron}'")
    else:
        feedback_parts.append(f"Incorrect cron expression. Expected: '{target_cron}', Got: '{final_cron}'")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }