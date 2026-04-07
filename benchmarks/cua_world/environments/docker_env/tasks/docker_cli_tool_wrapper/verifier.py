#!/usr/bin/env python3
"""
Verifier for docker_cli_tool_wrapper task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_wrapper_script(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Read result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()
        
        try:
            copy_from_env("/tmp/wrapper_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback = []

    # 1. Permission Safety (30 points) - CRITICAL
    # We check if the file created by the tool is owned by the host user
    if result.get("permissions_correct", 0):
        score += 30
        feedback.append("Permissions correct: Generated files owned by host user.")
    elif result.get("runs_successfully", 0):
        feedback.append("Permissions INCORRECT: Generated files are likely owned by root (did you use --user?).")
    else:
        feedback.append("Permissions check skipped (script didn't run).")

    # 2. Connectivity (20 points)
    if result.get("net_connected", 0):
        score += 20
        feedback.append("Connectivity verified: Tool reached DB.")
    elif result.get("runs_successfully", 0):
        feedback.append("Connectivity failed: Tool could not resolve DB host.")

    # 3. I/O Integration (15 points) - Verified via static vol check + file creation
    # If the file was created (implied by permissions check logic) and vol flag used
    if result.get("static_vol", 0) and (result.get("permissions_correct", 0) or os.path.exists("/home/ga/projects/myapp/report.log")):
        # Note: verifier runs on host, can't check file existence directly, relying on export script logic
        # export script sets permissions_correct only if file exists
        # so we trust static_vol + runs_successfully
        if result.get("runs_successfully", 0):
            score += 15
            feedback.append("Volume mounting works.")
    elif result.get("static_vol", 0):
        score += 5
        feedback.append("Volume flag present but verification incomplete.")
    else:
        feedback.append("Volume mounting missing.")

    # 4. Argument Passing (15 points)
    if result.get("args_passed", 0):
        score += 15
        feedback.append("Arguments passed correctly.")
    elif result.get("static_arg_array", 0):
        score += 10 # Used "$@" but maybe run failed
        feedback.append("Argument array syntax used.")
    else:
        feedback.append("Arguments not passed correctly.")

    # 5. Cleanup (10 points)
    if result.get("static_cleanup", 0):
        score += 10
        feedback.append("Cleanup (--rm) enabled.")
    
    # 6. Environment (10 points)
    if result.get("env_passed", 0):
        score += 10
        feedback.append("Environment variable DB_HOST passed.")

    passed = score >= 70 and result.get("permissions_correct", 0) and result.get("net_connected", 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }