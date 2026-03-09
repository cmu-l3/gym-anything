#!/usr/bin/env python3
"""
Verifier for setup_split_knowledge_volume task.

Verifies:
1. Volume creation at correct path.
2. Positive Access: Volume mounts with Password + 3 Keyfiles.
3. Negative Access: Volume FAILS to mount with missing keyfiles (Split Knowledge enforcement).
4. Data Protection: Sensitive seed file moved inside volume.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_split_knowledge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification results from environment"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Volume Exists (10 pts)
    if result.get("volume_exists"):
        score += 10
        feedback_parts.append("Volume created successfully")
    else:
        feedback_parts.append("Volume file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Positive Access Check (30 pts)
    if result.get("positive_mount_success"):
        score += 30
        feedback_parts.append("Volume mounts with correct credentials")
    else:
        feedback_parts.append("Volume failed to mount with Password + 3 Keyfiles")

    # 3. Split Knowledge Enforcement (Negative Checks) (30 pts)
    # The volume MUST NOT mount if a keyfile is missing
    anti_gaming_pass = True
    if result.get("negative_missing_key_mounted"):
        anti_gaming_pass = False
        feedback_parts.append("SECURITY FAIL: Volume mounted with missing keyfiles (Split Knowledge not enforced)")
    
    if result.get("negative_pass_only_mounted"):
        anti_gaming_pass = False
        feedback_parts.append("SECURITY FAIL: Volume mounted with password only (No keyfiles used)")

    if anti_gaming_pass:
        score += 30
        feedback_parts.append("Access control correctly enforces keyfile requirement")
    else:
        # Severe penalty for failing security requirement
        score = min(score, 40) 

    # 4. Data Protection (20 pts)
    if result.get("seed_found_inside"):
        score += 20
        feedback_parts.append("Seed file secured inside volume")
    else:
        feedback_parts.append("Seed file not found inside volume")

    # 5. Cleanup (10 pts)
    if result.get("seed_removed_from_source"):
        score += 10
        feedback_parts.append("Source file cleaned up")
    else:
        feedback_parts.append("Source file still exists (not moved)")

    # Pass Threshold: 70
    # Must have positive access AND strict enforcement
    passed = score >= 70 and anti_gaming_pass and result.get("positive_mount_success")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }