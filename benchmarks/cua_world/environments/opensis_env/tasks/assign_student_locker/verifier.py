#!/usr/bin/env python3
import json
import os
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_student_locker(traj, env_info, task_info):
    """
    Verify that the agent assigned locker '555' to Kenny McCormick.
    """
    # 1. Retrieve result data from the container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate criteria
    student_found = result.get('student_found', False)
    locker_value = result.get('locker_value', '')
    
    # Handle None/Null from JSON
    if locker_value is None:
        locker_value = ""
    locker_value = str(locker_value).strip()

    target_locker = task_info['metadata'].get('target_locker_number', '555')
    
    score = 0
    feedback = []

    # Criterion A: Student Record Exists (20 pts)
    if student_found:
        score += 20
        feedback.append("Target student record found in database.")
    else:
        feedback.append("FAIL: Target student 'Kenny McCormick' not found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion B: Locker Value Correct (80 pts)
    # We allow exact match
    if locker_value == target_locker:
        score += 80
        feedback.append(f"SUCCESS: Locker number is correctly set to '{target_locker}'.")
    else:
        if locker_value == "":
            feedback.append("FAIL: Locker number is empty.")
        else:
            feedback.append(f"FAIL: Locker number is '{locker_value}', expected '{target_locker}'.")

    # Anti-gaming check (Implicit):
    # setup_task.sh cleared this field. If it matches now, the agent (or a ghost) updated it.
    # We assume no ghosts.

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }