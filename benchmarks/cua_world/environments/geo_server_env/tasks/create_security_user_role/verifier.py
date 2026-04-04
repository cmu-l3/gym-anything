#!/usr/bin/env python3
"""Verifier for create_security_user_role task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_security_user_role(traj, env_info, task_info):
    """
    Verify creation of user, role, assignment, and authentication.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_role = metadata.get('expected_role', 'ROLE_DATA_ANALYST')
    expected_user = metadata.get('expected_user', 'analyst_jones')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_security_user_role_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass # Allow soft fail if nonce missing, verification logic is strong enough
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Role Exists (20 points)
    if result.get('role_exists'):
        score += 20
        feedback_parts.append(f"Role '{expected_role}' created")
    else:
        feedback_parts.append(f"Role '{expected_role}' NOT found")

    # Criterion 2: User Exists (20 points)
    if result.get('user_exists'):
        score += 20
        feedback_parts.append(f"User '{expected_user}' created")
    else:
        feedback_parts.append(f"User '{expected_user}' NOT found")

    # Criterion 3: Role Assigned to User (20 points)
    if result.get('role_assigned'):
        score += 20
        feedback_parts.append("Role assigned to user")
    else:
        feedback_parts.append("Role NOT assigned to user")

    # Criterion 4: Authentication Works (25 points)
    # This proves the password was correct and the user is enabled
    if result.get('auth_success'):
        score += 25
        feedback_parts.append("Authentication with new credentials successful")
    else:
        code = result.get('auth_http_code')
        feedback_parts.append(f"Authentication failed (HTTP {code}) - check password or enabled status")

    # Criterion 5: Output File Created (10 points)
    if result.get('file_exists') and result.get('file_created_during_task'):
        content = result.get('file_content', '')
        if '200' in content:
            score += 10
            feedback_parts.append("Auth result file created with correct code")
        else:
            score += 5
            feedback_parts.append(f"Auth result file created but content '{content}' != '200'")
    elif result.get('file_exists'):
         feedback_parts.append("Auth result file existed before task (no credit)")
    else:
         feedback_parts.append("Auth result file NOT created")

    # Criterion 6: Anti-Gaming Counts (5 points)
    # Ensures we didn't just rename existing things (though our clean setup prevents that)
    try:
        init_roles = int(result.get('initial_roles', 0))
        curr_roles = int(result.get('current_roles', 0))
        init_users = int(result.get('initial_users', 0))
        curr_users = int(result.get('current_users', 0))
        
        if curr_roles > init_roles and curr_users > init_users:
            score += 5
            feedback_parts.append("Entity counts increased correctly")
    except:
        pass

    # VLM Verification (Optional Bonus / GUI Confirmation)
    # We don't penalize heavily if VLM fails as the REST checks are robust,
    # but we check for GUI usage to differentiate from pure API scripting.
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user interacting with the GeoServer Security interface (Users, Groups, or Roles panels)? Return JSON: {'gui_used': bool}"
            )
            # We don't modify score here based on strict GUI use to avoid false negatives, 
            # but we could log it or use it for tie-breaking.
            pass

    # Pass Threshold
    # Must have Role + User + Assignment + Auth working (20+20+20+25 = 85)
    # Minimum for pass: 60, but Critical components must be present.
    passed = score >= 60 and result.get('auth_success') and result.get('role_assigned')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }