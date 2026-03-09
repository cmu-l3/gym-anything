#!/usr/bin/env python3
"""
Verifier for fix_container_lifecycle_issues task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_lifecycle(traj, env_info, task_info):
    """
    Verify that the container logs stream immediately and stops gracefully.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # Load result
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
    
    config = result.get('config', {})
    behavior = result.get('behavior', {})
    
    # 1. Graceful Shutdown (50 points)
    # Thresholds: < 3.0s is Pass. > 9.0s is Fail (timeout is 10s).
    duration = behavior.get('shutdown_duration_sec', 10.0)
    
    if duration < 4.0:
        score += 50
        feedback_parts.append(f"Shutdown fast ({duration}s)")
    elif duration < 9.0:
        score += 25
        feedback_parts.append(f"Shutdown moderately slow ({duration}s)")
    else:
        feedback_parts.append(f"Shutdown timed out ({duration}s) - Signal handling not fixed")

    # Bonus: Check if they actually enabled init (sanity check)
    if config.get('init_enabled', False):
        feedback_parts.append("(Init process enabled)")
    else:
        # It's possible to fix this by modifying python code, though verification script tests config
        # If duration is low but init is false, maybe they changed the entrypoint to 'tini'?
        pass

    # 2. Real-time Logging (30 points)
    logs_streaming = behavior.get('logs_streaming', False)
    
    if logs_streaming:
        score += 30
        feedback_parts.append("Logs streaming correctly")
    else:
        feedback_parts.append("Logs still buffered/delayed")

    # 3. Configuration Best Practices (20 points)
    # Award points if they used the standard Docker/Env methods
    config_score = 0
    if config.get('init_enabled', False):
        config_score += 10
    
    if config.get('unbuffered_env', False) or config.get('unbuffered_flag', False):
        config_score += 10
        
    score += config_score
    if config_score > 0:
        feedback_parts.append(f"Configuration points: +{config_score}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }