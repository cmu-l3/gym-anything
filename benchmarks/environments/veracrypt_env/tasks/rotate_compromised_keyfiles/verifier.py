#!/usr/bin/env python3
"""
Verifier for rotate_compromised_keyfiles task.

SCORING CRITERIA:
1. New Keyfile Created (10 pts)
2. Volume Accessible with NEW credentials (40 pts)
3. Volume NOT Accessible with OLD credentials (30 pts)
4. In-Place Modification (Inode preserved) (20 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rotate_keyfiles(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. New Keyfile Created (10 pts)
    if result.get("new_key_exists", False):
        score += 10
        feedback_parts.append("New keyfile created (+10)")
    else:
        feedback_parts.append("New keyfile NOT found")

    # 2. Access with New Key (40 pts)
    if result.get("mount_new_success", False):
        score += 40
        feedback_parts.append("Volume accessible with new key (+40)")
        
        # Bonus check: data integrity
        if result.get("data_intact", False):
            feedback_parts.append("(Data integrity verified)")
        else:
            feedback_parts.append("(WARNING: Data may be missing)")
    else:
        feedback_parts.append("Failed to access volume with new key")

    # 3. Old Key Revoked (30 pts)
    # Success means mount_old_success is FALSE (we want it to fail)
    if not result.get("mount_old_success", True):
        score += 30
        feedback_parts.append("Old key successfully revoked (+30)")
    else:
        if result.get("mount_old_success", False):
            feedback_parts.append("CRITICAL: Volume still opens with compromised key!")
        else:
            # This case handles if the mount failed for other reasons, 
            # but usually mount_old_success=True is the failure condition here.
            # If the script returned false, it means mount failed, which is good.
            pass

    # 4. In-Place Modification (20 pts)
    if result.get("inode_match", False):
        score += 20
        feedback_parts.append("In-place header modification confirmed (+20)")
    else:
        feedback_parts.append("Volume appears re-created (inode changed) - prefer in-place modification")

    # Pass Threshold: 80 points
    # This requires at least: New Key (10) + New Access (40) + Old Revoked (30) = 80
    # In-place mod is preferred but not strictly blocking if they did the crypto right manually
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }