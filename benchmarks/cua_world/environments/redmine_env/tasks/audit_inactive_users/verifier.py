#!/usr/bin/env python3
"""
Verifier for audit_inactive_users task.
Verifies that specific users are locked/active based on their last login date.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_inactive_users(traj, env_info, task_info):
    """
    Verify that:
    1. Users active before 2026-01-01 are LOCKED (Status 3).
    2. Users active on/after 2026-01-01 are ACTIVE (Status 1).
    3. Admin is ACTIVE (Status 1).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    users_data = result.get('users', [])
    user_map = {u['login']: u for u in users_data}

    # Task Metadata
    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])      # Should be Locked
    safe_users = metadata.get('safe_users', []) # Should be Active
    
    score = 0
    max_score = 100
    feedback_parts = []
    failed = False

    # Status constants: 1 = Active, 3 = Locked
    STATUS_ACTIVE = 1
    STATUS_LOCKED = 3

    # 1. Check TARGETS (Should be Locked)
    # Weight: 50 points total (split evenly)
    target_points = 50 / len(targets) if targets else 0
    
    for target in targets:
        login = target['login']
        user_rec = user_map.get(login)
        
        if not user_rec:
            feedback_parts.append(f"User {login} not found in DB")
            failed = True
            continue
            
        if user_rec['status'] == STATUS_LOCKED:
            score += target_points
            feedback_parts.append(f"[PASS] {login} is Locked")
        else:
            feedback_parts.append(f"[FAIL] {login} is NOT Locked (Status: {user_rec['status']})")
            failed = True

    # 2. Check SAFE USERS (Should be Active)
    # Weight: 50 points total (split evenly)
    safe_points = 50 / len(safe_users) if safe_users else 0
    
    for safe in safe_users:
        login = safe['login']
        user_rec = user_map.get(login)
        
        if not user_rec:
            feedback_parts.append(f"User {login} not found in DB")
            failed = True
            continue
            
        if user_rec['status'] == STATUS_ACTIVE:
            score += safe_points
            feedback_parts.append(f"[PASS] {login} is Active")
        else:
            feedback_parts.append(f"[FAIL] {login} was incorrectly Locked (Status: {user_rec['status']})")
            failed = True

    # 3. Anti-Gaming Check: Ensure 'updated_on' timestamp is recent for locked users
    # If a user is locked, it should have been updated AFTER task start
    task_start = result.get('task_start', 0)
    for target in targets:
        login = target['login']
        user_rec = user_map.get(login)
        if user_rec and user_rec['status'] == STATUS_LOCKED:
            # Check if update happened during task
            # Allow slight clock skew, but updated_on should be > task_start
            if user_rec.get('updated_on', 0) < task_start:
                feedback_parts.append(f"[WARN] {login} was already locked before task?")
                # We don't necessarily penalize here as setup script resets them to Active,
                # so if they are Locked now, the agent must have done it.
                # If setup failed to reset, this would catch it.

    final_score = round(score)
    is_passed = (final_score >= 100) and not failed
    
    return {
        "passed": is_passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }