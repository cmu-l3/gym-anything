#!/usr/bin/env python3
"""
Verifier for restrict_analytics_db_user task.

Uses strict programmatic privilege simulation to guarantee that the Principle 
of Least Privilege was correctly implemented by the agent.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_analytics_db_user(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/restrict_user_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract test results
    user_exists = result.get("user_exists", False)
    auth_success = result.get("auth_success", False)
    read_success = result.get("read_success", False)
    write_denied = result.get("write_denied", False)
    create_denied = result.get("create_denied", False)
    grants = result.get("grants", [])

    if not user_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "User 'analytics_user'@'localhost' does not exist. The account was dropped entirely rather than restricted."
        }

    # CRITERION 1: Password Rotation (20 points)
    if auth_success:
        score += 20
        feedback_parts.append("Password updated to DataViz#2026 successfully")
    else:
        feedback_parts.append("Authentication failed with the requested new password")

    # CRITERION 2: Read Access Maintained (30 points)
    if read_success:
        score += 30
        feedback_parts.append("SELECT queries succeed")
    else:
        feedback_parts.append("SELECT queries failed (insufficient privileges or auth failure)")

    # CRITERION 3: Write Actions Denied (25 points)
    if write_denied and create_denied:
        score += 25
        feedback_parts.append("Write/Create actions are explicitly denied")
    else:
        feedback_parts.append("SECURITY VULNERABILITY: User can still write/create objects!")

    # CRITERION 4: Privileges Correct in SHOW GRANTS (25 points)
    grants_string = " ".join(grants).upper()
    has_all = "ALL PRIVILEGES" in grants_string
    has_select = "GRANT SELECT ON `SOCIOBOARD`.*" in grants_string or "GRANT SELECT ON `SOCIOBOARD`" in grants_string or "GRANT SELECT " in grants_string

    if not has_all and has_select:
        score += 25
        feedback_parts.append("Grants configured correctly (ALL removed, SELECT maintained)")
    elif has_all:
        feedback_parts.append("Grants still contain ALL PRIVILEGES")
    else:
        feedback_parts.append("Grants are misconfigured (Missing SELECT or badly scoped)")

    # CRITICAL SECURITY CHECK
    # This is a strict security task. If the user can still write or holds ALL privileges,
    # the security hole remains open, making the task an automatic failure.
    security_passed = write_denied and create_denied and not has_all

    passed = (score == 100) and security_passed

    if not security_passed:
        passed = False
        feedback_parts.append("[CRITICAL] Task failed due to open security vulnerabilities. Write/Admin access was not properly revoked.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }