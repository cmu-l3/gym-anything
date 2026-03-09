#!/usr/bin/env python3
"""Verifier for secure_visual_migration task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_visual_migration(traj, env_info, task_info):
    """
    Verify the secure visual migration task.
    
    Criteria:
    1. New volume exists (20 pts)
    2. Volume is secured correctly (Mounts with correct Password + Mountain Key + PIM 485) (40 pts)
       - Partial credit if mountable but wrong PIM
    3. Data transferred successfully (30 pts)
    4. Clean state (all volumes dismounted) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    score = 0
    feedback_parts = []
    
    # Criterion 1: Volume Exists (20 pts)
    if result.get("volume_exists"):
        score += 20
        feedback_parts.append("New volume created")
    else:
        return {"passed": False, "score": 0, "feedback": "New volume not found"}

    # Criterion 2: Security Configuration (40 pts)
    if result.get("mount_success"):
        if result.get("pim_correct") and result.get("keyfile_correct"):
            score += 40
            feedback_parts.append("Security config correct (Password+Keyfile+PIM)")
        elif result.get("keyfile_correct"):
            score += 20
            feedback_parts.append("Partial Security: Correct Keyfile used, but PIM incorrect")
        else:
            score += 10
            feedback_parts.append("Partial Security: Volume mountable but security params incorrect")
    else:
        feedback_parts.append("Volume failed to mount with expected credentials")

    # Criterion 3: Data Transfer (30 pts)
    if result.get("files_transferred"):
        score += 30
        feedback_parts.append("All files transferred successfully")
    elif result.get("file_count", 0) > 0:
        score += 15
        feedback_parts.append("Some files transferred but incomplete")
    else:
        feedback_parts.append("No files transferred")

    # Criterion 4: Cleanup (10 pts)
    if result.get("cleanup_done"):
        score += 10
        feedback_parts.append("Cleanup correct (volumes dismounted)")
    else:
        feedback_parts.append("Volumes left mounted")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }