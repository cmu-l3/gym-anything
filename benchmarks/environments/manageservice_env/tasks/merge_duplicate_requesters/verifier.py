#!/usr/bin/env python3
"""
Verifier for merge_duplicate_requesters task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_duplicate_requesters(traj, env_info, task_info):
    """
    Verifies that the agent successfully merged the duplicate requester.
    
    Criteria:
    1. Secondary user (Cameron Howe) should no longer exist/be active (Count = 0).
    2. Primary user (C. Howe) should exist (Count >= 1).
    3. The specific ticket should still exist.
    4. The ticket should be assigned to the Primary user.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check if Old User is gone (40 pts)
    old_user_count = int(result.get("old_user_count", 1))
    if old_user_count == 0:
        score += 40
        feedback.append("Duplicate user 'Cameron Howe' successfully removed/merged.")
    else:
        feedback.append("Duplicate user 'Cameron Howe' still exists.")

    # 2. Check if Ticket still exists (20 pts)
    # This prevents the agent from just deleting the user and the ticket with it (if cascading delete)
    ticket_exists = int(result.get("ticket_exists", 0))
    if ticket_exists > 0:
        score += 20
        feedback.append("Ticket preserved.")
    else:
        feedback.append("Ticket was deleted or lost.")

    # 3. Check if Ticket is reassigned (40 pts)
    correctly_assigned = result.get("ticket_correctly_assigned", False)
    if correctly_assigned:
        score += 40
        feedback.append("Ticket successfully reassigned to 'C. Howe'.")
    else:
        feedback.append("Ticket is NOT assigned to the correct user 'C. Howe'.")

    # VLM Verification (Bonus/Confirmation)
    # We check if the agent actually used the Merge UI
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    # Simple VLM check to see if they visited the requester list
    # Not strictly required for score if DB state is correct, but good for anti-gaming feedback
    vlm_prompt = "Does the sequence of images show the user navigating to a list of users/requesters and selecting multiple users or clicking a 'Merge' button?"
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get("success"):
            logger.info(f"VLM Analysis: {vlm_res.get('response')}")
    except:
        pass

    # Pass logic
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }