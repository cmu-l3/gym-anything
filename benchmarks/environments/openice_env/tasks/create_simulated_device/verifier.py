#!/usr/bin/env python3
"""Verifier for create_simulated_device task in OpenICE."""

import json
import tempfile
import os


def verify_create_simulated_device(traj, env_info, task_info):
    """Verify that a simulated device adapter was created in OpenICE.

    Scoring criteria (100 points total):
    - OpenICE running (20 pts) - CRITICAL
    - Device evidence found (30 pts) - New windows or device-related windows
    - Window count increased (20 pts) - Device adapter creates new window
    - Device in log (15 pts) - Log shows device creation
    - Task completed in time (15 pts) - Reasonable completion time

    Pass threshold: 60 points AND openice_running=true
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    min_device_count = metadata.get('min_device_count', 1)

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

    # Criterion 2: Device evidence found (30 pts)
    device_evidence = result.get('device_evidence_found', False)
    device_windows = result.get('device_related_windows', 0)
    if device_evidence or device_windows > 0:
        score += 30
        subscores['device_evidence'] = 30
        feedback_parts.append(f"Device evidence found ({device_windows} device windows)")
    else:
        subscores['device_evidence'] = 0
        feedback_parts.append("No device evidence found")

    # Criterion 3: Window count increased (20 pts)
    initial_windows = result.get('initial_window_count', 0)
    final_windows = result.get('final_window_count', 0)
    window_increase = final_windows - initial_windows
    if window_increase > 0:
        score += 20
        subscores['window_increase'] = 20
        feedback_parts.append(f"Window count increased by {window_increase}")
    else:
        subscores['window_increase'] = 0
        feedback_parts.append("Window count did not increase")

    # Criterion 4: Device in log (15 pts)
    device_in_log = result.get('device_in_log', False)
    if device_in_log:
        score += 15
        subscores['device_in_log'] = 15
        feedback_parts.append("Device creation found in log")
    else:
        subscores['device_in_log'] = 0
        feedback_parts.append("No device creation in log")

    # Criterion 5: Task completed in reasonable time (15 pts)
    task_start = result.get('task_start_timestamp', 0)
    task_end = result.get('task_end_timestamp', 0)
    task_duration = task_end - task_start
    if task_duration > 10:  # At least 10 seconds of work
        score += 15
        subscores['task_duration'] = 15
        feedback_parts.append(f"Task duration: {task_duration}s")
    else:
        subscores['task_duration'] = 0
        feedback_parts.append(f"Task too quick ({task_duration}s)")

    # Determine pass/fail
    # Must have OpenICE running and some evidence of device creation
    passed = score >= 60 and openice_running and (device_evidence or device_windows > 0 or window_increase > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "openice_running": openice_running,
            "device_evidence": device_evidence,
            "device_windows": device_windows,
            "window_change": f"{initial_windows} -> {final_windows}",
            "device_in_log": device_in_log,
            "task_duration_sec": task_duration
        }
    }
