#!/usr/bin/env python3
"""Verifier for audit_failed_login_attempt task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_failed_login_attempt(traj, env_info, task_info):
    """
    Verify that the agent identified the correct IP address of the failed login.
    
    Criteria:
    1. Result file 'suspicious_ip.txt' exists.
    2. File content matches the actual IP recorded in the database (Ground Truth).
    3. File was created during the task window (Anti-gaming).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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
    
    file_exists = result.get('file_exists', False)
    file_content = result.get('file_content', '')
    ground_truth_ip = result.get('ground_truth_ip', '')
    file_created_during_task = result.get('file_created_during_task', False)

    # Criterion 1: File Existence (20 points)
    if file_exists:
        score += 20
        feedback_parts.append("File 'suspicious_ip.txt' found")
    else:
        feedback_parts.append("File 'suspicious_ip.txt' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Content Match (60 points)
    # Note: ground_truth_ip might be empty if setup failed, handle that gracefully
    if not ground_truth_ip:
        return {"passed": False, "score": 0, "feedback": "Setup Error: Ground truth IP was not recorded."}

    if file_content == ground_truth_ip:
        score += 60
        feedback_parts.append(f"IP Address matches ground truth ({ground_truth_ip})")
    else:
        feedback_parts.append(f"IP Address incorrect. Expected '{ground_truth_ip}', got '{file_content}'")

    # Criterion 3: Anti-gaming Timestamp (20 points)
    if file_created_during_task:
        score += 20
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File timestamp is older than task start (pre-existing or stale)")

    # Pass Threshold
    # Must have correct IP and valid timestamp
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }