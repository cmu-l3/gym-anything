#!/usr/bin/env python3
"""Verifier for container_security_hardening task.

Scoring (100 points):
- Non-root user (25 pts): Container effective UID != 0
- No Docker socket mount (25 pts): /var/run/docker.sock not mounted
- Not privileged (20 pts): HostConfig.Privileged == false
- Memory limit set (20 pts): HostConfig.Memory > 0
- App functional (10 pts): HTTP 200 on port 8090

Pass threshold: 70 points
Mandatory for pass: non-root + no socket mount + score >= 70
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_container_security_hardening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/container_security_hardening_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    # If no hardened container found at all
    hardened_container = result.get("hardened_container", "")
    if not hardened_container:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No hardened container found running — build and start the hardened deployment"
        }

    score = 0
    feedback_parts = []
    details = {}

    runs_as_root = result.get("runs_as_root", True)
    has_docker_socket = result.get("has_docker_socket", True)
    is_privileged = result.get("is_privileged", True)
    has_memory_limit = result.get("has_memory_limit", False)
    http_code = result.get("app_http_code", "000")

    # Criterion 1: Non-root user (25 pts)
    if not runs_as_root:
        score += 25
        feedback_parts.append(f"Runs as non-root user (UID: {result.get('container_user')}) (+25)")
    else:
        feedback_parts.append("Still running as root (UID 0) — add USER directive to Dockerfile (+0)")
    details["runs_as_root"] = runs_as_root

    # Criterion 2: No Docker socket (25 pts)
    if not has_docker_socket:
        score += 25
        feedback_parts.append("Docker socket NOT mounted (+25)")
    else:
        feedback_parts.append("/var/run/docker.sock still mounted — remove from compose volumes (+0)")
    details["has_docker_socket"] = has_docker_socket

    # Criterion 3: Not privileged (20 pts)
    if not is_privileged:
        score += 20
        feedback_parts.append("Container NOT privileged (+20)")
    else:
        feedback_parts.append("Container still running with privileged:true — remove from compose (+0)")
    details["is_privileged"] = is_privileged

    # Criterion 4: Memory limit (20 pts)
    if has_memory_limit:
        mem_mb = result.get("memory_limit_bytes", 0) // (1024 * 1024)
        score += 20
        feedback_parts.append(f"Memory limit set ({mem_mb}MB) (+20)")
    else:
        feedback_parts.append("No memory limit configured — add mem_limit in compose deploy.resources (+0)")
    details["has_memory_limit"] = has_memory_limit

    # Criterion 5: App functional (10 pts)
    if http_code in ("200", "301", "302"):
        score += 10
        feedback_parts.append(f"App responds HTTP {http_code} (+10)")
    else:
        feedback_parts.append(f"App not accessible (HTTP {http_code}) (+0)")
    details["app_http_code"] = http_code

    # Pass: non-root + no socket + score >= 70
    passed = (not runs_as_root) and (not has_docker_socket) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
