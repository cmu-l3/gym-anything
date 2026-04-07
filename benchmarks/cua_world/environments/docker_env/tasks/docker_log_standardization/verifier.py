#!/usr/bin/env python3
"""
Verifier for docker_log_standardization task.

Scoring (100 points total):
  - Fixed containers (12 pts each * 5 = 60 pts):
    - Must be running
    - Must be created AFTER task start
    - Must have json-file driver
    - Must have max-size=10m
    - Must have max-file=3
  - Original containers stopped (2 pts each * 5 = 10 pts)
  - Report (30 pts):
    - Exists & Modified (10 pts)
    - Contains ERR-4721 (10 pts)
    - Substantial content (> 50 chars) (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_log_standardization(traj, env_info, task_info):
    """Verify log standardization task results."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/log_audit_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    task_start = result.get("task_start", 0)

    # 1. Verify Fixed Containers (60 pts)
    fixed_containers = result.get("fixed_containers", {})
    expected_names = [
        "acme-web-fixed", "acme-api-fixed", "acme-worker-fixed", 
        "acme-scheduler-fixed", "acme-notifier-fixed"
    ]
    
    for name in expected_names:
        info = fixed_containers.get(name, {})
        status = info.get("status", "missing")
        created = info.get("created_epoch", 0)
        driver = info.get("driver", "")
        max_size = info.get("max_size", "")
        max_file = info.get("max_file", "")

        is_valid = True
        reason = []

        if status != "running":
            is_valid = False
            reason.append(f"status={status}")
        
        if created <= task_start:
            is_valid = False
            reason.append("not recreated")

        if driver != "json-file":
            is_valid = False
            reason.append(f"driver={driver}")

        # Strict check on config
        if max_size != "10m":
            is_valid = False
            reason.append(f"max-size={max_size}")

        if max_file != "3":
            is_valid = False
            reason.append(f"max-file={max_file}")

        if is_valid:
            score += 12
        else:
            feedback_parts.append(f"{name} failed: {', '.join(reason)}")

    # 2. Verify Originals Stopped (10 pts)
    original_containers = result.get("original_containers", {})
    originals_stopped = 0
    for name, status in original_containers.items():
        if status not in ["running", "restarting", "paused"]:
            originals_stopped += 1
    
    score += (originals_stopped * 2)
    if originals_stopped < 5:
        feedback_parts.append(f"Only {originals_stopped}/5 original containers stopped")

    # 3. Verify Report (30 pts)
    report = result.get("report", {})
    report_exists = report.get("exists", 0)
    report_mtime = report.get("mtime", 0)
    report_size = report.get("size", 0)
    report_has_error = report.get("has_error_code", 0)

    if report_exists and report_mtime > task_start:
        score += 10 # Exists
        if report_size > 50:
            score += 10 # Content
        else:
            feedback_parts.append("Report too short")
        
        if report_has_error:
            score += 10 # Error code
        else:
            feedback_parts.append("Report missing error code ERR-4721")
    else:
        feedback_parts.append("Report missing or not modified")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts) if feedback_parts else "All criteria met"
    }