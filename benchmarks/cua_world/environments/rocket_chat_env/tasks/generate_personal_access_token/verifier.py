#!/usr/bin/env python3
"""
Verifier for Generate Personal Access Token task.

Checks:
1. File /home/ga/gitlab_token.txt exists and has content.
2. Token 'gitlab-ci' exists in Rocket.Chat API for the admin user.
3. Both file and API token were created during the task session.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_personal_access_token(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # Check 1: API Token Existence (40 pts)
    api_found = result.get("api_token_found", False)
    if api_found:
        score += 40
        feedback_parts.append("Token 'gitlab-ci' found in API")
    else:
        feedback_parts.append("Token 'gitlab-ci' NOT found in API")

    # Check 2: API Token Freshness (20 pts)
    # If setup script cleaned correctly, existence implies freshness, but explicit check is better
    api_fresh = result.get("api_token_created_during_task", False)
    if api_fresh:
        score += 20
        feedback_parts.append("Token created during task")
    elif api_found:
        feedback_parts.append("Token exists but timestamp is old (reused previous?)")

    # Check 3: File Existence (20 pts)
    file_exists = result.get("file_exists", False)
    if file_exists:
        score += 20
        feedback_parts.append("Output file exists")
    else:
        feedback_parts.append("Output file /home/ga/gitlab_token.txt NOT found")

    # Check 4: File Content Validity (20 pts)
    # A token should be a reasonably long alphanumeric string
    content_len = result.get("file_content_length", 0)
    min_len = task_info.get("metadata", {}).get("min_token_length", 20)
    
    if file_exists:
        if content_len >= min_len:
            score += 20
            feedback_parts.append(f"File content valid (length {content_len})")
        else:
            feedback_parts.append(f"File content too short (length {content_len}, expected >={min_len})")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }