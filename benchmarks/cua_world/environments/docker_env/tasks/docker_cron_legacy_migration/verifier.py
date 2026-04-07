#!/usr/bin/env python3
"""
Verifier for docker_cron_legacy_migration task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_cron_legacy_migration(traj, env_info, task_info):
    """
    Verifies that the user successfully containerized a cron-based application.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Image Build (20 pts)
    if result.get('image_exists'):
        if result.get('image_created_after_start'):
            score += 20
            feedback.append("Image legacy-etl:latest built successfully (+20)")
        else:
            score += 10
            feedback.append("Image exists but wasn't rebuilt during task (+10)")
    else:
        feedback.append("Image legacy-etl:latest not found (0/20)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Container Stability (20 pts)
    if result.get('container_kept_running'):
        score += 20
        feedback.append("Container stays running (+20)")
    else:
        feedback.append("Container exited immediately (0/20)")

    # 3. Cron Process (15 pts)
    if result.get('cron_process_found'):
        score += 15
        feedback.append("Cron process detected (+15)")
    else:
        feedback.append("Cron process not found (running python directly?) (0/15)")

    # 4. Logs Visibility (Redirection) (25 pts)
    if result.get('logs_found'):
        score += 25
        feedback.append("Cron logs visible in docker logs (+25)")
    else:
        feedback.append("No cron output found in docker logs (redirection missing?) (0/25)")

    # 5. Environment Variable Propagation (20 pts)
    if result.get('env_vars_visible'):
        score += 20
        feedback.append("Environment variables successfully passed to cron (+20)")
    else:
        feedback.append("Environment variables NOT visible to cron job (UNSET) (0/20)")

    # Pass Threshold: 80 points
    # Requires getting most things right (especially redirection + env vars)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }