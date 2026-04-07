#!/usr/bin/env python3
"""
Verifier for docker_airgap_deployment task.

Scoring Breakdown (100 points):
- Local Build (10): Image exists locally.
- Remote Transfer (30): Image exists on remote daemon.
- Container Running (20): Container is Up on remote.
- Configuration (25): Correct name, port mapping (8080), restart policy.
- Functional (15): App responds to HTTP request.

Anti-Gaming:
- Checks timestamps (via logic in setup/export scripts effectively).
- Ensures isolation wasn't broken (network check).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airgap_deployment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Read result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Local Build (10 pts)
    if result.get("local_image_exists"):
        score += 10
        feedback.append("Local image built successfully (+10).")
    else:
        feedback.append("Local image 'inventory-tracker:v1' not found.")

    # 2. Remote Transfer (30 pts)
    if result.get("remote_image_exists"):
        score += 30
        feedback.append("Image successfully transferred to isolated host (+30).")
    else:
        feedback.append("Image not found on remote host.")

    # 3. Container Running (20 pts)
    if result.get("remote_container_running"):
        score += 20
        feedback.append("Container is running on remote host (+20).")
    else:
        feedback.append("No container running 'inventory-tracker:v1' on remote host.")

    # 4. Configuration (25 pts)
    config_score = 0
    # Name
    if result.get("remote_container_name") == "tracker-app":
        config_score += 5
    else:
        feedback.append(f"Incorrect container name: {result.get('remote_container_name')}")
    
    # Restart Policy
    if result.get("restart_policy") == "always":
        config_score += 10
    else:
        feedback.append(f"Incorrect restart policy: {result.get('restart_policy')} (expected 'always')")

    # Port Mapping
    if str(result.get("port_mapping")) == "8080":
        config_score += 10
    else:
        feedback.append(f"Incorrect port mapping: {result.get('port_mapping')} (expected 8080)")
    
    if config_score > 0:
        score += config_score
        feedback.append(f"Configuration checks passed (+{config_score}).")

    # 5. Functionality (15 pts)
    if result.get("app_responding"):
        score += 15
        feedback.append("Application is reachable and responding (+15).")
    else:
        feedback.append("Application did not respond to HTTP request.")

    # Pass Threshold
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 75)
    passed = score >= pass_threshold

    # Isolation Check (Fail-safe)
    if not result.get("isolation_maintained", True):
        score = 0
        passed = False
        feedback = ["CRITICAL: Isolation network 'secure-net' was tampered with."]

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }