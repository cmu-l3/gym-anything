#!/usr/bin/env python3
"""
Verifier for Create User Account Task (Bahmni).

Verifies that:
1. A user with the correct username exists.
2. The user has the correct person details (Name, Gender).
3. The user has the assigned Role.
4. The user count actually increased (anti-gaming).
5. VLM verification confirms UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    """
    Verify create_user_account task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'anita.sharma')
    expected_given = metadata.get('expected_given_name', 'Anita')
    expected_family = metadata.get('expected_family_name', 'Sharma')
    expected_gender = metadata.get('expected_gender', 'F')
    expected_role = metadata.get('expected_role', 'Provider')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check User Existence (25 pts)
    user_found = result.get('user_found', False)
    actual_username = result.get('actual_username', '')
    
    if user_found and actual_username == expected_username:
        score += 25
        feedback_parts.append(f"User '{expected_username}' created successfully.")
    elif user_found:
        score += 10
        feedback_parts.append(f"User found but username mismatch ('{actual_username}').")
    else:
        feedback_parts.append("User NOT found.")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": "User was not created. " + " | ".join(feedback_parts)}

    # 2. Check Demographics (30 pts)
    # Name (20 pts)
    actual_given = result.get('actual_given_name', '')
    actual_family = result.get('actual_family_name', '')
    
    name_correct = (actual_given.lower() == expected_given.lower() and 
                    actual_family.lower() == expected_family.lower())
    
    if name_correct:
        score += 20
        feedback_parts.append(f"Name correct ({expected_given} {expected_family}).")
    else:
        feedback_parts.append(f"Name mismatch: got '{actual_given} {actual_family}'.")

    # Gender (10 pts)
    actual_gender = result.get('actual_gender', '')
    if actual_gender == expected_gender:
        score += 10
        feedback_parts.append("Gender correct.")
    else:
        feedback_parts.append(f"Gender mismatch: got '{actual_gender}'.")

    # 3. Check Role (15 pts)
    actual_roles = result.get('actual_roles', [])
    # Check partial match or exact match
    role_found = any(expected_role.lower() in r.lower() for r in actual_roles)
    
    if role_found:
        score += 15
        feedback_parts.append(f"Role '{expected_role}' assigned.")
    else:
        feedback_parts.append(f"Role mismatch: assigned roles were {actual_roles}.")

    # 4. Anti-Gaming: User Count (10 pts)
    initial_count = int(result.get('initial_user_count', 0))
    final_count = int(result.get('final_user_count', 0))
    
    if final_count > initial_count:
        score += 10
        feedback_parts.append("User count increased.")
    else:
        feedback_parts.append(f"WARNING: User count did not increase ({initial_count} -> {final_count}). Did you overwrite a user?")

    # 5. VLM Verification (20 pts)
    # Verify the agent actually used the OpenMRS Admin UI
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an agent performing a task in Bahmni/OpenMRS. "
            "1. Did the agent navigate to the 'Administration' or 'Manage Users' screen? "
            "2. Did the agent fill out a form to create a new person/user? "
            "3. Does the final state look like a success message or the user list? "
            "Return JSON with keys: 'admin_ui_seen' (bool), 'form_filled' (bool), 'confidence' (high/med/low)."
        )
        
        try:
            vlm_resp = query_vlm(images=frames + [final_ss], prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            if vlm_data.get('admin_ui_seen', False):
                score += 10
                feedback_parts.append("VLM confirmed Admin UI usage.")
            
            if vlm_data.get('form_filled', False):
                score += 10
                feedback_parts.append("VLM confirmed form filling.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Grant partial credit if programmatic checks passed strongly
            if score >= 70:
                score += 10
                feedback_parts.append("VLM skipped (error), trusting programmatic checks.")
    else:
        # If no VLM, we rely on programmatic
        feedback_parts.append("VLM not available.")

    # Calculate final result
    passed = score >= 60 and user_found and name_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }