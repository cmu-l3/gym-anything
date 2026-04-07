#!/usr/bin/env python3
"""
Verifier for docker_debug_distroless task.

Scoring (100 points):
  - JSON Report exists and is valid: 20 pts
  - Correct Port identified: 40 pts
  - Correct Auth Token identified: 40 pts

Anti-gaming:
  - The port and token are randomized on every run.
  - The token is NOT in docker inspect; agent must inspect process memory (e.g., /proc/1/environ).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 100

def verify_docker_debug_distroless(traj, env_info, task_info):
    """Verify extracted port and token match ground truth."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/distroless_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Result JSON malformed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Report Existence (20 pts)
    report_valid = result.get("report_valid_json", 0)
    if report_valid:
        score += 20
        feedback_parts.append("Report file exists and is valid JSON (+20)")
    else:
        feedback_parts.append("Report file missing or invalid JSON (0/20)")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # 2. Port Check (40 pts)
    actual_port = result.get("actual_port")
    reported_port = result.get("reported_port")
    
    # Handle string/int comparison safely
    try:
        if int(reported_port) == int(actual_port):
            score += 40
            feedback_parts.append("Correct port identified (+40)")
        else:
            feedback_parts.append(f"Incorrect port: reported {reported_port}, expected {actual_port} (0/40)")
    except (ValueError, TypeError):
        feedback_parts.append(f"Invalid port format: {reported_port} (0/40)")

    # 3. Token Check (40 pts)
    actual_token = str(result.get("actual_token", "")).strip()
    reported_token = str(result.get("reported_token", "")).strip()

    if reported_token and reported_token == actual_token:
        score += 40
        feedback_parts.append("Correct auth_token identified (+40)")
    else:
        # Be helpful in feedback if it looks close (e.g. they got the var name instead of value)
        if "AUTH_TOKEN" in reported_token:
            feedback_parts.append("Incorrect token (looks like variable name, need value) (0/40)")
        elif reported_token == "":
            feedback_parts.append("Token missing from report (0/40)")
        else:
            # Don't reveal actual token in feedback to avoid leaking if they see logs
            feedback_parts.append("Incorrect auth_token value (0/40)")

    # 4. Check container running (sanity check, no points but useful info)
    if not result.get("container_running", 0):
        feedback_parts.append("(Warning: Target container was stopped)")

    passed = (score >= PASS_THRESHOLD)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }