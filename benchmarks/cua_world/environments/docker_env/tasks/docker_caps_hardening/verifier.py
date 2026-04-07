#!/usr/bin/env python3
"""
Verifier for Docker Capabilities Hardening Task.

Criteria:
1. Container is running (10 pts)
2. Runs as Non-Root (UID != 0) (30 pts)
3. Drops ALL default capabilities (20 pts)
4. Adds NET_BIND_SERVICE (15 pts)
5. Adds NET_RAW (15 pts)
6. Web endpoint works (Port 80 bound) (5 pts)
7. Ping endpoint works (ICMP sent) (5 pts)

Pass Threshold: 70 points
"""

import json
import os
import logging
import tempfile
import ast

logger = logging.getLogger(__name__)

def verify_docker_caps_hardening(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Container Running (10 pts)
    if result.get('is_running') == 1:
        score += 10
        feedback.append("Container is running (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "Container net-monitor is not running"}

    # 2. Non-Root User (30 pts)
    # Check actual runtime UID
    try:
        uid = int(result.get('container_uid', 0))
        if uid != 0:
            score += 30
            feedback.append(f"Running as non-root user (UID {uid}) (+30)")
        else:
            feedback.append("Running as ROOT (UID 0) - Failed least privilege check")
    except ValueError:
        feedback.append("Could not determine Container UID")

    # 3. Capability Drop (20 pts)
    # Expect "ALL" in CapDrop
    cap_drop_raw = result.get('cap_drop', 'None')
    # Handle string representation of list from bash output
    caps_dropped = False
    if "ALL" in cap_drop_raw:
        caps_dropped = True
    
    if caps_dropped:
        score += 20
        feedback.append("Capabilities dropped correctly (+20)")
    else:
        feedback.append(f"Did not drop ALL capabilities. Found: {cap_drop_raw}")

    # 4. Capability Add (30 pts total)
    cap_add_raw = result.get('cap_add', 'None')
    
    # Check NET_BIND_SERVICE (15 pts)
    if "NET_BIND_SERVICE" in cap_add_raw:
        score += 15
        feedback.append("NET_BIND_SERVICE capability present (+15)")
    else:
        feedback.append("Missing NET_BIND_SERVICE capability")

    # Check NET_RAW (15 pts)
    if "NET_RAW" in cap_add_raw:
        score += 15
        feedback.append("NET_RAW capability present (+15)")
    else:
        feedback.append("Missing NET_RAW capability")

    # 5. Functionality (10 pts total)
    # Web Status
    if result.get('web_status') == 1:
        score += 5
        feedback.append("Web service responding on port 80 (+5)")
    else:
        feedback.append("Web service not accessible")

    # Ping Status
    if result.get('ping_status') == 1:
        score += 5
        feedback.append("Ping functionality working (+5)")
    else:
        feedback.append("Ping functionality failed")

    passed = score >= task_info['metadata'].get('pass_threshold', 70)
    
    # Mandatory requirement check: Must be non-root to pass
    if passed and uid == 0:
        passed = False
        feedback.append("FAILED: Score met threshold but container is still running as ROOT.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }