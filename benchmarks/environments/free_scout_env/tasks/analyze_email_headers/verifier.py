#!/usr/bin/env python3
"""
Verifier for analyze_email_headers task.

Verifies:
1. Submission file exists (/home/ga/submission/suspect_ip.txt)
2. File was created during the task.
3. Content of the file matches the dynamically generated IP in ground truth.
4. Agent used the application (Firefox running).
"""

import json
import tempfile
import os
import re

def verify_analyze_email_headers(traj, env_info, task_info):
    """
    Verify that the agent correctly identified the X-Originating-IP.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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
    
    # Check 1: Submission exists (20 pts)
    submission_exists = result.get('submission_exists', False)
    if submission_exists:
        score += 20
        feedback_parts.append("Submission file exists")
    else:
        feedback_parts.append("Submission file NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check 2: Content matches ground truth (60 pts)
    # Using strict matching but allowing for whitespace stripping
    submitted_ip = result.get('submission_content', '').strip()
    ground_truth_ip = result.get('ground_truth_value', '').strip()
    
    # Basic IP validation regex
    ip_pattern = r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"
    
    if not submitted_ip:
        feedback_parts.append("Submission file is empty")
    elif submitted_ip == ground_truth_ip:
        score += 60
        feedback_parts.append(f"IP address matches ({submitted_ip})")
    elif ground_truth_ip in submitted_ip:
        # Partial credit if they pasted the whole header line instead of just IP
        score += 30
        feedback_parts.append(f"IP found but file contains extra text (expected exactly '{ground_truth_ip}')")
    else:
        feedback_parts.append(f"IP mismatch: submitted '{submitted_ip}', expected '{ground_truth_ip}'")

    # Check 3: File created during task (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp indicates pre-task creation (or file not modified)")

    # Check 4: App running (10 pts)
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("Application active")
    else:
        feedback_parts.append("Application not running")

    # Pass logic: Must have exact or close match and file must exist
    passed = (score >= 80) and submission_exists and (ground_truth_ip in submitted_ip)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }