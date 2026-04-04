#!/usr/bin/env python3
"""
Verifier for Create API Token task in Jenkins.

Checks:
1. Agent generated a working API token (saved to file, authenticates correctly).
2. Agent used the token to download the job list (saved to JSON file).
3. The token was actually created in Jenkins (name check) and files were created during task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_api_token(traj, env_info, task_info):
    """
    Verify the agent created a working API token and used it.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    token_info = result.get("token_file", {})
    jobs_info = result.get("jobs_file", {})
    config_info = result.get("jenkins_config", {})

    # Criterion 1: Token File Exists & Created During Task (15 pts)
    if token_info.get("exists"):
        if token_info.get("created_during_task"):
            score += 15
            feedback_parts.append("Token file created.")
        else:
            score += 5
            feedback_parts.append("Token file exists (but old timestamp).")
    else:
        feedback_parts.append("Token file missing.")

    # Criterion 2: Token Authenticates (30 pts)
    if token_info.get("authenticates"):
        score += 30
        feedback_parts.append("Token authenticates successfully.")
    else:
        status = token_info.get("http_status", 0)
        feedback_parts.append(f"Token failed authentication (HTTP {status}).")

    # Criterion 3: Token Name Found in Config (15 pts)
    if config_info.get("token_name_found"):
        score += 15
        feedback_parts.append("Token named 'automation-token' found in Jenkins config.")
    else:
        feedback_parts.append("Token name 'automation-token' NOT found in Jenkins.")

    # Criterion 4: Jobs File Exists & Valid (20 pts)
    if jobs_info.get("exists"):
        if jobs_info.get("valid_json"):
            score += 20
            feedback_parts.append("Jobs file contains valid JSON.")
        else:
            score += 5
            feedback_parts.append("Jobs file exists but invalid JSON.")
    else:
        feedback_parts.append("Jobs file missing.")

    # Criterion 5: Jobs Content Correct (20 pts)
    if jobs_info.get("matches_actual_count"):
        score += 20
        feedback_parts.append("Jobs list matches actual Jenkins jobs.")
    elif jobs_info.get("jobs_count", 0) > 0:
        score += 10
        feedback_parts.append("Jobs list contains data but count mismatch.")
    
    # Calculate success
    passed = score >= 70 and token_info.get("authenticates")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }