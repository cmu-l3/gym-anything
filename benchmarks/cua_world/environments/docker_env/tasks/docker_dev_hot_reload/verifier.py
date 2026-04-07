#!/usr/bin/env python3
"""
Verifier for docker_dev_hot_reload task.

Criteria:
1. Immutability: docker-compose.yml must not be modified (20 pts)
2. Override: docker-compose.override.yml must exist (20 pts)
3. Configuration:
   - Port 5000 exposed (10 pts)
   - Volume mounted (15 pts)
   - FLASK_DEBUG=1 set (10 pts)
4. Functional: Hot reload works without container restart (25 pts)

Pass Threshold: 75 pts
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_dev_hot_reload(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Immutability (20 pts)
    if result.get("immutable_check", False):
        score += 20
        feedback_parts.append("Original compose file unmodified (+20)")
    else:
        feedback_parts.append("FAIL: Original docker-compose.yml was modified")

    # 2. Override Existence (20 pts)
    if result.get("override_exists", False):
        score += 20
        feedback_parts.append("Override file created (+20)")
    else:
        feedback_parts.append("FAIL: docker-compose.override.yml not found")

    # 3. Configuration Checks
    
    # Port Exposure (10 pts)
    if result.get("port_exposed", False):
        score += 10
        feedback_parts.append("Port 5000 exposed (+10)")
    else:
        feedback_parts.append("FAIL: Port 5000 not exposed")

    # Volume Mount (15 pts)
    if result.get("has_mount", False):
        score += 15
        feedback_parts.append("Code volume mounted (+15)")
    else:
        feedback_parts.append("FAIL: Local ./app not mounted to /app")

    # Debug Mode (10 pts)
    if result.get("env_has_debug", False) and result.get("cmd_is_flask", False):
        score += 10
        feedback_parts.append("Debug mode/Flask command set (+10)")
    else:
        feedback_parts.append("FAIL: FLASK_DEBUG not set or wrong command")

    # 4. Functional Hot Reload (25 pts)
    if result.get("hot_reload_success", False):
        score += 25
        feedback_parts.append("Hot reload verified (+25)")
    else:
        if result.get("hot_reload_restarted", False):
            feedback_parts.append("FAIL: Container restarted during update (not hot reload)")
        else:
            feedback_parts.append("FAIL: Code change did not update API response")

    # Final tally
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }