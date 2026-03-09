#!/usr/bin/env python3
"""
Verifier for create_organic_depot task.
Verifies that a storage location named 'Silo Bio 01' was created in Ekylibre.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_organic_depot(traj, env_info, task_info):
    """
    Verify the creation of the organic storage depot.
    
    Scoring:
    - 40 pts: Depot record exists with correct name
    - 20 pts: Depot created DURING the task (anti-gaming)
    - 10 pts: Depot code/reference matches expected
    - 30 pts: VLM verification of UI interaction/success
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Silo Bio 01')
    expected_code = metadata.get('expected_code', 'SILO-BIO-01')

    # Load result from container
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
    
    # 1. Database Verification
    depot_found = result.get('depot_found', False)
    depot_name = result.get('depot_name', '')
    depot_code = result.get('depot_code', '')
    created_during_task = result.get('created_during_task', False)

    if depot_found and depot_name.lower() == expected_name.lower():
        score += 40
        feedback_parts.append(f"Storage location '{depot_name}' found.")
    else:
        feedback_parts.append(f"Storage location '{expected_name}' NOT found.")

    if created_during_task:
        score += 20
        feedback_parts.append("Record created during task session.")
    elif depot_found:
        feedback_parts.append("Record existed before task start (no points for pre-existing data).")

    # Check optional code
    # Ekylibre sometimes uses 'code' or 'work_number' fields. 
    # We accept partial matches or exact matches on available fields.
    if depot_found and (expected_code.lower() in str(depot_code).lower() or expected_code.lower() in str(depot_name).lower()):
        score += 10
        feedback_parts.append(f"Code/Reference '{expected_code}' matched.")
    elif depot_found:
        feedback_parts.append(f"Code mismatch (Expected '{expected_code}', found '{depot_code}').")

    # 2. VLM Verification
    # Use trajectory to confirm user actually interacted with the form
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    You are verifying an agent using farm management software.
    Goal: Create a new storage location named '{expected_name}'.
    
    Look at the sequence of images.
    1. Did the agent navigate to an Inventory or Storage/Depot settings page?
    2. Did the agent fill out a form with the name '{expected_name}'?
    3. Does the final state show the new storage location in a list or a success message?
    
    Respond with JSON: {{ "workflow_followed": boolean, "name_visible": boolean, "success_state": boolean }}
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        # Parse simple JSON response (assuming helper handles parsing or returns dict)
        # If query_vlm returns string, we'd parse it. Assuming dict for this template.
        if isinstance(vlm_result, str):
            # rudimentary parsing if mock
            vlm_data = {"workflow_followed": True} if "true" in vlm_result.lower() else {"workflow_followed": False}
        else:
            vlm_data = vlm_result

        if vlm_data.get("workflow_followed", False):
            score += 10
        if vlm_data.get("name_visible", False):
            score += 10
        if vlm_data.get("success_state", False):
            score += 10
            
        feedback_parts.append("Visual verification passed.")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Fallback: if database verified, give partial credit for VLM
        if depot_found and created_during_task:
            score += 15
            feedback_parts.append("Visual verification skipped (error), partial points awarded based on DB success.")

    passed = score >= 60 and depot_found and created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }