#!/usr/bin/env python3
"""Verifier for generate_api_token task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_generate_api_token(traj, env_info, task_info):
    """
    Verify that an API token was generated, saved, and works.
    
    Scoring:
    1. Token file exists (10 pts)
    2. Token authenticates successfully (50 pts)
    3. Token named 'MetricsDash' found in DB (20 pts)
    4. Token created during task session (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_token_name', 'MetricsDash')

    # Copy result file from container
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
    
    # 1. Check File Existence (10 pts)
    file_exists = result.get('file_exists', False)
    content_len = result.get('token_content_length', 0)
    
    if file_exists and content_len > 10:
        score += 10
        feedback_parts.append("Token file exists and has content")
    elif file_exists:
        score += 5
        feedback_parts.append("Token file exists but is empty/short")
    else:
        feedback_parts.append("Token file NOT found")

    # 2. Check Token Functionality (50 pts)
    # The export script runs `curl` with the token and reports success
    api_works = result.get('api_works', False)
    status_code = result.get('api_status_code', 0)
    
    if api_works:
        score += 50
        feedback_parts.append("Token authenticates successfully (HTTP 200)")
    else:
        feedback_parts.append(f"Token authentication failed (HTTP {status_code})")

    # 3. Check Database Record Name (20 pts)
    db_token_found = result.get('db_token_found', False)
    db_token_name = result.get('db_token_name', '')
    
    if db_token_found and db_token_name == expected_name:
        score += 20
        feedback_parts.append(f"Token '{expected_name}' found in database")
    elif db_token_found:
        score += 10
        feedback_parts.append(f"Token found but wrong name: '{db_token_name}'")
    else:
        feedback_parts.append("No token record found in database")

    # 4. Check Creation Timestamp (20 pts)
    # Ensures the agent actually created it now, not pre-existing
    is_new = result.get('is_newly_created', False)
    if is_new:
        score += 20
        feedback_parts.append("Token was created during this session")
    else:
        feedback_parts.append("Token is old or timestamp check failed")

    # Pass if score is high enough AND functional check passed
    passed = (score >= 80) and api_works

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }