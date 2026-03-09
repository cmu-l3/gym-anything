#!/usr/bin/env python3
"""Verifier for launch_clinical_app task in OpenICE."""

import json
import tempfile
import os


def verify_launch_clinical_app(traj, env_info, task_info):
    """Verify that a clinical application was launched in OpenICE.

    Scoring criteria (100 points total):
    - OpenICE running (20 pts) - CRITICAL
    - Window state changed (30 pts) - App launch changes UI state
    - App-related windows (20 pts) - Specific app windows detected
    - App launched in log (15 pts) - Log shows app activity
    - Task duration (15 pts) - Reasonable time to launch and observe app

    Pass threshold: 60 points AND openice_running=true
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: OpenICE running (20 pts) - CRITICAL
    openice_running = result.get('openice_running', False)
    if openice_running:
        score += 20
        subscores['openice_running'] = 20
        feedback_parts.append("OpenICE is running")
    else:
        subscores['openice_running'] = 0
        feedback_parts.append("FAIL: OpenICE not running")

    # Criterion 2: Window state changed (30 pts)
    window_changed = result.get('window_changed', False)
    app_interaction = result.get('app_interaction', False)
    if window_changed or app_interaction:
        score += 30
        subscores['window_changed'] = 30
        feedback_parts.append("Window state changed (app interaction)")
    else:
        subscores['window_changed'] = 0
        feedback_parts.append("No window state change detected")

    # Criterion 3: App-related windows (20 pts)
    app_windows = result.get('app_related_windows', 0)
    initial_count = result.get('initial_window_count', 0)
    final_count = result.get('final_window_count', 0)

    if app_windows > 0 or final_count != initial_count:
        score += 20
        subscores['app_windows'] = 20
        feedback_parts.append(f"App windows: {app_windows}, window count: {initial_count} -> {final_count}")
    else:
        subscores['app_windows'] = 0
        feedback_parts.append("No app-specific windows detected")

    # Criterion 4: App launched in log (15 pts)
    app_launched_log = result.get('app_launched_log', False)
    if app_launched_log:
        score += 15
        subscores['app_launched_log'] = 15
        feedback_parts.append("App activity found in log")
    else:
        subscores['app_launched_log'] = 0
        feedback_parts.append("No app activity in log")

    # Criterion 5: Task duration (15 pts)
    task_start = result.get('task_start_timestamp', 0)
    task_end = result.get('task_end_timestamp', 0)
    task_duration = task_end - task_start
    if task_duration >= 10:  # At least 10 seconds to launch and observe
        score += 15
        subscores['task_duration'] = 15
        feedback_parts.append(f"Task duration: {task_duration}s")
    else:
        subscores['task_duration'] = 0
        feedback_parts.append(f"Task too quick ({task_duration}s)")

    # Determine pass/fail
    passed = score >= 60 and openice_running and (window_changed or app_interaction)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "openice_running": openice_running,
            "window_changed": window_changed,
            "app_interaction": app_interaction,
            "app_windows": app_windows,
            "window_count_change": f"{initial_count} -> {final_count}",
            "app_launched_log": app_launched_log,
            "task_duration_sec": task_duration
        }
    }
