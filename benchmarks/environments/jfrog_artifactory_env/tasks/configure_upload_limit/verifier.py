#!/usr/bin/env python3
"""
Verifier for configure_upload_limit task.

Verifies that the global file upload limit in Artifactory has been set to 500 MB.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_upload_limit(traj, env_info, task_info):
    """
    Verify the upload limit configuration.
    
    Criteria:
    1. Artifactory API reports fileUploadMaxSize is exactly 500.
    2. Value changed from initial state (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected value from metadata
    metadata = task_info.get('metadata', {})
    target_limit = metadata.get('target_upload_limit', 500)

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
    
    # Extract values
    final_limit_raw = result.get('final_limit_raw', 'not_found')
    initial_limit = result.get('initial_limit', 'unknown')
    app_running = result.get('app_running', False)

    # 1. Verify Application State (10 pts)
    if app_running:
        score += 10
    else:
        feedback_parts.append("Firefox was closed")

    # 2. Verify Configuration Value (90 pts)
    try:
        final_limit_int = int(final_limit_raw)
        
        if final_limit_int == target_limit:
            score += 90
            feedback_parts.append(f"Upload limit correctly set to {target_limit} MB")
            
            # Anti-gaming check: Did it actually change?
            # If initial was already 500 (unlikely given setup, but possible in dirty env), 
            # we technically pass, but warn.
            if str(final_limit_int) == str(initial_limit):
                feedback_parts.append("(Note: Limit was already set to target value at start)")
        else:
            feedback_parts.append(f"Upload limit is {final_limit_int} MB (expected {target_limit} MB)")
            # Partial credit for being close? No, config should be exact.
            
    except ValueError:
        if final_limit_raw == "not_found":
            feedback_parts.append("Could not retrieve configuration setting from Artifactory")
        else:
            feedback_parts.append(f"Invalid configuration value found: '{final_limit_raw}'")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }