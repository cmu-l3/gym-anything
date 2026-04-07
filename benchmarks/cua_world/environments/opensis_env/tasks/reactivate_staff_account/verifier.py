#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reactivate_staff_account(traj, env_info, task_info):
    """
    Verifies that the agent reactivated the existing staff account for James Helper.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # 1. Retrieve result data from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (Database State)
    
    # Check 1: Access Enabled (40 pts)
    # The 'opensis_access' column should be 'Y' (was 'N')
    current_access = result.get('current_access', 'N')
    if current_access == 'Y':
        score += 40
        feedback.append("Success: Staff account access enabled.")
    else:
        feedback.append(f"Fail: Staff account access is still '{current_access}'.")

    # Check 2: No Duplicates Created (30 pts)
    # The agent should have found the *existing* user, not created a new one.
    # Count of 'James Helper' should remain exactly 1 (initial == current)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    if current_count == initial_count:
        score += 30
        feedback.append("Success: Reactivated original record (no duplicates created).")
    elif current_count > initial_count:
        score += 0
        feedback.append("Fail: New staff record created instead of reactivating existing one.")
    else:
        # Should not happen unless they deleted the user
        score += 0
        feedback.append("Fail: Staff record count decreased (user deleted?).")

    # Check 3: Profile Integrity (10 pts)
    # Ensure they didn't change him to an admin or student
    current_profile = result.get('current_profile', '').lower()
    if 'teacher' in current_profile:
        score += 10
        feedback.append("Success: User profile role preserved as Teacher.")
    else:
        feedback.append(f"Warning: User profile changed to '{current_profile}'.")

    # 3. VLM Verification (Trajectory Analysis) (20 pts)
    # Since finding the user requires using a filter (e.g. "Include Inactive"), 
    # we check if the agent interacted with search filters.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    Analyze these screenshots of a user interacting with OpenSIS student information system.
    The user is trying to find a disabled/inactive staff member.
    
    Look for:
    1. A list of users or staff members.
    2. Any interaction with search filters, specifically checkboxes like "Include Inactive", "All", or "Status".
    3. A staff details form where "OpenSIS Access" or "System Access" is being toggled.
    
    Did the user perform these actions?
    """
    
    vlm_result = query_vlm(images=all_frames, prompt=vlm_prompt)
    
    # We award points if the VLM sees relevant UI interactions or if the programmatic check passed overwhelmingly
    # (If they passed programmatic perfectly, they MUST have found the user, so we grant VLM points implicitly 
    # to avoid false negatives from VLM).
    if score >= 70: 
        # Implicit pass on VLM if functional goal achieved perfectly
        score += 20
        feedback.append("Process Verified: Successfully located and modified hidden user.")
    elif vlm_result and "yes" in str(vlm_result).lower():
        score += 10
        feedback.append("Process Partial: VLM detected search attempt.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }