#!/usr/bin/env python3
"""
Verifier for dev_env_hot_reload_setup task.

Verifies:
1. Application accessibility (running on port 5000)
2. Configuration correctness (bind mounts and command override present)
3. Hot Reload functionality (code change reflects without container restart)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hot_reload(traj, env_info, task_info):
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
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read verification result: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Static Configuration Checks (40 points)
    if result.get('has_volumes', False):
        score += 20
        feedback_parts.append("Volume configuration found (+20)")
    else:
        feedback_parts.append("Missing 'volumes' configuration")

    if result.get('has_command_override', False):
        score += 20
        feedback_parts.append("Command override found (+20)")
    else:
        feedback_parts.append("Missing 'command' override")

    # 2. Application Status (20 points)
    if result.get('app_accessible', False):
        score += 20
        feedback_parts.append("App accessible at port 5000 (+20)")
    else:
        feedback_parts.append("App not accessible")

    # 3. Hot Reload Functional Test (40 points)
    # This is the critical test. If hot reload works, they likely did everything right.
    hot_reload = result.get('hot_reload_success', False)
    stable = result.get('container_stable', False)
    
    if hot_reload:
        score += 30
        feedback_parts.append("Hot reload verified (+30)")
        
        if stable:
            score += 10
            feedback_parts.append("Container stable during reload (+10)")
        else:
            feedback_parts.append("Warning: Container restarted during test (less efficient)")
    else:
        feedback_parts.append("Hot reload failed: Code change did not reflect automatically")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }