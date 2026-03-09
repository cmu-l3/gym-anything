#!/usr/bin/env python3
"""
Verifier for batch_deploy_archive task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_deploy_archive(traj, env_info, task_info):
    """
    Verify that the archive was uploaded and extracted correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
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
    
    task_start = result.get('task_start', 0)
    
    # Check Artifact 1: commons-lang3.jar
    art1 = result.get('artifact_lang3', {})
    exp_sha1_1 = result.get('expected_sha1_lang3', '').strip()
    
    if art1.get('exists'):
        # Check creation time anti-gaming
        created = art1.get('created', 0)
        if created > task_start:
            # Check integrity
            sha1 = art1.get('sha1', '').strip()
            if sha1 and exp_sha1_1 and sha1 == exp_sha1_1:
                score += 40
                feedback_parts.append("commons-lang3.jar deployed and extracted correctly.")
            else:
                score += 20
                feedback_parts.append(f"commons-lang3.jar found but checksum mismatch (Expected: {exp_sha1_1}, Got: {sha1}).")
        else:
            feedback_parts.append("commons-lang3.jar exists but has stale timestamp (pre-task).")
    else:
        feedback_parts.append("commons-lang3.jar NOT found at expected path 'libs/commons-lang3.jar'.")

    # Check Artifact 2: commons-io.jar
    art2 = result.get('artifact_io', {})
    exp_sha1_2 = result.get('expected_sha1_io', '').strip()
    
    if art2.get('exists'):
        created = art2.get('created', 0)
        if created > task_start:
            sha1 = art2.get('sha1', '').strip()
            if sha1 and exp_sha1_2 and sha1 == exp_sha1_2:
                score += 40
                feedback_parts.append("commons-io.jar deployed and extracted correctly.")
            else:
                score += 20
                feedback_parts.append(f"commons-io.jar found but checksum mismatch (Expected: {exp_sha1_2}, Got: {sha1}).")
        else:
            feedback_parts.append("commons-io.jar exists but has stale timestamp.")
    else:
        feedback_parts.append("commons-io.jar NOT found at expected path 'libs/commons-io.jar'.")

    # Check for integrity bonus (implicitly covered above, but let's explicitly award for clean execution)
    # If both files are perfect, add remaining 20 points
    if score == 80:
        score += 20
        feedback_parts.append("Full integrity verified.")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }