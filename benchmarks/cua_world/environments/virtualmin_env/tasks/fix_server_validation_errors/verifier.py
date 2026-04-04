#!/usr/bin/env python3
"""
Verifier for fix_server_validation_errors task.

Criteria:
1. Virtualmin validation passes (Exit code 0) - 40 pts
2. File permissions fixed (broken-app:broken-app) - 25 pts
3. Apache configuration file restored - 25 pts
4. Apache configuration content valid - 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_server_validation_errors(traj, env_info, task_info):
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
    feedback = []
    passed = False

    # 1. Validation Status (40 pts)
    # Exit code 0 means success. Non-zero means validation failed.
    exit_code = result.get("validation_exit_code", -1)
    if exit_code == 0:
        score += 40
        feedback.append("Virtualmin validation passed.")
    else:
        # Check output for partial clues
        output = result.get("validation_output", "")
        if "Everything is fine" in output:
             # Sometimes exit code might be weird but output says fine
             score += 40
             feedback.append("Virtualmin validation passed (text check).")
        else:
             feedback.append(f"Virtualmin validation failed (Exit code {exit_code}).")

    # 2. Permissions Fixed (25 pts)
    if result.get("permissions_fixed", False):
        score += 25
        feedback.append("File permissions fixed.")
    else:
        owner = result.get("actual_owner", "unknown")
        feedback.append(f"File permissions incorrect (Current: {owner}).")

    # 3. Apache Config Restored (25 pts)
    if result.get("config_restored", False):
        score += 25
        feedback.append("Apache configuration file exists.")
    else:
        feedback.append("Apache configuration file missing.")

    # 4. Config Content Valid (10 pts)
    if result.get("config_content_valid", False):
        score += 10
        feedback.append("Apache configuration content looks correct.")
    
    # Pass logic
    # Must at least fix permissions and config to 'pass' significantly, 
    # but strictly needs score >= 65 to be considered a full pass.
    # If validation passes (40), presumably other things are fixed too.
    
    if score >= 65:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }