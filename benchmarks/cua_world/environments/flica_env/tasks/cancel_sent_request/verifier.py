#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import sys
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cancel_request(traj, env_info, task_info):
    """
    Verifies that the friend request to 'ghost_pilot@example.com' was cancelled.
    
    Strategy:
    1. Programmatic: Check final UI dump. Target email must be GONE.
    2. Programmatic: Check final UI context. Should still be on a Requests/Friends related screen (optional but good).
    3. VLM: Check trajectory to confirm the 'Cancel'/'Withdraw' action was actually performed (anti-gaming: simple navigation away shouldn't pass).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_email = metadata.get('target_email', "ghost_pilot@example.com")
    
    # Setup temp file for result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_path = temp_result.name
    temp_result.close()
    
    try:
        # Fetch result JSON
        copy_from_env("/sdcard/task_result.json", result_path)
        with open(result_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(result_path):
            os.unlink(result_path)

    # --- Criteria Evaluation ---
    score = 0
    feedback = []
    
    # 1. App Running (Basic sanity check) - 10 pts
    if result_data.get("app_running", False):
        score += 10
    else:
        feedback.append("App was closed at end of task.")

    # 2. Target Email Absence (Primary Goal) - 40 pts
    email_still_present = result_data.get("email_still_present", True)
    if not email_still_present:
        score += 40
        feedback.append(f"Target email '{target_email}' successfully removed from view.")
    else:
        feedback.append(f"Target email '{target_email}' is STILL visible in the UI (Task Failed).")
        # If email is still there, they definitely failed.
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Context Check (Are we still on a relevant screen?) - 10 pts
    # This prevents getting points by just crashing/exiting the screen immediately
    # If the email is gone AND we are on "Requests" screen, it's very likely cancelled.
    if result_data.get("on_requests_screen", False):
        score += 10
        feedback.append("Agent remained on Requests/Sent screen.")
    else:
        feedback.append("Agent navigated away from Requests screen (Ambiguous outcome).")

    # 4. VLM Trajectory Verification (Action Confirmation) - 40 pts
    # We need to distinguish between "I navigated to settings so the email isn't visible" 
    # and "I actually tapped cancel".
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = f"""
    You are verifying an Android UI task.
    Goal: Cancel/Withdraw a sent friend request to '{target_email}'.
    
    Review the screenshots. Look for:
    1. Navigation to a 'Friend Requests' or 'Sent Requests' list.
    2. The presence of '{target_email}' in a list.
    3. An interaction (tap) with a 'Cancel', 'Withdraw', 'Remove', or 'X' button next to that email.
    
    Did the agent perform the cancellation action?
    Return JSON: {{ "action_performed": true/false, "email_seen": true/false, "reason": "..." }}
    """
    
    try:
        vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_response.get('parsed', {})
        
        if parsed.get('action_performed', False):
            score += 40
            feedback.append("VLM confirmed cancellation action.")
        elif parsed.get('email_seen', False):
            # Email was seen but action not confirmed - suspicious
            feedback.append("VLM saw the email but did not detect cancellation action.")
            score += 10 # Partial credit for finding it
        else:
            feedback.append("VLM did not observe the workflow.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback.append("VLM verification skipped due to error.")
        # Fallback scoring if VLM fails but programmatic passed
        if score >= 50: 
            score += 20 

    # Final Pass Determination
    # Must have removed the email (primary check) AND (Action confirmed OR Remained on screen)
    passed = (not email_still_present) and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }