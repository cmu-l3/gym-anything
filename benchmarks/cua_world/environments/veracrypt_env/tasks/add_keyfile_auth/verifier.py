#!/usr/bin/env python3
"""
Verifier for add_keyfile_auth task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_keyfile_auth(traj, env_info, task_info):
    """
    Verify that the user added a keyfile to the volume authentication.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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
    
    # 1. Keyfile Created (10 pts)
    if result.get("keyfile_exists") and result.get("keyfile_size_bytes", 0) >= 64:
        score += 10
        feedback_parts.append("Keyfile created")
    else:
        feedback_parts.append("Keyfile missing or invalid")

    # 2. Volume Mounted at End (10 pts)
    if result.get("volume_mounted_at_end"):
        score += 10
        feedback_parts.append("Volume left mounted")
    else:
        feedback_parts.append("Volume NOT mounted at end")

    # 3. Data Integrity (20 pts)
    if result.get("data_intact"):
        score += 20
        feedback_parts.append("Data files intact")
    elif result.get("data_files_found_count", 0) > 0:
        score += 10
        feedback_parts.append("Partial data found")
    else:
        feedback_parts.append("Data missing/inaccessible")

    # 4. Listing File (10 pts)
    if result.get("listing_file_exists") and result.get("listing_content_match"):
        score += 10
        feedback_parts.append("Content listing created")
    elif result.get("listing_file_exists"):
        score += 5
        feedback_parts.append("Listing file exists but content mismatch")

    # 5. SECURITY CHECK: Password Only Fails (30 pts)
    # This is the core of the task: did they actually ADD the keyfile requirement?
    pwd_only_res = result.get("auth_test_password_only")
    if pwd_only_res == "access_denied_correctly":
        score += 30
        feedback_parts.append("Security enforced (Password-only mount failed)")
    elif pwd_only_res == "mounted_unexpectedly":
        feedback_parts.append("Security FAIL: Volume still mountable with password only")
    else:
        feedback_parts.append("Security test inconclusive")

    # 6. FUNCTIONALITY CHECK: Full Creds Work (20 pts)
    # Did they break the volume?
    full_auth_res = result.get("auth_test_full_creds")
    if full_auth_res == "success":
        score += 20
        feedback_parts.append("Authentication successful with new credentials")
    else:
        feedback_parts.append("Authentication FAILED with new credentials")

    # Pass logic
    # Must have enforced security AND kept volume working
    passed = (score >= 70 and 
              pwd_only_res == "access_denied_correctly" and 
              full_auth_res == "success")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }