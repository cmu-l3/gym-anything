#!/usr/bin/env python3
"""Verifier for implement_cryptographic_erasure task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cryptographic_erasure(traj, env_info, task_info):
    """
    Verify that the agent implemented and executed the cryptographic erasure.

    Criteria:
    1. Panic script exists (20 pts)
    2. Volume file still exists (not deleted) (20 pts)
    3. Primary Header modified (30 pts)
    4. Backup Header modified (30 pts)
    
    Penalties:
    - If mount succeeds, automatic fail (Headers not destroyed).
    - If file size changed significantly, penalty (should preserve file structure).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/erasure_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Script Existence (20 pts)
    if result.get('script_exists'):
        score += 20
        feedback_parts.append("Panic script created")
    else:
        feedback_parts.append("Panic script NOT found")

    # 2. File Preservation (20 pts)
    if result.get('volume_file_exists'):
        if result.get('volume_size_preserved'):
            score += 20
            feedback_parts.append("Volume file preserved with correct size")
        else:
            score += 10
            feedback_parts.append("Volume file exists but size changed")
    else:
        feedback_parts.append("Volume file was DELETED (Task required cryptographic erasure, not file deletion)")
        return {"passed": False, "score": 0, "feedback": "Volume file was deleted. Task required header destruction only."}

    # 3. Primary Header Wiped (30 pts)
    if result.get('primary_header_changed'):
        score += 30
        feedback_parts.append("Primary header successfully wiped")
    else:
        feedback_parts.append("Primary header NOT modified")

    # 4. Backup Header Wiped (30 pts)
    if result.get('backup_header_changed'):
        score += 30
        feedback_parts.append("Backup header successfully wiped")
    else:
        feedback_parts.append("Backup header NOT modified (Recovery still possible!)")

    # Critical Failure Check: Mount Succeeded
    if result.get('mount_succeeded'):
        score = 0
        feedback_parts = ["CRITICAL FAIL: Volume can still be mounted! Erasure failed."]
        
    passed = score >= 80  # Requires script, file preservation, and both headers wiped
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }