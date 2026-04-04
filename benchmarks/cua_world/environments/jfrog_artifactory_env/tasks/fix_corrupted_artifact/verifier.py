#!/usr/bin/env python3
"""
Verifier for fix_corrupted_artifact task.

Criteria:
1. Artifact must exist at the correct path in Artifactory.
2. Artifact SHA256 must match the valid local file (NOT the corrupted one).
3. VLM verification of the deployment workflow.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_corrupted_artifact(traj, env_info, task_info):
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

    # Extract data
    artifact_exists = result.get('artifact_exists', False)
    hosted_sha256 = result.get('hosted_sha256', '')
    valid_sha256 = result.get('valid_sha256', '')
    bad_initial_sha256 = result.get('bad_initial_sha256', '')
    
    score = 0
    feedback_parts = []
    
    # 1. Check existence (30 pts)
    if artifact_exists:
        score += 30
        feedback_parts.append("Artifact exists at correct path")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Artifact not found in repository at expected path"
        }

    # 2. Check content integrity (70 pts)
    # The hosted checksum MUST match the valid checksum AND NOT match the bad checksum
    if hosted_sha256 == valid_sha256:
        score += 70
        feedback_parts.append("Artifact checksum matches valid file")
    elif hosted_sha256 == bad_initial_sha256:
        score = 0 # Fail completely if it's still the corrupted file
        return {
            "passed": False,
            "score": 0,
            "feedback": "Artifact is still the corrupted version (checksum unchanged)"
        }
    else:
        # It changed, but it's not the right file?
        score += 10 # Partial credit for doing *something*
        feedback_parts.append(f"Artifact checksum changed but does not match valid file (Got {hosted_sha256[:8]}...)")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }