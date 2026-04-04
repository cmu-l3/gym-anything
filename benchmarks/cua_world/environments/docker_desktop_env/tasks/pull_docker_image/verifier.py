#!/usr/bin/env python3
"""Verifier for pull_docker_image task.

This verifier checks if the agent successfully pulled the target Docker image
(python:3.11-slim) using Docker Desktop.

Note: This verifier checks the final state (image exists) but cannot verify
whether the agent used the Docker Desktop GUI vs CLI. Future enhancement could
analyze the trajectory for GUI interactions (mouse clicks on Images section,
search field interactions, etc.) to enforce GUI usage.
"""

import json
import tempfile
import os


def verify_pull_docker_image(traj, env_info, task_info):
    """Verify that the python:3.11-slim image was pulled successfully.

    Verification criteria:
    1. Target image exists in Docker images list
    2. Image count increased (or target image is new)
    3. Docker daemon is operational

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
    expected_image = metadata.get('expected_image', 'python')
    expected_tag = metadata.get('expected_tag', '3.11-slim')
    full_image_name = metadata.get('full_image_name', f'{expected_image}:{expected_tag}')

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

    # Criterion 3: Target image found (60 points - main criterion)
    image_found = result.get('image_found', False)
    if image_found:
        score += 60
        image_id = result.get('image_id', 'unknown')
        image_size = result.get('image_size', 'unknown')
        feedback_parts.append(f"Target image '{full_image_name}': FOUND (ID: {image_id}, Size: {image_size})")
    else:
        # Check if any python images exist
        python_images = result.get('python_images', '')
        if python_images:
            feedback_parts.append(f"Target image '{full_image_name}': NOT FOUND (found python images: {python_images})")
        else:
            feedback_parts.append(f"Target image '{full_image_name}': NOT FOUND (no python images)")

    # Criterion 4: Image count changed (20 points)
    initial_count = result.get('initial_image_count', 0)
    current_count = result.get('current_image_count', 0)

    if current_count > initial_count:
        score += 20
        feedback_parts.append(f"Image count: {initial_count} -> {current_count} (new images pulled)")
    elif image_found:
        # Image found but count didn't change - might have been pulled before in same session
        score += 10
        feedback_parts.append(f"Image count: {initial_count} -> {current_count} (target exists)")
    else:
        feedback_parts.append(f"Image count: {initial_count} -> {current_count} (no change)")

    # Determine pass/fail
    # Must have the target image to pass
    passed = image_found and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "target_image": full_image_name,
            "image_found": image_found,
            "initial_count": initial_count,
            "current_count": current_count,
            "all_images_sample": result.get('all_images_sample', '')
        }
    }
