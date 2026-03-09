#!/usr/bin/env python3
"""
Verifier for chained_volume_access_workflow task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chained_volume_access_workflow(traj, env_info, task_info):
    """
    Verify the sequential recovery of data from daisy-chained volumes.
    
    Scoring:
    - 70 points: Recovered file exists and matches expected content (MD5).
    - 30 points: Secure cleanup (all volumes dismounted).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_md5 = metadata.get('expected_md5', 'e5b85368670878146958428286594247')

    score = 0
    feedback_parts = []
    
    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Criterion 1: Target File Recovery (70 pts)
    file_exists = result.get('target_file_exists', False)
    file_md5 = result.get('target_file_md5', '')
    created_during = result.get('file_created_during_task', False)

    if file_exists:
        if file_md5 == expected_md5:
            if created_during:
                score += 70
                feedback_parts.append("✅ Data recovered successfully (Checksum verified)")
            else:
                score += 35
                feedback_parts.append("⚠️ Data correct but file timestamp predates task (did you overwrite?)")
        else:
            score += 20
            feedback_parts.append(f"❌ Data recovered but checksum mismatch (Got {file_md5[:6]}..., Expected {expected_md5[:6]}...)")
    else:
        feedback_parts.append("❌ Target file 'recovered_coordinates.csv' not found")

    # Criterion 2: Workspace Cleanup (30 pts)
    is_clean = result.get('is_clean_state', False)
    mount_count = result.get('mounted_volume_count', 0)

    if is_clean:
        score += 30
        feedback_parts.append("✅ Security cleanup successful (All volumes dismounted)")
    else:
        feedback_parts.append(f"❌ Security violation: {mount_count} volume(s) left mounted")

    # Bonus/Penalty feedback (informational)
    if result.get('beta_key_exposed') or result.get('gamma_key_exposed'):
        feedback_parts.append("ℹ️ Note: Intermediate keyfiles were left exposed on the filesystem")

    passed = (score >= 90) # Requires full recovery + reasonable cleanup effort (at least partially)
    
    # Strict pass: Must have recovered data AND dismounted volumes
    if file_md5 != expected_md5:
        passed = False
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }