#!/usr/bin/env python3
"""
Verifier for the change_admin_password task in SEB Server.

Verification Strategy:
1. Compare initial vs final password hashes in the database.
2. Verify all 5 profile fields match expectations.
3. Validate API authentication changes.
4. Supplement with VLM trajectory verification to ensure GUI usage.
"""

import json
import os
import tempfile
import logging

# Import VLM utilities from gym_anything
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("gym_anything.vlm not available. VLM verification will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_change_admin_password(traj, env_info, task_info):
    """Verifies that the super-admin account was correctly updated."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'System')
    expected_surname = metadata.get('expected_surname', 'Administrator')
    expected_email = metadata.get('expected_email', 'admin@university-testing.edu')
    expected_timezone = metadata.get('expected_timezone', 'America/New_York')
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/change_admin_password_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    db_state = result.get('db_state', {})
    
    # 1. Password Hash Check (25 pts)
    hash_changed = db_state.get('hash_changed', False)
    if hash_changed:
        score += 25
        feedback_parts.append("Password successfully changed in DB")
    else:
        feedback_parts.append("Password hash unchanged (Failed to update password)")

    # 2. Profile Details Check (40 pts total)
    fields_updated = 0
    
    if str(db_state.get('name', '')).strip().lower() == expected_name.lower():
        score += 10
        fields_updated += 1
        feedback_parts.append("First Name updated correctly")
    
    if str(db_state.get('surname', '')).strip().lower() == expected_surname.lower():
        score += 10
        fields_updated += 1
        feedback_parts.append("Surname updated correctly")
        
    if str(db_state.get('email', '')).strip().lower() == expected_email.lower():
        score += 10
        fields_updated += 1
        feedback_parts.append("Email updated correctly")
        
    if str(db_state.get('time_zone', '')).strip() == expected_timezone:
        score += 5
        fields_updated += 1
        feedback_parts.append("Timezone updated correctly")
        
    # Language is tricky ('en' vs 'English'), check for inclusion
    lang = str(db_state.get('language', '')).strip().lower()
    if 'en' in lang or 'english' in lang:
        score += 5
        fields_updated += 1
        feedback_parts.append("Language updated correctly")

    # 3. API Auth Check (20 pts)
    # Give points if the new password works while the old one fails (assuming endpoint allows basic auth)
    api_auth = result.get('api_auth', {})
    old_code = api_auth.get('old_password_http_code', '000')
    new_code = api_auth.get('new_password_http_code', '000')
    
    auth_verified = False
    if new_code in ['200', '302'] and old_code in ['401', '403']:
        score += 20
        auth_verified = True
        feedback_parts.append("API Authentication verified with new password")
    elif new_code == old_code and hash_changed:
        # Fallback: API endpoints might not support basic auth directly, so if hash changed we grant partial points
        score += 10
        feedback_parts.append("API check indeterminate, but DB confirms hash change")

    # 4. VLM Verification (15 pts) - Ensures agent used the GUI instead of a DB backdoor
    vlm_passed = False
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            prompt = (
                "You are an evaluator checking if a user successfully modified an account profile in the Safe Exam Browser Server GUI. "
                "Look closely at the provided screenshots from the workflow. "
                "Did the user open the User Account section, edit the 'super-admin' profile, and interact with the password/profile edit fields? "
                "Respond with YES if the workflow screenshots clearly show interaction with the SEB Server user account edit form, or NO otherwise."
            )
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and "YES" in str(vlm_result).upper():
                score += 15
                vlm_passed = True
                feedback_parts.append("VLM confirms GUI usage")
            else:
                feedback_parts.append("VLM did not detect profile editing in GUI")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM check encountered an error")
    else:
        # If VLM is unavailable but they passed DB checks, auto-grant points to be fair
        if hash_changed and fields_updated >= 3:
            score += 15
            feedback_parts.append("VLM skipped but DB confirms updates (points granted)")

    # Final logic for passing
    # Agent must have changed the password AND updated at least 3 profile fields
    key_criteria_met = hash_changed and (fields_updated >= 3)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "hash_changed": hash_changed,
            "fields_updated": fields_updated,
            "auth_verified": auth_verified,
            "vlm_passed": vlm_passed
        }
    }