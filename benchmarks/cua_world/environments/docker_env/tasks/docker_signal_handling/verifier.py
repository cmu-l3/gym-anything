#!/usr/bin/env python3
"""
Verifier for docker_signal_handling task.

Scoring (100 pts total):
1. Webserver fixed (Graceful stop < 4.5s): 20 pts
2. Scheduler fixed (Graceful stop < 4.5s): 20 pts
3. Processor fixed (Graceful stop < 4.5s): 15 pts
4. Processor uses init system: 10 pts
5. All fixed containers running: 10 pts
6. Originals stopped: 5 pts
7. Report exists and valid: 20 pts

Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_signal_handling(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/signal_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Threshold for graceful stop (Docker timeout is 5s in test, so graceful should be << 5s)
    GRACEFUL_THRESHOLD = 4.5

    # 1. Webserver Logic (20 pts)
    ws_time = float(result.get("webserver_stop_time", 999))
    if ws_time < GRACEFUL_THRESHOLD:
        score += 20
        feedback.append(f"Webserver stopped gracefully ({ws_time:.2f}s).")
    elif ws_time < 999:
        feedback.append(f"Webserver failed to stop gracefully ({ws_time:.2f}s). Check CMD format.")
    else:
        feedback.append("Webserver not running.")

    # 2. Scheduler Logic (20 pts)
    sc_time = float(result.get("scheduler_stop_time", 999))
    if sc_time < GRACEFUL_THRESHOLD:
        score += 20
        feedback.append(f"Scheduler stopped gracefully ({sc_time:.2f}s).")
    elif sc_time < 999:
        feedback.append(f"Scheduler failed to stop gracefully ({sc_time:.2f}s). Check entrypoint exec.")
    else:
        feedback.append("Scheduler not running.")

    # 3. Processor Logic (25 pts total: 15 stop time + 10 init)
    pr_time = float(result.get("processor_stop_time", 999))
    has_init = result.get("processor_has_init", False)
    
    if pr_time < GRACEFUL_THRESHOLD:
        score += 15
        feedback.append(f"Processor stopped gracefully ({pr_time:.2f}s).")
    elif pr_time < 999:
        feedback.append(f"Processor failed to stop gracefully ({pr_time:.2f}s).")
    
    if has_init:
        score += 10
        feedback.append("Processor has init system enabled.")
    else:
        feedback.append("Processor missing init system (tini/--init).")

    # 4. Running Status (10 pts)
    running_count = sum([
        result.get("webserver_running", 0),
        result.get("scheduler_running", 0),
        result.get("processor_running", 0)
    ])
    if running_count == 3:
        score += 10
        feedback.append("All fixed containers running.")
    else:
        score += int(running_count * 3.3)
        feedback.append(f"Only {running_count}/3 fixed containers running.")

    # 5. Originals Stopped (5 pts)
    if result.get("originals_stopped"):
        score += 5
        feedback.append("Original containers stopped.")

    # 6. Report (20 pts)
    report_exists = result.get("report_exists", False)
    content = result.get("report_content", "").lower()
    
    if report_exists:
        score += 10 # Base points for existence
        keywords = ["exec", "pid 1", "shell", "signal", "sigterm", "init"]
        found_kw = [kw for kw in keywords if kw in content]
        if len(found_kw) >= 2:
            score += 10
            feedback.append(f"Report looks good (keywords: {', '.join(found_kw)}).")
        else:
            feedback.append("Report exists but missing technical details.")
    else:
        feedback.append("Report missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }