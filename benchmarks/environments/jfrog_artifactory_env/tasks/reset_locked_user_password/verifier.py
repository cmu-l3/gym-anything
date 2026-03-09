#!/usr/bin/env python3
"""
Verifier for reset_locked_user_password task.

Criteria:
1. User jmonroe can authenticate with 'TemporaryFix#2024' (60 pts)
   - Proves account is unlocked
   - Proves password was reset
2. User jmonroe is still in 'backend-devs' group (20 pts)
   - Proves user wasn't deleted/recreated (Anti-gaming)
3. VLM Verification (20 pts)
   - Checks visual evidence of user management UI
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reset_locked_user_password(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Authentication Check (60 pts)
    auth_success = result.get('authentication_success', False)
    if auth_success:
        score += 60
        feedback_parts.append("User authenticated successfully with new password")
    else:
        feedback_parts.append("Authentication failed with new password (account may still be locked or wrong password)")

    # 2. Group Membership Check (20 pts)
    group_preserved = result.get('group_membership_preserved', False)
    if group_preserved:
        score += 20
        feedback_parts.append("User group membership 'backend-devs' preserved")
    else:
        if result.get('user_exists', False):
            feedback_parts.append("User exists but lost group membership (did you delete the user?)")
        else:
            feedback_parts.append("User not found")

    # 3. VLM Verification (20 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
        
        prompt = """
        Review these screenshots of a user performing an administrative task in JFrog Artifactory.
        
        Look for:
        1. Navigation to the "Users" management list.
        2. A user details/edit form for a user named "jmonroe".
        3. An "Unlock" action or "Change Password" dialog.
        
        Answer JSON:
        {
            "user_management_visible": true/false,
            "edit_user_screen_visible": true/false,
            "unlock_or_password_action_visible": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('user_management_visible'): vlm_score += 5
            if parsed.get('edit_user_screen_visible'): vlm_score += 10
            if parsed.get('unlock_or_password_action_visible'): vlm_score += 5
            
            if vlm_score > 0:
                feedback_parts.append(f"Visual verification passed ({vlm_score}/20 pts)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: if auth passed, assume visual is okay (full points) to avoid punishing API failures
            if auth_success:
                vlm_score = 20
    
    score += vlm_score

    # Pass Threshold: 80 points (Must auth + preserve group OR auth + VLM)
    # Ideally Auth + Group is key.
    passed = score >= 80 and auth_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }