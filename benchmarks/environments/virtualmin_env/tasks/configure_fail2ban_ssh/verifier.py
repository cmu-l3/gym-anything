#!/usr/bin/env python3
"""
Verifier for configure_fail2ban_ssh task.
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fail2ban_ssh(traj, env_info, task_info):
    """
    Verifies that Fail2Ban is configured correctly for SSH.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_retry = metadata.get('expected_max_retry', 3)
    expected_ban = metadata.get('expected_ban_time', 7200)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract results
    service_active = result.get('service_active', False)
    jail_active = result.get('jail_active', False)
    # Convert to int, handling potential strings
    try:
        runtime_retry = int(result.get('runtime_max_retry', 0))
        runtime_ban = int(result.get('runtime_ban_time', 0))
    except ValueError:
        runtime_retry = 0
        runtime_ban = 0

    config_b64 = result.get('config_file_b64', "")

    # Scoring
    score = 0
    feedback_parts = []

    # Criterion 1: Service Running (20 pts)
    if service_active:
        score += 20
        feedback_parts.append("Fail2Ban service is running")
    else:
        feedback_parts.append("Fail2Ban service is NOT running")

    # Criterion 2: SSH Jail Active (20 pts)
    if jail_active:
        score += 20
        feedback_parts.append("SSH jail is active")
    else:
        feedback_parts.append("SSH jail is NOT active")

    # Criterion 3: Max Retries (30 pts)
    if runtime_retry == expected_retry:
        score += 30
        feedback_parts.append(f"Max retries correctly set to {expected_retry}")
    else:
        feedback_parts.append(f"Max retries is {runtime_retry} (expected {expected_retry})")

    # Criterion 4: Ban Time (30 pts)
    if runtime_ban == expected_ban:
        score += 30
        feedback_parts.append(f"Ban time correctly set to {expected_ban}")
    else:
        feedback_parts.append(f"Ban time is {runtime_ban} (expected {expected_ban})")

    # Partial Credit Check via Config File (Fallback)
    # If service wasn't running but config looked correct in the file, give some points.
    # This handles cases where agent edited file correctly but forgot to restart.
    if not service_active or not jail_active:
        try:
            config_content = base64.b64decode(config_b64).decode('utf-8', errors='ignore')
            # Simple substring check - not perfect but good fallback
            if f"maxretry = {expected_retry}" in config_content or f"maxretry={expected_retry}" in config_content:
                if runtime_retry != expected_retry: # Don't double count
                    score += 10
                    feedback_parts.append("Config file has correct retry (service not updated)")
            if f"bantime = {expected_ban}" in config_content or f"bantime={expected_ban}" in config_content:
                if runtime_ban != expected_ban: # Don't double count
                    score += 10
                    feedback_parts.append("Config file has correct bantime (service not updated)")
        except Exception:
            pass

    # Pass Threshold
    # Must have service running OR perfect config file, but ideally service running.
    # Strict pass: Service must be running and values correct.
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }