#!/usr/bin/env python3
"""
Verifier for create_cleanup_command task.

Criteria:
1. File Creation (30 pts):
   - `registry/management/commands/close_expired_plans.py` exists
   - `__init__.py` exists in the commands directory
   - Created during task session
2. Functional Correctness (50 pts):
   - Expired Active plan -> Closed
   - Future Active plan -> Active (NOT changed)
   - Expired Closed plan -> Closed (NOT changed)
3. Code Quality / Validity (20 pts):
   - File size > 100 bytes (not empty)
   - No DB errors during check
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cleanup_command(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence & Structure (30 pts)
    if result.get('file_exists'):
        score += 15
        feedback.append("Command file created.")
        
        if result.get('file_created_during_task'):
            score += 5
            feedback.append("File created during session.")
        else:
            feedback.append("File timestamp predates task (reused?).")
            
        if result.get('init_exists'):
            score += 10
            feedback.append("__init__.py structure correct.")
        else:
            feedback.append("Missing __init__.py in commands directory.")
            
        if result.get('file_size', 0) > 100:
            # Part of code quality, giving it here
            pass
        else:
            feedback.append("File seems too small/empty.")
    else:
        feedback.append("Command file NOT found.")

    # 2. Logic Verification (50 pts)
    canaries = result.get('canary_states', {})
    db_error = result.get('db_error')
    
    if db_error:
        feedback.append(f"DB Check Failed: {db_error}")
    elif not canaries:
        feedback.append("No canary data found.")
    else:
        # Check Expired Active -> Closed
        s1 = canaries.get('expired_active_status')
        if s1 == 'Closed':
            score += 30
            feedback.append("Successfully closed expired plan.")
        else:
            feedback.append(f"Failed to close expired plan (Status: {s1}).")

        # Check Future Active -> Active
        s2 = canaries.get('future_active_status')
        if s2 == 'Active':
            score += 10
            feedback.append("Correctly ignored future plan.")
        else:
            feedback.append(f"Incorrectly modified future plan (Status: {s2}).")

        # Check Expired Closed -> Closed
        s3 = canaries.get('expired_closed_status')
        if s3 == 'Closed':
            score += 10
            feedback.append("Correctly ignored already closed plan.")
        else:
            feedback.append(f"Incorrectly modified closed plan (Status: {s3}).")

    # 3. Final Quality Check (20 pts)
    # If file exists and reasonable size
    if result.get('file_exists') and result.get('file_size', 0) > 100:
        score += 20
        feedback.append("File size validity check passed.")

    # Determine pass/fail
    # Must have created file AND successfully closed the expired plan
    passed = (result.get('file_exists') and 
              canaries.get('expired_active_status') == 'Closed')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }