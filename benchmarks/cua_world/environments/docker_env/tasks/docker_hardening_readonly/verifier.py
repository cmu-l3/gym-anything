#!/usr/bin/env python3
"""
Verifier for docker_hardening_readonly task.

Scoring (100 points):
  - Read-Only Root Filesystem Enabled: 25 pts
  - Container Running & Healthy: 25 pts
  - Cache Mounted as tmpfs: 15 pts
  - PID Mounted as tmpfs: 15 pts
  - Logs Mounted as Volume: 20 pts

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_docker_hardening_readonly(traj, env_info, task_info):
    """Verify the container is hardened with read-only FS and correct mounts."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/hardening_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_path)
            except Exception:
                pass

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Read-Only Enabled (25 pts)
    is_readonly = result.get("is_readonly", 0)
    if is_readonly:
        score += 25
        feedback_parts.append("Read-only root enabled (+25)")
    else:
        feedback_parts.append("Read-only root NOT enabled (0/25)")

    # 2. Container Running & Healthy (25 pts)
    is_running = result.get("is_running", 0)
    is_healthy = result.get("is_healthy", 0)
    
    if is_running and is_healthy:
        score += 25
        feedback_parts.append("Container running and healthy (+25)")
    elif is_running:
        score += 10
        feedback_parts.append("Container running but health check failed (10/25)")
    else:
        feedback_parts.append("Container NOT running (0/25)")

    mounts = result.get("mounts", {})

    # 3. Cache Tmpfs (15 pts)
    # Accept 'tmpfs' type.
    if mounts.get("cache_type") == "tmpfs":
        score += 15
        feedback_parts.append("Cache mounted as tmpfs (+15)")
    elif mounts.get("cache_type") == "volume":
        score += 5
        feedback_parts.append("Cache mounted as volume (preferred tmpfs) (5/15)")
    else:
        feedback_parts.append(f"Cache not correctly mounted (Type: {mounts.get('cache_type')}) (0/15)")

    # 4. PID Tmpfs (15 pts)
    if mounts.get("pid_type") == "tmpfs":
        score += 15
        feedback_parts.append("PID mounted as tmpfs (+15)")
    else:
        feedback_parts.append(f"PID not correctly mounted (Type: {mounts.get('pid_type')}) (0/15)")

    # 5. Logs Volume (20 pts)
    # Must be volume for persistence.
    if mounts.get("log_type") == "volume":
        # Check if actually persisted data
        if mounts.get("log_persisted", 0):
            score += 20
            feedback_parts.append("Logs mounted as volume and writable (+20)")
        else:
            score += 15
            feedback_parts.append("Logs mounted as volume but no data written (15/20)")
    elif mounts.get("log_type") == "bind":
        score += 10
        feedback_parts.append("Logs mounted as bind mount (preferred volume) (10/20)")
    else:
        feedback_parts.append(f"Logs not persistent (Type: {mounts.get('log_type')}) (0/20)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }