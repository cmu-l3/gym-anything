#!/usr/bin/env python3
"""
Verifier for docker_autoheal_watchdog task.

Scoring (100 points):
- Healthcheck Configured: 20 pts
- Watchdog Service Exists & Configured: 20 pts
- Deadlock Detection (Healthcheck catches sabotage): 20 pts
- Auto-Remediation (Restart actually happened): 40 pts

Pass Threshold: 80 points (Must achieve actual recovery)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 80

def verify_docker_autoheal_watchdog(traj, env_info, task_info):
    """Verify that the self-healing stack works."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/autoheal_result.json", temp_path)
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
    
    # 1. Healthcheck Configuration (20 pts)
    if result.get("has_healthcheck", 0):
        score += 20
        feedback_parts.append("Healthcheck configured on gateway (+20)")
    else:
        feedback_parts.append("Healthcheck missing on gateway (0/20)")

    # 2. Watchdog Configuration (20 pts)
    watchdog_exists = result.get("watchdog_exists", 0)
    watchdog_socket = result.get("watchdog_has_socket", 0)
    
    if watchdog_exists and watchdog_socket:
        score += 20
        feedback_parts.append("Watchdog service running with docker socket (+20)")
    elif watchdog_exists:
        score += 10
        feedback_parts.append("Watchdog exists but missing socket mount (10/20)")
    else:
        feedback_parts.append("Watchdog service not found (0/20)")

    # 3. Deadlock Detection (20 pts)
    # Did the container report 'unhealthy' after sabotage?
    if result.get("detected_unhealthy", 0):
        score += 20
        feedback_parts.append("System correctly identified unhealthy state (+20)")
    else:
        feedback_parts.append("System failed to detect unhealthy state during test (0/20)")

    # 4. Auto-Remediation (40 pts)
    # Did the restart actually happen?
    if result.get("recovery_success", 0):
        score += 40
        feedback_parts.append("SUCCESS: Watchdog successfully restarted the broken container (+40)")
    else:
        feedback_parts.append("FAILURE: Container was not automatically restarted after 60s (0/40)")

    passed = score >= PASS_THRESHOLD
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }