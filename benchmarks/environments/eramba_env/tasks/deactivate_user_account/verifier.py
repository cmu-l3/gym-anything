#!/usr/bin/env python3
"""
Verifier for deactivate_user_account task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_user_account(traj, env_info, task_info):
    """
    Verify that user 'amorgan' was deactivated and name updated.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    # 1. User Existence Check (CRITICAL)
    if not result.get('user_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User 'amorgan' not found in database. The record may have been deleted instead of deactivated."
        }
    
    score += 10
    feedback_parts.append("User record exists")

    # 2. Status Check (40 pts)
    # Active should be 0 (False)
    # MySQL typically returns '0' for boolean false, or 0 integer
    db_active = str(result.get('user_active', '1')).strip()
    
    if db_active == '0':
        score += 40
        feedback_parts.append("User successfully deactivated")
    else:
        feedback_parts.append(f"User is still Active (status={db_active})")

    # 3. Name Update Check (30 pts)
    # Name should contain "(CONTRACT ENDED)"
    db_name = result.get('user_name', '')
    expected_suffix = "(CONTRACT ENDED)"
    
    if expected_suffix in db_name:
        score += 30
        feedback_parts.append("Name updated with contract status")
        
        # Bonus check: First name preservation
        if db_name.startswith("Alex"):
            score += 10
            feedback_parts.append("First name preserved")
        else:
            feedback_parts.append("Warning: First name changed")
    else:
        feedback_parts.append(f"Name does not contain '{expected_suffix}' (Current: '{db_name}')")

    # 4. Anti-Gaming / Timestamp Check (10 pts)
    task_start = int(result.get('task_start', 0))
    modified_ts = int(result.get('record_modified_ts', 0))
    
    if modified_ts > task_start:
        score += 10
        feedback_parts.append("Record modified during task")
    else:
        # If user deactivated correctly but timestamp is old, something is wrong (or stale data)
        if db_active == '0':
            feedback_parts.append("Warning: Record not modified during task session (stale?)")
        else:
            feedback_parts.append("Record not modified")

    # Final Evaluation
    passed = (db_active == '0') and (expected_suffix in db_name) and (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }