#!/usr/bin/env python3
"""
Verifier for setup_shared_custody_volume task.

Verifies:
1. Volume file existence and size.
2. Security Enforcement: Volume must NOT mount with password alone.
3. Access Control: Volume MUST mount with specific keyfiles in correct order.
4. Order Sensitivity: Verifies that wrong order fails (implicit in cryptographic nature of VeraCrypt keyfiles).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shared_custody_volume(traj, env_info, task_info):
    """
    Verify the Shared Custody Volume creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Error reading result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task result from environment."}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Scoring Logic
    score = 0
    feedback_parts = []
    
    # 1. Volume Exists (20 pts)
    volume_exists = result.get('volume_exists', False)
    volume_size = result.get('volume_size_bytes', 0)
    
    if volume_exists and volume_size > 1024 * 1024: # > 1MB at least
        score += 20
        feedback_parts.append("Volume file created successfully")
    else:
        feedback_parts.append("Volume file missing or empty")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Keyfile Enforcement (20 pts)
    # Must FAIL with password only
    mount_pwd_only = result.get('mount_password_only')
    if mount_pwd_only == "failed":
        score += 20
        feedback_parts.append("Keyfile requirement enforced (password-only mount failed)")
    elif mount_pwd_only == "success":
        feedback_parts.append("Security Fail: Volume mounted with password only (keyfiles not added correctly)")
    
    # 3. Successful Mount with Correct Order (40 pts)
    mount_correct = result.get('mount_correct_keys')
    if mount_correct == "success":
        score += 40
        feedback_parts.append("Volume mounted successfully with correct keyfiles")
    else:
        feedback_parts.append("Failed to mount volume with the required keyfiles/password")

    # 4. Order Sensitivity Check (20 pts)
    # The 'mount_wrong_order' should fail. If it succeeds, it implies the agent might have added keyfiles
    # but maybe VeraCrypt behavior with order is subtle? 
    # Actually, VeraCrypt keyfile order MATTERS. If A+B works, B+A will NOT work.
    # If mount_wrong_order == failed, it confirms the hash is order-dependent as expected.
    # If mount_wrong_order == success, something is weird (maybe agent didn't use keyfiles, but we checked that in step 2).
    # Step 2 checks if NO keyfiles work.
    # If Step 3 works and Step 2 fails, we know keyfiles are used.
    # If Step 4 fails, it confirms strict ordering.
    
    mount_wrong = result.get('mount_wrong_order')
    if mount_wrong == "failed" and mount_correct == "success":
        score += 20
        feedback_parts.append("Keyfile order is strictly enforced")
    elif mount_wrong == "success":
        # This shouldn't happen with VeraCrypt unless the files are identical or empty, but we provided distinct files.
        # Or if the agent found a way to bypass.
        feedback_parts.append("Warning: Keyfile order did not affect mounting (unexpected)")

    # Final Pass Calculation
    # Pass if volume exists, password-only fails, and correct-keys succeeds.
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }