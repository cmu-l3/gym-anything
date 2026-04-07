#!/usr/bin/env python3
"""
Verifier for lock_down_user_profiles task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lock_down_user_profiles(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/lock_down_user_profiles_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if not result.get("api_reachable", False):
        return {"passed": False, "score": 0, "feedback": "Could not contact Rocket.Chat API to verify settings."}

    score = 0
    feedback_parts = []
    
    settings = {
        "Accounts_AllowRealNameChange": "Real Name Change",
        "Accounts_AllowUsernameChange": "Username Change",
        "Accounts_AllowEmailChange": "Email Change",
        "Accounts_AllowUserAvatarChange": "User Avatar Change",
        "Accounts_AllowDeleteOwnAccount": "Account Deletion"
    }
    
    for key, name in settings.items():
        val = result.get(key, True)
        if val is False:
            score += 20
            feedback_parts.append(f"[{name}] successfully disabled")
        else:
            feedback_parts.append(f"[{name}] remains enabled")

    passed = score == 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }