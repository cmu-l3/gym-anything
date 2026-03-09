#!/usr/bin/env python3
"""
Verifier for provision_asset_to_user task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_asset(traj, env_info, task_info):
    """
    Verifies that the asset was correctly provisioned.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_user = metadata.get('target_user', 'Elena Fisher')
    expected_dept = metadata.get('target_dept', 'Operations')
    expected_state = metadata.get('target_state', 'In Use')
    expected_desc_part = metadata.get('required_description_part', 'Handed over')

    # Load result from container
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
    feedback = []
    
    # 1. Verify User Assignment (30 pts)
    actual_owner = result.get('owner', '')
    if expected_user.lower() in actual_owner.lower():
        score += 30
        feedback.append(f"User correctly assigned to {actual_owner}.")
    else:
        feedback.append(f"Incorrect User: Expected '{expected_user}', found '{actual_owner}'.")

    # 2. Verify Department (25 pts)
    actual_dept = result.get('department', '')
    if expected_dept.lower() in actual_dept.lower():
        score += 25
        feedback.append(f"Department correctly set to {actual_dept}.")
    else:
        feedback.append(f"Incorrect Department: Expected '{expected_dept}', found '{actual_dept}'.")

    # 3. Verify State (25 pts)
    actual_state = result.get('state', '')
    if expected_state.lower() in actual_state.lower():
        score += 25
        feedback.append(f"State correctly set to {actual_state}.")
    else:
        feedback.append(f"Incorrect State: Expected '{expected_state}', found '{actual_state}'.")

    # 4. Verify Description (20 pts)
    actual_desc = result.get('description', '')
    if expected_desc_part.lower() in actual_desc.lower():
        score += 20
        feedback.append("Description contains handover notes.")
    else:
        feedback.append("Description missing required handover notes.")

    # 5. VLM Verification (Anti-Gaming / Confirmation)
    # Check if we can see the asset page in the trajectory
    frames = sample_trajectory_frames(traj, n=5)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = f"Does the screen show details for asset 'WS-LPT-4402'? Can you see User: '{expected_user}' or State: '{expected_state}'?"
    vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
    
    if not vlm_result.get('success', False):
        feedback.append("VLM verification skipped (failed to analyze).")
    else:
        if "yes" in vlm_result.get('parsed', {}).get('response', '').lower():
            feedback.append("Visual confirmation successful.")
        else:
            feedback.append("Visual confirmation failed (Asset details not clearly visible).")

    # Final Pass check
    # Must get User, Dept, and State right to pass (30+25+25 = 80)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }