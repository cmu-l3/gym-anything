#!/usr/bin/env python3
"""
Verifier for develop_detection_test_framework task.
"""

import json
import os
import base64
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_develop_detection_test_framework(traj, env_info, task_info):
    """
    Verify the agent's detection validation script.
    
    Criteria:
    1. Script exists and was created during the task.
    2. Script contains correct expected Rule IDs (5710/5716, 5715, 5402).
    3. Script interacts with Docker/wazuh-logtest.
    4. Script executes successfully (exit code 0).
    5. Script output indicates passing tests.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback_parts = []
    
    # 1. Check script existence (10 pts)
    if not result.get("script_exists", False):
        return {"passed": False, "score": 0, "feedback": "Script file validate_detections.py not found"}
    
    score += 10
    feedback_parts.append("Script created")

    # Decode content
    try:
        content = base64.b64decode(result.get("script_content_b64", "")).decode('utf-8')
        stdout = base64.b64decode(result.get("stdout_b64", "")).decode('utf-8')
    except:
        content = ""
        stdout = ""

    # 2. Check for expected Rule IDs in code (30 pts)
    # SSH Invalid: 5710 or 5716
    # SSH Success: 5715
    # Sudo: 5402
    
    found_invalid = "5710" in content or "5716" in content
    found_ssh_succ = "5715" in content
    found_sudo = "5402" in content
    
    id_score = 0
    if found_invalid: id_score += 10
    if found_ssh_succ: id_score += 10
    if found_sudo: id_score += 10
    
    score += id_score
    if id_score == 30:
        feedback_parts.append("All expected Rule IDs found in code")
    else:
        feedback_parts.append(f"Some Rule IDs missing from code (Found: Invalid={found_invalid}, SSH={found_ssh_succ}, Sudo={found_sudo})")

    # 3. Check for Docker interaction logic (20 pts)
    # Look for 'docker exec' or 'subprocess' calling docker
    if "docker exec" in content and "wazuh-logtest" in content:
        score += 20
        feedback_parts.append("Correct Docker invocation logic found")
    else:
        feedback_parts.append("Missing or incorrect 'docker exec wazuh-logtest' logic")

    # 4. Check Parsing Logic (Static Analysis) (10 pts)
    # Look for common patterns to parse the output
    if re.search(r"(id|Rule id)['\"]?\s*:\s*['\"]?\d+", content) or "regex" in content.lower() or "json" in content.lower():
        score += 10
        feedback_parts.append("Output parsing logic detected")
    else:
        feedback_parts.append("Could not clearly identify parsing logic")

    # 5. Execution Success (30 pts)
    exec_success = result.get("execution_success", False)
    exit_code = result.get("exit_code", -1)
    
    if exec_success and exit_code == 0:
        # Check stdout for success indicators
        if "PASS" in stdout.upper() or "SUCCESS" in stdout.upper() or "OK" in stdout.upper():
            score += 30
            feedback_parts.append("Script executed successfully and passed tests")
        else:
            score += 15
            feedback_parts.append("Script ran (exit 0) but didn't print standard success message")
    else:
        feedback_parts.append(f"Script execution failed (Exit code: {exit_code})")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }