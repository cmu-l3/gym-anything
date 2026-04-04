#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_volume_credentials(traj, env_info, task_info):
    """
    Verify that the volume credentials were reset correctly.
    
    Scoring:
    - 50 pts: Volume mounts with new password (Archive2025) and no PIM/Keyfile.
    - 30 pts: Data integrity (volume was not just reformatted/replaced).
    - 20 pts: Old credentials no longer work.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    passed = False

    # 1. Volume must exist
    if not result.get("volume_exists", False):
        return {"passed": False, "score": 0, "feedback": "Volume file was deleted or lost."}

    # 2. New credentials check (50 pts)
    if result.get("new_creds_work", False):
        score += 50
        feedback_parts.append("✅ Volume accepts new standard credentials.")
    else:
        feedback_parts.append("❌ Volume does not accept 'Archive2025' with default PIM/No Keyfile.")

    # 3. Data Integrity check (30 pts)
    if result.get("data_intact", False):
        score += 30
        feedback_parts.append("✅ Data preserved inside volume.")
    elif result.get("new_creds_work", False):
        feedback_parts.append("⚠️ Volume opens, but data is missing (possible reformat).")
    else:
        feedback_parts.append("❌ Cannot verify data integrity (mount failed).")

    # 4. Old Credentials check (20 pts)
    if result.get("old_creds_fail", False):
        score += 20
        feedback_parts.append("✅ Old credentials successfully removed.")
    else:
        feedback_parts.append("❌ Old credentials still work (Password was not changed).")

    # Pass threshold: 80 points (Must open with new pass AND have data)
    if score >= 80:
        passed = True
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }