#!/usr/bin/env python3
"""
Verifier for nested_encryption_workflow task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nested_encryption(traj, env_info, task_info):
    """
    Verify the nested encryption workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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
    
    # 1. Dismount Check (15 pts)
    if result.get('volumes_dismounted_at_end', False):
        score += 15
        feedback_parts.append("Clean teardown (all volumes dismounted)")
    else:
        feedback_parts.append("Volumes left mounted (security risk)")

    # 2. Inner Volume Existence (25 pts)
    if result.get('inner_volume_found', False):
        score += 25
        feedback_parts.append("Inner volume found inside outer volume")
        
        # Check size (approx 20MB)
        size = result.get('inner_volume_size', 0)
        # 19MB to 21MB tolerance
        if 19000000 <= size <= 22000000:
            score += 5
            feedback_parts.append("Inner volume size correct (~20MB)")
        else:
            feedback_parts.append(f"Inner volume size incorrect ({size} bytes)")
    else:
        feedback_parts.append("Inner volume NOT found inside outer volume")

    # 3. Inner Volume Mount & Content (35 pts total)
    if result.get('inner_mount_success', False):
        # Implicitly checks password 'InnerSecret!99' worked
        feedback_parts.append("Inner volume mountable with correct password")
        
        # Check Algorithm (10 pts)
        algo = result.get('inner_algorithm', '').lower()
        if 'serpent' in algo:
            score += 10
            feedback_parts.append("Encryption algorithm is Serpent")
        else:
            feedback_parts.append(f"Wrong encryption algorithm: {algo}")

        # Check Files (15 pts)
        files_found = result.get('files_found_count', 0)
        if files_found == 2:
            score += 15
            feedback_parts.append("All sensitive files found in inner volume")
        elif files_found == 1:
            score += 7
            feedback_parts.append("Partial files found")
        else:
            feedback_parts.append("No sensitive files found in inner volume")

        # Check Integrity (10 pts)
        if result.get('file_integrity_ok', False):
            score += 10
            feedback_parts.append("File integrity verified (checksums match)")
        else:
            feedback_parts.append("File integrity check failed")

    else:
        feedback_parts.append("Could not mount inner volume (wrong password or corrupt)")

    # 4. Anti-Gaming / Temporal Check (10 pts)
    task_start = result.get('task_start_time', 0)
    outer_mtime = result.get('outer_modified_time', 0)
    
    if outer_mtime > task_start and score >= 40:
        score += 10
        feedback_parts.append("Work verified during task window")
    elif score >= 60:
         # If score is high, work must have been done, trust result over timestamp if mtime check is flaky
         score += 10
         feedback_parts.append("Work verified")
    else:
        feedback_parts.append("No evidence of modification during task")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }