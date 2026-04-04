#!/usr/bin/env python3
"""
Verifier for fix_zombie_process_leak task.

Criteria:
1. Container 'job-worker' must be running (20 pts)
2. Container must have 'Init' enabled in HostConfig (40 pts)
   - This proves 'init: true' was added to compose or '--init' to run
3. Zombie process count must be low (<= 2) (30 pts)
   - Verifies the fix actually works
4. Application logs must show activity (10 pts)
   - Ensures the user didn't just break the app loop to stop zombies

Pass Threshold: 70 points AND Init enabled.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_zombie_process_leak(traj, env_info, task_info):
    # Setup
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    is_running = result.get('is_running', False)
    init_enabled = result.get('init_enabled', False)
    zombie_count = result.get('zombie_count', -1)
    logs_active = result.get('logs_active', False)
    
    # 1. Container Running (20 pts)
    if is_running:
        score += 20
        feedback_parts.append("Container running (+20)")
    else:
        feedback_parts.append("Container NOT running (0)")

    # 2. Init Enabled (40 pts) - CRITICAL
    if init_enabled:
        score += 40
        feedback_parts.append("Init process enabled (+40)")
    else:
        feedback_parts.append("Init process NOT enabled (0)")

    # 3. Zombie Count (30 pts)
    # Ideally 0, but we allow 1-2 transient zombies depending on race conditions
    if zombie_count == -1:
         feedback_parts.append("Cannot check zombies (container stopped)")
    elif zombie_count <= 2:
        score += 30
        feedback_parts.append(f"Zombie count low: {zombie_count} (+30)")
    else:
        feedback_parts.append(f"Zombie count too high: {zombie_count} (0)")

    # 4. App Active (10 pts)
    if logs_active:
        score += 10
        feedback_parts.append("App logs active (+10)")
    else:
        feedback_parts.append("App logs inactive or app broken (0)")

    # Decode process list for details
    try:
        proc_list_b64 = result.get('process_list', '')
        if proc_list_b64:
            proc_list = base64.b64decode(proc_list_b64).decode('utf-8')
            # logger.info(f"Process List Sample:\n{proc_list}")
    except:
        pass

    # Pass Condition
    # Must have running container, init enabled, and low zombies
    passed = (score >= 70 and init_enabled and is_running)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "zombie_count": zombie_count,
            "init_enabled": init_enabled,
            "is_running": is_running
        }
    }