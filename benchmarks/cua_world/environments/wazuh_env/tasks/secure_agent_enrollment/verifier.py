#!/usr/bin/env python3
"""
Verifier for secure_agent_enrollment task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_agent_enrollment(traj, env_info, task_info):
    """
    Verify the Wazuh agent enrollment security configuration.
    
    Criteria:
    1. Password File Created (20 pts)
    2. Secure Permissions (15 pts)
    3. Config: Use Password (20 pts)
    4. Config: Force Insert (15 pts)
    5. Service Running (15 pts)
    6. Auth Enforced (Network check) (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    feedback_parts = []
    
    # 1. Password File Existence & Content (20 pts)
    if result.get("pass_file_exists", False):
        if result.get("pass_content_match", False):
            score += 20
            feedback_parts.append("Password file correct")
        else:
            score += 10
            feedback_parts.append("Password file exists but wrong content")
    else:
        feedback_parts.append("Password file missing")

    # 2. Secure Permissions (15 pts)
    # Owner should be wazuh (or root if group is wazuh)
    # Perms should be 640 or 600
    owner = result.get("pass_file_owner", "")
    group = result.get("pass_file_group", "")
    perms = result.get("pass_file_perms", "")
    
    perms_ok = perms in ["640", "600", "440", "400"]
    owner_ok = (owner == "wazuh" or group == "wazuh") or (owner == "root" and group == "wazuh")
    
    if result.get("pass_file_exists", False):
        if perms_ok and owner_ok:
            score += 15
            feedback_parts.append(f"Permissions secure ({perms} {owner}:{group})")
        else:
            feedback_parts.append(f"Insecure permissions/owner ({perms} {owner}:{group})")

    # 3. Config: Use Password (20 pts)
    if result.get("config_use_password", False):
        score += 20
        feedback_parts.append("use_password enabled")
    else:
        feedback_parts.append("use_password NOT enabled")

    # 4. Config: Force Insert (15 pts)
    if result.get("config_force_insert", False):
        score += 15
        feedback_parts.append("force_insert enabled")
    else:
        feedback_parts.append("force_insert NOT enabled")

    # 5. Service Running (15 pts)
    # The user must have restarted the service for changes to take effect
    if result.get("service_running", False):
        score += 15
        feedback_parts.append("Authd service running")
    else:
        feedback_parts.append("Authd service NOT running")

    # 6. Network Check (15 pts)
    # If config is right and service running, we assume it's enforced.
    # The export script checks if port 1515 is open.
    if result.get("port_open", False) and result.get("service_running", False):
        score += 15
        feedback_parts.append("Port 1515 active")
    elif not result.get("port_open", False):
        feedback_parts.append("Port 1515 unreachable")

    # Threshold
    passed = score >= 70 and result.get("pass_file_exists", False) and result.get("service_running", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }