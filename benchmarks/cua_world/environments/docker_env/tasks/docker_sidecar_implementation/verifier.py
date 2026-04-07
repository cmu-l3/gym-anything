#!/usr/bin/env python3
"""
Verifier for docker_sidecar_implementation task.

Scoring (100 points):
  - Shared Volumes Configured: 20 pts
  - Log Sidecar Running: 20 pts
  - Log Streaming Working (actual logs visible): 20 pts
  - Report Sidecar Running: 20 pts
  - Reports Accessible via HTTP: 20 pts

Pass threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 80

def verify_docker_sidecar_implementation(traj, env_info, task_info):
    """Verify Sidecar and Ambassador pattern implementation."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/sidecar_result.json", temp_path)
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
    
    # 1. Check if Legacy Core is running (Prerequisite)
    legacy_running = result.get("legacy_running", 0)
    if not legacy_running:
        feedback_parts.append("Legacy Core service is NOT running (critical failure).")
        return {"passed": False, "score": 0, "feedback": "Legacy app not running."}

    # 2. Shared Volumes Configured (20 pts)
    # We inspect the legacy mounts. It should have at least 1 mount (likely 2) that are shared.
    # Since checking 'shared' strictly via inspecting one container is tricky without cross-reference,
    # we infer it from functionality, but we give points if mounts exist.
    legacy_mounts = result.get("legacy_mounts", [])
    if len(legacy_mounts) >= 1:
        # We assume if functionality works, volumes are correct.
        # But we give points here for having mounts defined.
        score += 20
        feedback_parts.append("Volumes mounted on legacy-core (+20).")
    else:
        feedback_parts.append("No volumes mounted on legacy-core (0/20).")

    # 3. Log Sidecar Running (20 pts)
    log_sidecar_running = result.get("log_sidecar_running", 0)
    if log_sidecar_running:
        score += 20
        feedback_parts.append("Log sidecar container is running (+20).")
    else:
        feedback_parts.append("Log sidecar container NOT running (0/20).")

    # 4. Log Streaming Working (20 pts)
    log_content_detected = result.get("log_content_detected", 0)
    if log_content_detected:
        score += 20
        feedback_parts.append("Log sidecar is successfully streaming transaction logs (+20).")
    else:
        feedback_parts.append("Log sidecar running but NO transaction logs found in stdout (0/20).")

    # 5. Report Sidecar Running (20 pts)
    report_sidecar_running = result.get("report_sidecar_running", 0)
    if report_sidecar_running:
        score += 20
        feedback_parts.append("Report sidecar container is running (+20).")
    else:
        feedback_parts.append("Report sidecar container NOT running (0/20).")

    # 6. Reports Accessible via HTTP (20 pts)
    report_accessible = result.get("report_http_accessible", 0)
    report_valid = result.get("report_content_valid", 0)
    
    if report_accessible and report_valid:
        score += 20
        feedback_parts.append("Reports successfully served via HTTP on port 8080 (+20).")
    elif report_accessible:
        score += 10
        feedback_parts.append("Port 8080 open but content verification failed (10/20).")
    else:
        feedback_parts.append("Reports NOT accessible on localhost:8080 (0/20).")

    # Bonus/Penalty: Robustness check
    # If log streaming failed, it might be due to race condition.
    if log_sidecar_running and not log_content_detected:
        has_robust = result.get("has_robust_command", 0)
        if not has_robust:
            feedback_parts.append("Hint: Log sidecar might have crashed or tailed before file existed.")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }