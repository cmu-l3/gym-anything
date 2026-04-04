#!/usr/bin/env python3
"""Verifier for run_container task.

This verifier checks if the agent successfully created and ran a Docker container
using Docker Desktop with the correct name and port mapping.

Note: This verifier checks the final state (container running with correct config)
but cannot verify whether the agent used the Docker Desktop GUI vs CLI.
Future enhancement could analyze the trajectory for GUI interactions
(mouse clicks on Images section, Run button, port configuration dialog, etc.)
to enforce GUI usage.
"""

import json
import tempfile
import os


def verify_run_container(traj, env_info, task_info):
    """Verify that the container was created and is running correctly.

    Verification criteria:
    1. Container with expected name exists
    2. Container is running
    3. Container uses correct image (nginx:alpine)
    4. Port mapping is correct (8888:80)
    5. Web server is accessible (bonus)

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
    expected_name = metadata.get('expected_container_name', 'my-nginx-server')
    expected_image = metadata.get('expected_image', 'nginx:alpine')
    expected_host_port = metadata.get('expected_host_port', 8888)
    expected_container_port = metadata.get('expected_container_port', 80)

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

    # Criterion 1: Docker daemon operational (5 points)
    if result.get('docker_daemon_ready', False):
        score += 5
        feedback_parts.append("Docker daemon: ready")
    else:
        feedback_parts.append("Docker daemon: NOT ready")

    # Criterion 2: Container exists (25 points)
    container_found = result.get('container_found', False)
    if container_found:
        score += 25
        feedback_parts.append(f"Container '{expected_name}': exists")
    else:
        feedback_parts.append(f"Container '{expected_name}': NOT FOUND")
        # Check what containers exist
        all_containers = result.get('all_containers_sample', '')
        if all_containers:
            feedback_parts.append(f"(found containers: {all_containers})")

    # Criterion 3: Container is running (25 points)
    container_running = result.get('container_running', False)
    if container_running:
        score += 25
        status = result.get('container_status', 'unknown')
        feedback_parts.append(f"Container status: running ({status})")
    else:
        if container_found:
            status = result.get('container_status', 'unknown')
            feedback_parts.append(f"Container status: NOT running ({status})")
        else:
            feedback_parts.append("Container status: N/A (container not found)")

    # Criterion 4: Correct image (15 points)
    container_image = result.get('container_image', '')
    if container_image:
        # Check if it's nginx:alpine (or nginx with alpine tag)
        if 'nginx' in container_image.lower() and 'alpine' in container_image.lower():
            score += 15
            feedback_parts.append(f"Image: {container_image} (correct)")
        elif 'nginx' in container_image.lower():
            score += 10  # Partial credit for nginx
            feedback_parts.append(f"Image: {container_image} (nginx but not alpine)")
        else:
            feedback_parts.append(f"Image: {container_image} (expected nginx:alpine)")
    else:
        feedback_parts.append("Image: unknown")

    # Criterion 5: Port mapping correct (20 points)
    port_mapping_correct = result.get('port_mapping_correct', False)
    container_ports = result.get('container_ports', '')
    if port_mapping_correct:
        score += 20
        feedback_parts.append(f"Port mapping: {container_ports} (correct)")
    else:
        if container_ports:
            # Partial credit if some port mapping exists
            score += 5
            feedback_parts.append(f"Port mapping: {container_ports} (expected 8888:80)")
        else:
            feedback_parts.append(f"Port mapping: none (expected {expected_host_port}:{expected_container_port})")

    # Criterion 6: Web accessible (10 points - bonus)
    web_accessible = result.get('web_accessible', False)
    if web_accessible:
        score += 10
        feedback_parts.append("Web server: accessible at localhost:8888")
    else:
        if container_running and port_mapping_correct:
            feedback_parts.append("Web server: not accessible")
        # No penalty if container isn't running correctly

    # Determine pass/fail
    # Must have container running with correct name to pass
    passed = container_found and container_running and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "expected_name": expected_name,
            "container_found": container_found,
            "container_running": container_running,
            "container_image": result.get('container_image', ''),
            "container_ports": container_ports,
            "web_accessible": web_accessible
        }
    }
