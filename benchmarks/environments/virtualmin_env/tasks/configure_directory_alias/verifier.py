#!/usr/bin/env python3
"""
Verifier for configure_directory_alias task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_directory_alias(traj, env_info, task_info):
    """
    Verify that the directory alias was configured correctly.
    
    Criteria:
    1. HTTP request to alias URL returns 200 OK (40 pts)
    2. HTTP response body contains expected content (10 pts)
    3. Apache config contains correct 'Alias' directive (30 pts)
    4. Apache config was modified during task (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # 1. HTTP Status Check (40 pts)
    http_code = result.get('http_code', 0)
    if http_code == 200:
        score += 40
        feedback_parts.append("HTTP access successful (200 OK)")
    elif http_code in [301, 302]:
        feedback_parts.append(f"HTTP check returned redirect ({http_code}) - Alias expected, not Redirect")
    elif http_code == 404:
        feedback_parts.append("HTTP check returned 404 Not Found")
    else:
        feedback_parts.append(f"HTTP check failed (Code: {http_code})")

    # 2. Content Check (10 pts)
    if result.get('content_match', False):
        score += 10
        feedback_parts.append("Content verified")
    elif http_code == 200:
        feedback_parts.append("Content mismatch - wrong file served?")

    # 3. Apache Config Check (30 pts)
    if result.get('alias_found_in_config', False):
        score += 30
        feedback_parts.append("Alias directive found in Apache config")
    else:
        feedback_parts.append("Alias directive NOT found in Apache config")
        if result.get('redirect_found_in_config', False):
            feedback_parts.append("(Found Redirect directive instead - incorrect for this task)")

    # 4. Anti-gaming / Config Modification (20 pts)
    if result.get('config_modified_during_task', False):
        score += 20
        feedback_parts.append("Configuration modified during task")
    else:
        feedback_parts.append("Configuration not modified")

    # Pass threshold
    # Must have at least working HTTP access (indicating success even if config parsing failed)
    # OR perfect config setup.
    passed = score >= 70 and (http_code == 200)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }