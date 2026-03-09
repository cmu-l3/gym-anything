#!/usr/bin/env python3
"""
Verifier for prevent_artifact_overwrite task.

Logic:
1. Immutability Check: Attempting to overwrite an existing artifact must fail (HTTP 403 Forbidden or 409 Conflict).
2. Writable Check: Attempting to write a NEW artifact must succeed (HTTP 201 Created).
   - This ensures the agent didn't just make the repository read-only or delete it.
3. Integrity Check: The original artifact must still exist.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prevent_artifact_overwrite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
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

    # Extract metrics
    overwrite_code = result.get('overwrite_http_code', 0)
    new_deploy_code = result.get('new_deploy_http_code', 0)
    artifact_exists = result.get('artifact_exists', False)

    score = 0
    feedback_parts = []
    
    # Criteria 1: Immutability (Overwrite should fail)
    # 403 Forbidden is the standard response for redeploy prevention
    # 409 Conflict is also possible depending on specific config/version
    if overwrite_code in [403, 409]:
        score += 50
        feedback_parts.append(f"SUCCESS: Overwrite prevented (HTTP {overwrite_code}).")
    elif overwrite_code in [200, 201]:
        feedback_parts.append(f"FAIL: Overwrite still allowed (HTTP {overwrite_code}).")
    else:
        feedback_parts.append(f"FAIL: Unexpected overwrite response (HTTP {overwrite_code}).")

    # Criteria 2: Repo Writeability (New deploy should succeed)
    if new_deploy_code == 201:
        score += 30
        feedback_parts.append("SUCCESS: Repository remains writable for new artifacts.")
    else:
        feedback_parts.append(f"FAIL: Repository is not writable for new artifacts (HTTP {new_deploy_code}). Did you make it Read-Only?")

    # Criteria 3: Integrity (Original artifact exists)
    if artifact_exists:
        score += 20
        feedback_parts.append("SUCCESS: Original artifact intact.")
    else:
        feedback_parts.append("FAIL: Original artifact is missing.")

    # Pass logic: Must prevent overwrite AND allow new writes
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }