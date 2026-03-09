#!/usr/bin/env python3
"""
Verifier for deactivate_dormant_users task.

Logic:
- Dormant users (>90 days or Never) MUST be status 2 (Disabled).
- Active users (<90 days) MUST remain status 1 (Active).
- No users should be deleted (count check).
- Admin must remain active.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_dormant_users(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    users = result.get('users', {})
    
    # 1. Verify Dormant User 1 (Old Login) - Should be Disabled (status != 1)
    # FreeScout: 1=Active, 2=Disabled. We give points for NOT being 1 (Active).
    u_old = users.get('dormant_old', {})
    if u_old.get('exists', 0) == 1:
        if u_old.get('status') != 1:
            score += 30
            feedback_parts.append("Dormant user (old login) deactivated")
        else:
            feedback_parts.append("FAIL: Dormant user (old login) is still active")
    else:
        feedback_parts.append("FAIL: Dormant user (old login) was deleted")

    # 2. Verify Dormant User 2 (Never Logged In) - Should be Disabled
    u_never = users.get('dormant_never', {})
    if u_never.get('exists', 0) == 1:
        if u_never.get('status') != 1:
            score += 30
            feedback_parts.append("Dormant user (never logged in) deactivated")
        else:
            feedback_parts.append("FAIL: Dormant user (never logged in) is still active")
    else:
        feedback_parts.append("FAIL: Dormant user (never logged in) was deleted")

    # 3. Verify Active User 1 (Recent) - Should stay Active (status == 1)
    u_recent = users.get('active_recent', {})
    if u_recent.get('status') == 1:
        score += 10
        feedback_parts.append("Recent user preserved")
    else:
        feedback_parts.append("FAIL: Recent user was incorrectly deactivated")

    # 4. Verify Active User 2 (Borderline) - Should stay Active
    u_border = users.get('active_borderline', {})
    if u_border.get('status') == 1:
        score += 10
        feedback_parts.append("Borderline active user preserved")
    else:
        feedback_parts.append("FAIL: Borderline active user was incorrectly deactivated")

    # 5. Verify Admin - Should stay Active
    u_admin = users.get('admin', {})
    if u_admin.get('status') == 1:
        score += 10
        feedback_parts.append("Admin account preserved")
    else:
        feedback_parts.append("FAIL: Admin account was deactivated (self-lockout!)")

    # 6. Verify No Deletions (Count match)
    initial_count = int(result.get('initial_user_count', 0))
    current_count = int(result.get('current_user_count', 0))
    if current_count == initial_count:
        score += 10
        feedback_parts.append("No users deleted")
    else:
        feedback_parts.append(f"User count changed ({initial_count}->{current_count})")

    # VLM Verification (Trajectory check)
    # Check if we see the users list being manipulated
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_response = query_vlm(
                images=frames,
                prompt="Does this sequence show a user deactivating accounts in a user management list? Look for clicks on status toggles, edit buttons, or 'Deactivate' options. Answer yes or no."
            )
            if vlm_response and "yes" in vlm_response.lower():
                # Just a small validation bonus/tie-breaker logic could go here, 
                # but currently scoring is maxed at 100 via DB checks.
                # We log it for auditing.
                logging.info("VLM confirmed visual workflow")
    except Exception as e:
        logging.warning(f"VLM check failed: {e}")

    # Pass if score >= 70 (Must catch both dormant users + preserve some active ones)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }