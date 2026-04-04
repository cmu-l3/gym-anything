#!/usr/bin/env python3
"""Verifier for stop_container task.

This verifier checks if the agent successfully stopped a running Docker container
using Docker Desktop. The container must be stopped (not removed).

Note: This verifier checks the final state (container stopped but still exists)
but cannot verify whether the agent used the Docker Desktop GUI vs CLI.
Future enhancement could analyze the trajectory for GUI interactions
(mouse clicks on Containers section, Stop button, etc.) to enforce GUI usage.
"""

import json
import tempfile
import os


def verify_stop_container(traj, env_info, task_info):
    """Verify that the container was stopped successfully.

    Verification criteria:
    1. Docker daemon is operational
    2. Target container was initially running
    3. Target container is now stopped (or removed)
    4. Running container count decreased

    Args:
        traj: Trajectory data (not used)
        env_info: Environment info dict with copy_from_env function
        task_info: Task info dict with metadata

    Returns:
        dict with keys: passed, score, feedback
    """

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_container_name', 'test-web-server')

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    feedback_parts = []

    # Criterion 1: Docker daemon operational (10 points)
    if result.get('docker_daemon_ready', False):
        score += 10
        feedback_parts.append("Docker daemon: ready")
    else:
        feedback_parts.append("Docker daemon: NOT ready")

    # Criterion 2: Docker Desktop running (10 points)
    if result.get('docker_desktop_running', False):
        score += 10
        feedback_parts.append("Docker Desktop: running")
    else:
        feedback_parts.append("Docker Desktop: NOT running")

    # Criterion 3: Container was initially running (precondition check - REQUIRED)
    initial_running = result.get('initial_container_running', 'unknown')
    precondition_met = (initial_running == 'true')

    if precondition_met:
        feedback_parts.append("Initial state: container was running (precondition met)")
    else:
        feedback_parts.append(f"PRECONDITION FAILED: container was not running at task start (was: {initial_running})")

    # Criterion 4: Container is now stopped (60 points - main criterion)
    # Task requires STOPPING the container, not removing it
    container_stopped = result.get('container_stopped', False)
    container_exists = result.get('container_exists', False)
    container_status = result.get('container_status', '')

    if container_stopped and container_exists:
        # Container properly stopped (exists but not running)
        score += 60
        feedback_parts.append(f"Container '{target_name}': STOPPED ({container_status})")
    elif container_stopped and not container_exists:
        # Container was removed instead of stopped - partial credit only
        score += 30
        feedback_parts.append(f"Container '{target_name}': REMOVED (task asked to stop, not remove - partial credit)")
    else:
        feedback_parts.append(f"Container '{target_name}': STILL RUNNING ({container_status})")
        running_containers = result.get('running_containers', '')
        if running_containers:
            feedback_parts.append(f"Running containers: {running_containers}")

    # Criterion 5: Running count decreased (20 points)
    initial_running_count = result.get('initial_running_count', 0)
    current_running_count = result.get('current_running_count', 0)

    if current_running_count < initial_running_count:
        score += 20
        feedback_parts.append(f"Running containers: {initial_running_count} -> {current_running_count} (decreased)")
    elif container_stopped:
        # Container was stopped but count might not have changed (if others started)
        score += 10
        feedback_parts.append(f"Running containers: {initial_running_count} -> {current_running_count}")
    else:
        feedback_parts.append(f"Running containers: {initial_running_count} -> {current_running_count} (no decrease)")

    # Determine pass/fail
    # Container must have been initially running (precondition) AND now be stopped
    if not precondition_met:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Precondition failed: container was not running at task start. Setup may have failed.",
            "details": {
                "target_container": target_name,
                "precondition_met": False,
                "initial_container_running": initial_running
            }
        }

    # Pass requires: container stopped AND still exists (not removed) AND high enough score
    passed = container_stopped and container_exists and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "target_container": target_name,
            "container_stopped": container_stopped,
            "container_exists": container_exists,
            "container_status": container_status,
            "initial_running_count": initial_running_count,
            "current_running_count": current_running_count
        }
    }
