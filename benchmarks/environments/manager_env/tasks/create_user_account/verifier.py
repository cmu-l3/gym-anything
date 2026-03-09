#!/usr/bin/env python3
"""
Verifier for create_user_account task.

Scoring Criteria:
1. User 'sjohnson' exists in the user list (25 pts)
2. Authentication with 'sjohnson'/'Northwind2024!' works (30 pts)
3. User 'sjohnson' has access to Northwind Traders business (20 pts)
4. VLM Verification: Agent navigated to user management screen (25 pts)

Pass Threshold: 65 points (Must essentially complete creation + auth or creation + VLM)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    """
    Verify that the agent created the user account with correct permissions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
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
    
    # --- Criterion 1: User Existence (25 pts) ---
    if result.get('user_exists', False):
        score += 25
        feedback_parts.append("User 'sjohnson' exists")
    elif result.get('partial_name_match', False):
        score += 10
        feedback_parts.append("User exists but username incorrect (partial match)")
    else:
        feedback_parts.append("User 'sjohnson' NOT found in list")

    # --- Criterion 2: Authentication (30 pts) ---
    # This proves the password was set correctly
    if result.get('auth_success', False):
        score += 30
        feedback_parts.append("Authentication successful")
    else:
        feedback_parts.append("Authentication failed (wrong password or user missing)")

    # --- Criterion 3: Business Access (20 pts) ---
    if result.get('business_access', False):
        score += 20
        feedback_parts.append("Northwind Traders access granted")
    elif result.get('auth_success', False):
        # Auth worked but business access failed
        feedback_parts.append("Business access NOT granted to user")

    # --- Criterion 4: VLM Verification (25 pts) ---
    # We verify the agent actually interacted with the User Management UI
    # This prevents gaming via CLI or other non-standard means (though unlikely here)
    # and confirms navigation logic.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    You are verifying if an agent successfully created a user in Manager.io.
    Look at these screenshots of the agent's workflow.
    
    I am looking for:
    1. Navigation to the 'Users' screen (server level, not inside a business).
    2. Filling out a form with username 'sjohnson'.
    3. Selecting 'Northwind Traders' in a permissions/access list.
    
    Did the agent perform these actions?
    Respond with JSON: {"success": boolean, "reason": "string"}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
    
    vlm_score = 0
    if vlm_result.get("success", False):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("success", False):
            vlm_score = 25
            feedback_parts.append("VLM confirmed workflow")
        else:
            # Fallback: if VLM is unsure but programmatic passed, give partial credit
            if score >= 50:
                vlm_score = 15
                feedback_parts.append("VLM inconclusive, partial credit based on result")
            else:
                feedback_parts.append(f"VLM did not observe correct workflow: {parsed.get('reason', 'unknown')}")
    else:
        feedback_parts.append("VLM verification failed to execute")
        
    score += vlm_score

    # Final check
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }