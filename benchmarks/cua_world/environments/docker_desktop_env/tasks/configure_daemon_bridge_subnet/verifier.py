#!/usr/bin/env python3
"""
Verifier for configure_daemon_bridge_subnet task.

Criteria:
1. Docker daemon must be running (20 pts)
2. Bridge subnet must match expected CIDR (60 pts)
3. Bridge gateway must match expected IP (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_subnet_config(traj, env_info, task_info):
    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_subnet = metadata.get('expected_subnet', '192.168.200.0/24')
    expected_gateway = metadata.get('expected_gateway', '192.168.200.1')

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
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if daemon is running (20 pts)
    # The config change requires a restart; if it fails to come back up, config was likely invalid
    daemon_running = result.get('daemon_running', False)
    if daemon_running:
        score += 20
        feedback_parts.append("Docker daemon is running")
    else:
        feedback_parts.append("Docker daemon is NOT running (did it fail to restart?)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Check Subnet (60 pts)
    current_subnet = result.get('current_subnet', '')
    initial_subnet = result.get('initial_subnet', '')
    
    if current_subnet == expected_subnet:
        score += 60
        feedback_parts.append(f"Subnet correctly configured to {current_subnet}")
    elif current_subnet == initial_subnet:
        feedback_parts.append(f"Subnet unchanged ({current_subnet}). Did you forget to Apply & Restart?")
    else:
        feedback_parts.append(f"Subnet incorrect. Expected: {expected_subnet}, Got: {current_subnet}")

    # 3. Check Gateway (20 pts)
    current_gateway = result.get('current_gateway', '')
    
    if current_gateway == expected_gateway:
        score += 20
        feedback_parts.append(f"Gateway correct ({current_gateway})")
    else:
        feedback_parts.append(f"Gateway incorrect. Expected: {expected_gateway}, Got: {current_gateway}")

    # Pass determination
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "expected_subnet": expected_subnet,
            "current_subnet": current_subnet,
            "initial_subnet": initial_subnet
        }
    }