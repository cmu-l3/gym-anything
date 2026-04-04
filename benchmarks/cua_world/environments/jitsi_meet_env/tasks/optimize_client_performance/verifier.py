#!/usr/bin/env python3
"""
Verifier for optimize_client_performance task.

Checks if the Jitsi Meet config.js file was modified to include:
- disableAudioLevels: true
- enableNoisyMicDetection: false
- startAudioOnly: true
"""

import json
import os
import base64
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_optimize_client_performance(traj, env_info, task_info):
    """
    Verify the Jitsi configuration optimization.
    """
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
    
    # 1. Check if file exists and was modified (10 pts)
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Config file config.js not found"}
    
    if result.get('file_modified_during_task', False):
        score += 10
        feedback_parts.append("File modified successfully")
    else:
        feedback_parts.append("File was not modified (timestamp unchanged)")

    # 2. Decode and parse content
    content_b64 = result.get('config_content_base64', '')
    if not content_b64:
        return {"passed": False, "score": score, "feedback": "Config file content is empty or unreadable"}

    try:
        content_str = base64.b64decode(content_b64).decode('utf-8')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode config content: {e}"}

    # Helper to check key-value pairs loosely (handling whitespace/comments)
    # We look for the pattern: key : value
    # JavaScript objects keys can be unquoted.
    
    def check_setting(key, expected_val_str, points):
        # Regex explanation:
        # \bKEY\s*:\s*VALUE
        # We allow for trailing commas or comments, but ensuring the value is set
        pattern = re.compile(rf"\b{key}\s*:\s*{expected_val_str}\b", re.IGNORECASE)
        if pattern.search(content_str):
            return points, f"{key} set correctly"
        return 0, f"{key} NOT set to {expected_val_str}"

    # 3. Check disableAudioLevels: true (30 pts)
    p, f = check_setting("disableAudioLevels", "true", 30)
    score += p
    feedback_parts.append(f)

    # 4. Check enableNoisyMicDetection: false (30 pts)
    p, f = check_setting("enableNoisyMicDetection", "false", 30)
    score += p
    feedback_parts.append(f)

    # 5. Check startAudioOnly: true (30 pts)
    p, f = check_setting("startAudioOnly", "true", 30)
    score += p
    feedback_parts.append(f)

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }