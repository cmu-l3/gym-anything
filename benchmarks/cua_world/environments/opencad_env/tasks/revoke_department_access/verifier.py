#!/usr/bin/env python3
"""Verifier for revoke_department_access task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_revoke_department_access(traj, env_info, task_info):
    """
    Verify that Police access was revoked for James Rodriguez while preserving Civilian access.
    
    Criteria:
    1. User 'James Rodriguez' must still exist (Prevent 'delete user' gaming).
    2. Police department association must be REMOVED (Count == 0).
    3. Civilian department association must be RETAINED (Count >= 1).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/revoke_department_access_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Criterion 1: User Integrity (20 pts)
    # The user account must still exist.
    if result.get('user_exists', False):
        score += 20
        feedback_parts.append("User account preserved")
    else:
        feedback_parts.append("CRITICAL FAIL: User account was deleted or not found")
        return {"passed": False, "score": 0, "feedback": ". ".join(feedback_parts)}
        
    # Criterion 2: Police Access Revoked (40 pts)
    # The record in user_departments for Police should be gone.
    police_count = int(result.get('police_access_count', 999))
    if police_count == 0:
        score += 40
        feedback_parts.append("Police department access successfully revoked")
    else:
        feedback_parts.append(f"FAIL: User still has access to Police department (Count: {police_count})")
        
    # Criterion 3: Civilian Access Preserved (30 pts)
    # The record in user_departments for Civilian should still exist.
    # This ensures the agent didn't just 'Select All -> Delete' or wipe the user's config.
    civilian_count = int(result.get('civilian_access_count', 0))
    if civilian_count > 0:
        score += 30
        feedback_parts.append("Civilian department access properly preserved")
    else:
        feedback_parts.append("FAIL: Civilian department access was incorrectly removed")
        
    # Criterion 4: Basic Workflow/App State (10 pts)
    # Implicitly checked if scores > 20 (meaning DB interactions happened), 
    # but explicitly checking app_running adds robustness.
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Application left in running state")
    else:
        feedback_parts.append("Application was closed")
        
    # Calculate Pass/Fail
    # Must have User + Revoked Police + Preserved Civilian to pass reliably.
    # Threshold 70 allows for minor issues but requires main objective.
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }