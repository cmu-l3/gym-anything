#!/usr/bin/env python3
"""
Verifier for upgrade_volume_security task.

Criteria:
1. Volume must exist.
2. Volume must mount with Default PIM (0), proving PIM was reset.
3. Volume PRF must be HMAC-SHA-512, proving algorithm upgrade.
4. Data must be intact inside the volume.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_upgrade_volume_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
        except Exception as e:
            logger.error(f"Error copying result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error copying result: {e}"}

        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # 1. Volume Exists (10 pts)
    if result.get("volume_exists"):
        score += 10
        feedback_parts.append("Volume file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Volume file missing"}

    # 2. Mounts with Default PIM (30 pts)
    if result.get("mount_success_default_pim"):
        score += 30
        feedback_parts.append("Volume mounts with default PIM (Success)")
    elif result.get("mount_success_legacy_pim"):
        feedback_parts.append("Volume still requires legacy PIM (Task not completed)")
    else:
        feedback_parts.append("Volume failed to mount with either PIM (Possible corruption)")

    # 3. Correct PRF (30 pts)
    detected_prf = result.get("detected_prf", "unknown")
    if "SHA-512" in detected_prf:
        score += 30
        feedback_parts.append(f"PRF updated to {detected_prf}")
    elif "SHA-256" in detected_prf:
        feedback_parts.append(f"PRF is still legacy {detected_prf}")
    else:
        feedback_parts.append(f"PRF unknown or incorrect: {detected_prf}")

    # 4. Data Integrity (30 pts)
    data_status = result.get("data_intact", "false")
    if data_status == "true":
        score += 30
        feedback_parts.append("Data integrity verified")
    elif data_status == "partial":
        score += 15
        feedback_parts.append("Data partially verified (files exist but check incomplete)")
    else:
        feedback_parts.append("Data integrity check failed or volume empty")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }