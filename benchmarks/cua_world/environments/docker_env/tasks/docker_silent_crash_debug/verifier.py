#!/usr/bin/env python3
"""
Verifier for docker_silent_crash_debug task.

Scoring Breakdown (100 pts total):
1. Stability (35 pts):
   - Container is running stable (not restarting) (25 pts)
   - Configuration (docker-compose) fixed (10 pts)
2. Observability (55 pts):
   - Logs are visible via 'docker logs' (40 pts)
   - Logs contain expected success message (15 pts)
3. Documentation (10 pts):
   - 'reason_for_crash.txt' exists (10 pts)

Pass Threshold: 65 pts
"""

import json
import os
import sys
import tempfile

def verify_docker_silent_crash_debug(traj, env_info, task_info):
    # 1. Setup - Load Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Evaluate Stability (35 pts)
    container_running = result.get("container_running", False)
    config_fixed = result.get("config_fixed", False)

    if container_running:
        score += 25
        feedback.append("Container is running stable (+25)")
    else:
        feedback.append(f"Container is not running stable (Status: {result.get('container_status', 'unknown')})")

    if config_fixed:
        score += 10
        feedback.append("Configuration fixed (SYNC_BATCH_SIZE is valid) (+10)")
    else:
        feedback.append("Configuration not fixed (SYNC_BATCH_SIZE still contains 'items'?)")

    # 3. Evaluate Observability (55 pts)
    logs_visible = result.get("logs_visible", False)
    logs_correct = result.get("logs_correct_content", False)

    if logs_visible:
        score += 40
        feedback.append("Logs are visible via 'docker logs' (+40)")
        if logs_correct:
            score += 15
            feedback.append("Logs contain expected success message (+15)")
        else:
            feedback.append("Logs visible but 'Inventory sync initialized' not found")
    else:
        feedback.append("Logs are still empty/missing in 'docker logs' (0/55)")

    # 4. Evaluate Documentation (10 pts)
    report_exists = result.get("report_exists", False)
    if report_exists:
        score += 10
        feedback.append("Crash reason report created (+10)")
    else:
        feedback.append("Report file ~/Desktop/reason_for_crash.txt missing")

    # 5. Final Result
    pass_threshold = 65
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }