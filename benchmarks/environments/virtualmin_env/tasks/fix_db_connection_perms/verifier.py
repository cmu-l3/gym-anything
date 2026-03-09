#!/usr/bin/env python3
"""
Verifier for fix_db_connection_perms task.

Checks:
1. File permissions of db_config.php are 644 (Secure).
2. File content contains the correct database password.
3. The status page loads (HTTP 200) and displays "System Operational".
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_db_connection_perms(traj, env_info, task_info):
    """
    Verify the agent fixed the database connection and permissions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    # Scoring Variables
    score = 0
    feedback_parts = []
    
    # 1. Check Permissions (30 pts)
    # Expected: 644
    perms = str(result.get('file_perms', '000'))
    if perms == '644':
        score += 30
        feedback_parts.append("Permissions fixed (644)")
    elif perms == '777':
        feedback_parts.append("Permissions still insecure (777)")
    else:
        feedback_parts.append(f"Permissions incorrect ({perms})")

    # 2. Check Password in File (30 pts)
    if result.get('password_correct', False):
        score += 30
        feedback_parts.append("Password updated in config")
    else:
        feedback_parts.append("Wrong password in config")

    # 3. Check Site Load (HTTP 200) (30 pts)
    http_code = int(result.get('http_code', 0))
    if http_code == 200:
        score += 30
        feedback_parts.append("Site loads (HTTP 200)")
    elif http_code == 500:
        feedback_parts.append("Site error (HTTP 500) - check permissions")
    else:
        feedback_parts.append(f"Site failed to load (HTTP {http_code})")

    # 4. Check Site Content (10 pts)
    if result.get('site_operational', False):
        score += 10
        feedback_parts.append("DB connected successfully")
    else:
        feedback_parts.append("Status message not found")

    # Pass Threshold
    # Must fix permissions AND password (which usually implies site works)
    passed = score >= 70 and perms == '644' and result.get('password_correct', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }