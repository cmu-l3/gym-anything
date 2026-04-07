#!/usr/bin/env python3
"""
Verifier for docker_cron_observability task.

Scoring (100 points):
  - Logs Visible (40 pts): Docker logs show the script output (stdout/stderr redirection).
  - Execution Success (40 pts): The script actually ran and used the API_KEY (marker file exists).
  - No Hardcoding (10 pts): The API key wasn't hardcoded in the script/crontab.
  - Container/Cron Health (10 pts): Container is running and cron process is active.

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 80

def verify_docker_cron_observability(traj, env_info, task_info):
    """Verify that the cron job is fixed, logging correctly, and secure."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/cron_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract results
    container_running = result.get("container_running", 0)
    logs_visible = result.get("logs_visible_in_docker", 0)
    execution_success = result.get("script_execution_success", 0)
    hardcoded = result.get("hardcoded_key_detected", 0)
    cron_running = result.get("cron_process_running", 0)

    # 1. Logs Visible (40 pts)
    # This proves they redirected stdout/stderr to /proc/1/fd/1 or similar
    if logs_visible:
        score += 40
        feedback_parts.append("Logs successfully redirected to Docker (+40)")
    else:
        feedback_parts.append("No logs found in 'docker logs' (0/40)")

    # 2. Execution Success (40 pts)
    # This proves they fixed the environment variable inheritance
    if execution_success:
        score += 40
        feedback_parts.append("Backup script executed successfully with valid API_KEY (+40)")
    else:
        feedback_parts.append("Backup script did not run successfully or Auth failed (0/40)")

    # 3. No Hardcoding (10 pts)
    if execution_success: # Only check this if they actually succeeded
        if not hardcoded:
            score += 10
            feedback_parts.append("Environment variable used correctly (no hardcoding) (+10)")
        else:
            feedback_parts.append("Security warning: API_KEY appears to be hardcoded (0/10)")
    else:
        feedback_parts.append("Hardcoding check skipped due to execution failure")

    # 4. Container Health (10 pts)
    if container_running and cron_running:
        score += 10
        feedback_parts.append("Container and Cron daemon healthy (+10)")
    else:
        feedback_parts.append("Container or Cron daemon not running (0/10)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }