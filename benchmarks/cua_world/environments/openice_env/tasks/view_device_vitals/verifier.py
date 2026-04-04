#!/usr/bin/env python3
"""Verifier for view_device_vitals task in OpenICE."""

import json
import tempfile
import os


def verify_view_device_vitals(traj, env_info, task_info):
    """Verify that vital signs data was viewed from a simulated device.

    Scoring criteria (100 points total):
    - OpenICE running (15 pts) - CRITICAL
    - Device windows present (25 pts) - Device adapter created
    - Device activity in log (20 pts) - Device publishing data
    - Vitals/waveform in log (20 pts) - Vital signs being transmitted
    - Details view opened (10 pts) - Multiple windows indicating details view
    - Task duration reasonable (10 pts) - Spent time viewing data

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

    # Criterion 1: OpenICE running (15 pts) - CRITICAL
    openice_running = result.get('openice_running', False)
    if openice_running:
        score += 15
        subscores['openice_running'] = 15
        feedback_parts.append("OpenICE is running")
    else:
        subscores['openice_running'] = 0
        feedback_parts.append("FAIL: OpenICE not running")

    # Criterion 2: Device windows present (25 pts)
    device_windows = result.get('device_related_windows', 0)
    initial_windows = result.get('initial_window_count', 0)
    final_windows = result.get('final_window_count', 0)
    window_increase = final_windows - initial_windows

    if device_windows > 0 or window_increase > 0:
        score += 25
        subscores['device_windows'] = 25
        feedback_parts.append(f"Device windows: {device_windows}, window increase: {window_increase}")
    else:
        subscores['device_windows'] = 0
        feedback_parts.append("No device windows detected")

    # Criterion 3: Device activity in log (20 pts)
    device_activity = result.get('device_activity', False)
    if device_activity:
        score += 20
        subscores['device_activity'] = 20
        feedback_parts.append("Device activity detected in log")
    else:
        subscores['device_activity'] = 0
        feedback_parts.append("No device activity in log")

    # Criterion 4: Vitals/waveform in log (20 pts)
    vitals_in_log = result.get('vitals_in_log', False)
    if vitals_in_log:
        score += 20
        subscores['vitals_in_log'] = 20
        feedback_parts.append("Vital signs data found in log")
    else:
        subscores['vitals_in_log'] = 0
        feedback_parts.append("No vital signs data in log")

    # Criterion 5: Details view opened (10 pts)
    details_viewed = result.get('details_viewed', False)
    if details_viewed or window_increase > 1:
        score += 10
        subscores['details_viewed'] = 10
        feedback_parts.append("Device details view opened")
    else:
        subscores['details_viewed'] = 0
        feedback_parts.append("Details view not clearly opened")

    # Criterion 6: Task duration reasonable (10 pts)
    task_start = result.get('task_start_timestamp', 0)
    task_end = result.get('task_end_timestamp', 0)
    task_duration = task_end - task_start
    if task_duration >= 20:  # At least 20 seconds to create device and view vitals
        score += 10
        subscores['task_duration'] = 10
        feedback_parts.append(f"Task duration: {task_duration}s")
    else:
        subscores['task_duration'] = 0
        feedback_parts.append(f"Task too quick ({task_duration}s)")

    # Determine pass/fail
    passed = score >= 60 and openice_running and (device_windows > 0 or window_increase > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "openice_running": openice_running,
            "device_windows": device_windows,
            "window_change": f"{initial_windows} -> {final_windows}",
            "device_activity": device_activity,
            "vitals_in_log": vitals_in_log,
            "details_viewed": details_viewed,
            "task_duration_sec": task_duration
        }
    }
