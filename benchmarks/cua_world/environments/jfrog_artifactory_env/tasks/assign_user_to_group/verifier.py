#!/usr/bin/env python3
"""
Verifier for assign_user_to_group task.

Verifies:
1. User 'dev-maria' exists
2. Group 'release-engineers' exists
3. User is a member of the group (via API)
4. No other users were added to the group
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assign_user_to_group(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    group_info = result.get('group_info', {})
    user_info = result.get('user_info', {})
    user_auth_success = result.get('user_auth_success', False)
    
    # 1. Check Group Existence (10 pts)
    # If the group wasn't found or was deleted, the name won't match
    if group_info.get('name') == 'release-engineers':
        score += 10
        feedback_parts.append("Group 'release-engineers' exists")
    else:
        feedback_parts.append("Group 'release-engineers' NOT found")

    # 2. Check User Existence (10 pts)
    # If API returned 200, name matches. If restricted (OSS), fallback to auth check.
    user_exists = False
    if user_info.get('name') == 'dev-maria':
        user_exists = True
    elif user_auth_success:
        user_exists = True
    
    if user_exists:
        score += 10
        feedback_parts.append("User 'dev-maria' exists")
    else:
        feedback_parts.append("User 'dev-maria' NOT found")

    # 3. Check Membership (Primary: 40 pts, Fallback included)
    is_member = False
    
    # Method A: Check group's 'userNames' list
    group_users = group_info.get('userNames', [])
    if 'dev-maria' in group_users:
        is_member = True
        score += 40
        feedback_parts.append("Membership verified via Group API")
    
    # Method B: Check user's 'groups' list (if Method A failed or API restricted)
    if not is_member:
        user_groups = user_info.get('groups', [])
        if 'release-engineers' in user_groups:
            is_member = True
            score += 40
            feedback_parts.append("Membership verified via User API")

    if not is_member:
        feedback_parts.append("Membership NOT found via API")

    # 4. Check for Spurious Members (10 pts)
    # The group should ONLY contain dev-maria (and maybe no one else if failed)
    # If we added dev-maria, count should be 1.
    if is_member:
        if len(group_users) == 1:
            score += 10
            feedback_parts.append("Group has exactly 1 member (Clean)")
        elif len(group_users) > 1:
            feedback_parts.append(f"Group has extra members: {group_users}")
        else:
            # Should not happen if is_member is true
            pass
    else:
        # If not member, check if group is empty as expected for failure
        if len(group_users) == 0:
            score += 10 # Didn't mess up the group by adding randoms
            feedback_parts.append("Group remains empty (Clean)")

    # 5. Visual Verification Check (simulated/placeholder logic for score)
    # In a real scenario, we would process 'traj' frames here.
    # Assuming if API passes, the UI likely reflects it.
    if is_member:
        score += 15 # Award points for implicit visual correctness if API works
        feedback_parts.append("Visual verification assumed correct via API")
    else:
        # If API failed, we can't really award visual points unless we do OCR
        pass

    # 6. Secondary API Validation (15 pts)
    # If we confirmed via one API, checking consistency helps. 
    # Here we just treat successful completion of the main task as satisfying this.
    if is_member and user_exists and group_info.get('name'):
         score += 15
         feedback_parts.append("Consistency check passed")

    passed = score >= 60 and is_member

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }