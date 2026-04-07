#!/usr/bin/env python3
"""
Verifier for setup_client_project_portfolio task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_client_project_portfolio(traj, env_info, task_info):
    """
    Verifies that the customer, project, admin, and activities were correctly created in OrangeHRM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cust_desc = metadata.get('customer_desc', "")
    expected_proj_desc = metadata.get('project_desc', "")

    # Load result JSON
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
    
    # 1. Customer Verification (20 pts)
    if result.get('customer_found'):
        score += 20
        feedback_parts.append("Customer 'Nebula Stream' created.")
    else:
        feedback_parts.append("Customer 'Nebula Stream' NOT found.")

    # 2. Project Verification (20 pts)
    if result.get('project_found'):
        score += 20
        feedback_parts.append("Project 'Legacy System Migration' created.")
    else:
        feedback_parts.append("Project 'Legacy System Migration' NOT found.")

    # 3. Project Description (10 pts)
    # Allow partial match or full match
    actual_proj_desc = result.get('project_desc', "")
    if expected_proj_desc in actual_proj_desc and len(actual_proj_desc) > 0:
        score += 10
        feedback_parts.append("Project description correct.")
    elif actual_proj_desc:
        score += 5
        feedback_parts.append(f"Project description partial match (Found: {actual_proj_desc}).")
    else:
        feedback_parts.append("Project description missing/incorrect.")

    # 4. Project Admin (10 pts)
    if result.get('admin_assigned'):
        score += 10
        feedback_parts.append("Project Admin assigned.")
    else:
        feedback_parts.append("Project Admin NOT assigned.")

    # 5. Activities (30 pts)
    if result.get('activity_1_found'):
        score += 15
        feedback_parts.append("Activity 'Code Analysis' found.")
    else:
        feedback_parts.append("Activity 'Code Analysis' missing.")
        
    if result.get('activity_2_found'):
        score += 15
        feedback_parts.append("Activity 'Data Transfer' found.")
    else:
        feedback_parts.append("Activity 'Data Transfer' missing.")

    # 6. Anti-Gaming (10 pts)
    # Ensure items were created during this session
    if result.get('new_customer_created') and result.get('new_project_created'):
        score += 10
        feedback_parts.append("Records created fresh during task.")
    elif result.get('customer_found'):
        feedback_parts.append("Warning: Records appear to be pre-existing (anti-gaming check failed).")

    # 7. VLM Verification (Bonus/Confirmation)
    # Check if we can see the Project Info screen in trajectory
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of the OrangeHRM interface.
        Did the user navigate to 'Time' > 'Project Info' > 'Projects' or 'Customers'?
        Do you see 'Nebula Stream' or 'Legacy System Migration' entered in any form or list?
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res.get('success'):
                # We mainly use DB for scoring, but this confirms UI interaction
                feedback_parts.append("VLM confirmed UI interaction.")
        except Exception:
            pass

    # Success Logic
    # Must have at least Customer + Project created to pass
    critical_success = result.get('customer_found') and result.get('project_found')
    passed = (score >= 70) and critical_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }