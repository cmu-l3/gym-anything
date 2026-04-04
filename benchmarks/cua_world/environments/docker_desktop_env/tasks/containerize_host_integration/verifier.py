#!/usr/bin/env python3
"""
Verifier for containerize_host_integration task.

Scoring Criteria:
1. Frontend container is running (20 pts)
2. Application source code was NOT modified (20 pts)
3. Docker Compose file WAS modified (10 pts)
4. ExtraHosts configuration detected in container inspection (20 pts)
5. End-to-end connectivity: Frontend returns success response from backend (30 pts)

Pass Threshold: 80/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_containerize_host_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Container Running (20 pts)
    if result.get("container_running", False):
        score += 20
        feedback_parts.append("Frontend container is running (+20)")
    else:
        feedback_parts.append("Frontend container NOT running (0)")

    # 2. Code Integrity (20 pts)
    # The user should NOT modify app.py to change the hostname
    if not result.get("code_modified", True):
        score += 20
        feedback_parts.append("Source code integrity maintained (+20)")
    else:
        feedback_parts.append("Source code was modified (0) - Task constraint violation")

    # 3. Compose Modified (10 pts)
    if result.get("compose_modified", False):
        score += 10
        feedback_parts.append("Docker Compose file updated (+10)")
    else:
        feedback_parts.append("Docker Compose file not modified (0)")

    # 4. Configuration Check (20 pts)
    if result.get("extra_hosts_configured", False):
        score += 20
        feedback_parts.append("ExtraHosts configuration detected (+20)")
    else:
        feedback_parts.append("ExtraHosts configuration NOT found in container inspection (0)")

    # 5. End-to-End Connectivity (30 pts)
    # Check if the frontend actually reached the backend
    response_body = result.get("frontend_response_body", "")
    try:
        # response_body is a string, we might need to parse it if it was stringified json
        # In export_result.sh we used jq -R ., so it's a string containing the raw curl output
        if "Legacy Core Online" in response_body and '"status": "connected"' in response_body:
            score += 30
            feedback_parts.append("End-to-end connectivity verified (+30)")
        elif "Legacy Core Online" in response_body:
            score += 20
            feedback_parts.append("Partial connectivity verification (+20)")
        else:
            feedback_parts.append("Connectivity test failed - Backend response not found in frontend output (0)")
    except Exception:
        feedback_parts.append("Error parsing response body (0)")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }