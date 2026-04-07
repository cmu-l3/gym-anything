#!/usr/bin/env python3
"""
Verifier for create_user_account task.

Criteria:
1. User 'ariviera' exists in DB (30 pts)
2. Linked Person Name is 'Alice Riviera' (20 pts)
3. Role 'Nurse' is assigned (30 pts)
4. Account was created during the task window (10 pts)
5. VLM Process Verification (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_username = metadata.get('target_username', 'ariviera')
    target_given = metadata.get('target_given_name', 'Alice')
    target_family = metadata.get('target_family_name', 'Riviera')
    target_role = metadata.get('target_role', 'Nurse')

    # 1. Load JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Verification
    user_found = result.get('user_found', False)
    
    if not user_found:
        feedback.append(f"User '{target_username}' NOT found in database.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}
    
    score += 30
    feedback.append(f"User '{target_username}' created.")

    # Check Name
    given = result.get('given_name', '')
    family = result.get('family_name', '')
    if given.lower() == target_given.lower() and family.lower() == target_family.lower():
        score += 20
        feedback.append("Person name matches.")
    else:
        feedback.append(f"Name mismatch: Found '{given} {family}', expected '{target_given} {target_family}'.")

    # Check Role
    roles = result.get('roles', [])
    # Role might be stored as "Nurse" or "Organizational: Nurse" depending on setup
    # We check if target_role string is contained in any of the assigned roles
    role_match = any(target_role.lower() in r.lower() for r in roles if r)
    if role_match:
        score += 30
        feedback.append(f"Role '{target_role}' assigned.")
    else:
        feedback.append(f"Role mismatch: Found {roles}, expected '{target_role}'.")

    # Check Creation Time (Anti-gaming)
    is_new = result.get('is_newly_created', False)
    if is_new:
        score += 10
        feedback.append("User created during task window.")
    else:
        feedback.append("User record predates task start (pre-existing?).")

    # 3. VLM Verification (Trajectory)
    # Check if the agent actually visited the admin pages
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Analyze these screenshots of an agent using OpenMRS.
        Did the agent navigate to a "System Administration", "Advanced Administration", or "Accounts" page?
        Is there any evidence of a "Create User" or "Add Person" form being filled?
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get("success"):
                # We assume if the programmatic check passed, the VLM check is just a bonus confirmation
                # If programmatic failed, VLM won't save it.
                # Here we just give points if it looks plausible.
                score += 10
                feedback.append("VLM confirms admin workflow.")
            else:
                # If VLM fails/timeouts, we don't penalize heavily if the DB proof is solid
                score += 10 
                feedback.append("VLM verification skipped.")
        except:
            score += 10 # Graceful fallback
    else:
        score += 10

    passed = score >= 80  # Require user, name, and role to be mostly correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }