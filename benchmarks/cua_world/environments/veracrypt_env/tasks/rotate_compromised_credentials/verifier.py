#!/usr/bin/env python3
"""
Verifier for rotate_compromised_credentials task.

Verification Logic:
1. Security: Old credentials must NOT work (30 pts).
2. Access: New credentials MUST work (30 pts).
3. Key Hygiene: New keyfile must exist and be unique (15 pts).
4. Cleanup: Old compromised keyfile must be deleted (15 pts).
5. State: Volume should be mounted at the end (10 pts).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rotate_compromised_credentials(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Security Check (Lockout)
    if result.get("negative_test_passed", False):
        if result.get("mixed_test_passed", False):
            score += 30
            feedback_parts.append("Security: Old credentials successfully locked out")
        else:
            score += 15
            feedback_parts.append("Security: Password changed, but old keyfile still works (Partial)")
    else:
        feedback_parts.append("Security FAIL: Old credentials still work")

    # 2. Access Check
    if result.get("positive_test_passed", False):
        score += 30
        feedback_parts.append("Access: New credentials work")
    else:
        feedback_parts.append("Access FAIL: New credentials do not work")

    # 3. Key Generation
    if result.get("new_keyfile_exists", False) and result.get("keys_are_different", False):
        score += 15
        feedback_parts.append("Keyfile: Generated unique new key")
    elif result.get("new_keyfile_exists", False):
        score += 5
        feedback_parts.append("Keyfile: Created, but identical to old key (bad security)")
    else:
        feedback_parts.append("Keyfile: Not created")

    # 4. Cleanup
    if result.get("old_keyfile_deleted", False):
        score += 15
        feedback_parts.append("Cleanup: Compromised key deleted")
    else:
        feedback_parts.append("Cleanup: Compromised key still exists")

    # 5. Final State
    if result.get("is_mounted_at_end", False):
        score += 10
        feedback_parts.append("State: Volume left mounted")
    else:
        feedback_parts.append("State: Volume not mounted at end")

    # Pass threshold: Must secure the volume (lockout) and have access
    passed = (score >= 75) and result.get("negative_test_passed") and result.get("positive_test_passed")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }