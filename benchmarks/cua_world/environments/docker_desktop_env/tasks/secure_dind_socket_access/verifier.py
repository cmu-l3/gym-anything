#!/usr/bin/env python3
"""Verifier for secure_dind_socket_access task.

Criteria:
1. Container 'build-agent' must be running.
2. Container must run as non-root user (UID != 0).
3. Container must have functional access to docker daemon.
4. Host socket permissions must NOT be compromised (world-writable).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_dind_socket_access(traj, env_info, task_info):
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # Check 1: Container Running (20 pts)
    container_running = result.get('container_running', False)
    if container_running:
        score += 20
        feedback_parts.append("Container running")
    else:
        feedback_parts.append("Container NOT running")
        return {"passed": False, "score": 0, "feedback": "Container build-agent is not running"}

    # Check 2: Non-Root User (30 pts)
    uid = result.get('container_uid', -1)
    if uid == 0:
        feedback_parts.append("FAIL: Container running as root (Security Violation)")
        return {"passed": False, "score": 20, "feedback": "Security check failed: Container is running as root"}
    elif uid > 0:
        score += 30
        feedback_parts.append(f"Container running as non-root (UID {uid})")
    else:
        feedback_parts.append(f"Could not determine UID ({uid})")

    # Check 3: Host Socket Security (20 pts)
    socket_secure = result.get('socket_secure', True)
    current_perms = result.get('current_socket_perms', 'unknown')
    
    if socket_secure:
        score += 20
        feedback_parts.append("Host socket permissions secure")
    else:
        feedback_parts.append(f"FAIL: Host socket is insecure ({current_perms})")
        return {"passed": False, "score": score, "feedback": "Security check failed: You modified host socket permissions to be insecure"}

    # Check 4: Docker Access (30 pts)
    docker_access = result.get('docker_access', False)
    if docker_access:
        score += 30
        feedback_parts.append("Docker socket accessible from container")
    else:
        error_msg = result.get('docker_error', 'Unknown error')
        feedback_parts.append(f"Docker socket access failed: {error_msg}")

    # Pass logic
    passed = score == 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }