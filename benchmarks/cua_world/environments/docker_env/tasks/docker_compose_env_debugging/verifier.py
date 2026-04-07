#!/usr/bin/env python3
"""
Verifier for docker_compose_env_debugging task.

Scoring (100 points):
  - Container Running: 10 pts
  - DB_HOST Correct (prod-db-01): 25 pts
  - DB_PASSWORD Correct (Secure$tring!2024): 25 pts
  - API_REGION Correct (eu-west-1): 10 pts
  - YAML Syntax Fixed (hardcodes removed): 15 pts
  - App Connection Success (logs verify logic): 15 pts

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_compose_env_debugging(traj, env_info, task_info):
    """Verify the Docker Compose environment precedence fix."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    CORRECT_HOST = metadata.get('correct_host', 'prod-db-01')
    CORRECT_PASS = metadata.get('correct_password', 'Secure$tring!2024')
    CORRECT_REGION = metadata.get('correct_region', 'eu-west-1')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/env_debug_result.json", temp_path)
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
    
    # 1. Container Running (10 pts)
    if result.get("container_running", False):
        score += 10
        feedback_parts.append("Container running (+10)")
    else:
        feedback_parts.append("Container NOT running (0/10)")

    # 2. DB_HOST Correct (25 pts)
    actual_host = result.get("env_host", "")
    if actual_host == CORRECT_HOST:
        score += 25
        feedback_parts.append("DB_HOST correct (+25)")
    elif actual_host == "dev-db":
        feedback_parts.append("DB_HOST is still 'dev-db' - Hardcode not removed (0/25)")
    else:
        feedback_parts.append(f"DB_HOST incorrect: '{actual_host}' (0/25)")

    # 3. DB_PASSWORD Correct (25 pts)
    actual_pass = result.get("env_pass", "")
    if actual_pass == CORRECT_PASS:
        score += 25
        feedback_parts.append("DB_PASSWORD correct (+25)")
    else:
        # Check if they lost the $
        if "$" not in actual_pass and "Secure" in actual_pass:
            feedback_parts.append("DB_PASSWORD incorrect: Special character '$' was lost/interpolated (0/25)")
        else:
            feedback_parts.append("DB_PASSWORD incorrect (0/25)")

    # 4. API_REGION Correct (10 pts)
    if result.get("env_region", "") == CORRECT_REGION:
        score += 10
        feedback_parts.append("API_REGION correct (+10)")
    else:
        feedback_parts.append("API_REGION incorrect (0/10)")

    # 5. YAML Fixed (15 pts)
    if result.get("yaml_fixed_static", False):
        score += 15
        feedback_parts.append("docker-compose.yml hardcodes removed (+15)")
    else:
        feedback_parts.append("docker-compose.yml still contains hardcoded values (0/15)")

    # 6. Log Success (15 pts)
    if result.get("log_success", False):
        score += 15
        feedback_parts.append("App logs confirm successful connection (+15)")
    else:
        feedback_parts.append("App logs show failure or missing success message (0/15)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }