#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_smart_home_hub(traj, env_info, task_info):
    """
    Verify the fix_smart_home_hub task.
    
    Criteria:
    1. Bug 1 Fixed (Async blocking): 35 pts
    2. Bug 2 Fixed (Logic error): 35 pts
    3. Bug 3 Fixed (Schema error): 30 pts
    
    Pass threshold: 100/100 (All critical bugs must be fixed).
    """
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
    feedback = []
    
    # Evaluate Bug 1
    if result.get("bug1_fixed"):
        score += 35
        feedback.append("Bug 1 (Async Blocking) Fixed")
    else:
        feedback.append("Bug 1 Failed: Event loop still blocks or test failed")

    # Evaluate Bug 2
    if result.get("bug2_fixed"):
        score += 35
        feedback.append("Bug 2 (Logic Error) Fixed")
    else:
        feedback.append("Bug 2 Failed: Logic error in trigger evaluation persists")

    # Evaluate Bug 3
    if result.get("bug3_fixed"):
        score += 30
        feedback.append("Bug 3 (Schema Mismatch) Fixed")
    else:
        feedback.append("Bug 3 Failed: Device state not updating correctly")

    # Overall Status
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback)
    }