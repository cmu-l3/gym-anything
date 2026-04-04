#!/usr/bin/env python3
"""Verifier for create_failsafe_mount_script task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_failsafe_mount_script(traj, env_info, task_info):
    """
    Verify the failsafe mount script task.
    
    Scoring Criteria:
    1. Script exists and is executable (10 pts)
    2. Positive Test: Script works, updates log, and dismounts cleanly (50 pts)
    3. Negative Test: Script dismounts cleanly even when an error occurs (40 pts)
    
    Pass Threshold: 70 pts (Must pass positive test and have some safety)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Basic script checks (10 pts)
    if result.get('script_exists') and result.get('is_executable'):
        score += 10
        feedback_parts.append("Script created and executable")
    elif result.get('script_exists'):
        score += 5
        feedback_parts.append("Script created but not executable")
    else:
        feedback_parts.append("Script not found")
        return {"passed": False, "score": 0, "feedback": "Script safe_log_entry.sh not found"}

    # 2. Positive Test (50 pts)
    # Breakdown: 30 for functionality (log updated), 20 for hygiene (dismounted)
    if result.get('positive_test_passed'):
        score += 50
        feedback_parts.append("Normal execution successful (log updated + clean dismount)")
    else:
        if result.get('log_updated'):
            score += 30
            feedback_parts.append("Log updated, but script failed or left volume mounted")
        else:
            feedback_parts.append("Script failed to update log file")

    # 3. Negative/Safety Test (40 pts)
    # This verifies the 'trap' functionality
    if result.get('negative_test_passed'):
        score += 40
        feedback_parts.append("Safety check passed: Volume dismounted after crash/error")
    else:
        # Partial credit if they at least wrote a trap command but it failed in practice
        if result.get('has_trap_command'):
            score += 10
            feedback_parts.append("Safety check failed: Volume left mounted after crash (Trap command detected but ineffective)")
        else:
            feedback_parts.append("Safety check failed: No error handling detected")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }