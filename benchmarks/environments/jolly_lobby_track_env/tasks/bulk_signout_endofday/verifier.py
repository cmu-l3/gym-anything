#!/usr/bin/env python3
"""
Verifier for Bulk Sign-out Task.

Verification Strategy:
1. File Check: Did the agent save the requested screenshot? (10 pts)
2. Final State VLM: Does the final system screenshot show 0 active visitors? (40 pts)
3. Trajectory VLM: Did the agent perform sign-out actions for multiple people? (50 pts)
   - Prevents "do nothing" if the list happened to be empty
   - Prevents gaming by just closing the app
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_signout(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: Missing verification tools"}

    # Load result JSON
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

    # 1. Check Agent Screenshot (10 pts)
    if result.get('agent_screenshot_exists') and result.get('agent_screenshot_valid_time'):
        score += 10
        feedback.append("Confirmation screenshot saved correctly.")
    else:
        feedback.append("Confirmation screenshot missing or stale.")

    # 2. Final State Verification (40 pts)
    # We check the actual system screenshot taken by export_result.sh
    final_sys_screenshot = get_final_screenshot(traj) # Using traj final frame is usually safer/aligned
    
    final_state_prompt = """
    Examine this screenshot of the Lobby Track visitor management software.
    Look at the list of Active Visitors or Signed-In Visitors.
    
    1. Is the visitor list empty? (No names listed in the grid)
    2. Does it explicitly say "0 Visitors" or similar?
    3. Are there any rows of people names visible?
    
    Return JSON:
    {
        "visitor_list_empty": true/false,
        "visible_visitor_count": int,
        "reasoning": "string"
    }
    """
    
    vlm_final = query_vlm(images=[final_sys_screenshot], prompt=final_state_prompt)
    final_data = vlm_final.get('parsed', {})
    
    if final_data.get('visitor_list_empty') or final_data.get('visible_visitor_count', 1) == 0:
        score += 40
        feedback.append("Final state confirmed: Visitor list is empty.")
    else:
        cnt = final_data.get('visible_visitor_count', 'unknown')
        feedback.append(f"Final state check failed: {cnt} visitors still visible.")

    # 3. Trajectory Verification (50 pts)
    # Check if we saw sign-out actions
    frames = sample_trajectory_frames(traj, n=8)
    
    traj_prompt = """
    Review this sequence of screenshots showing a user interacting with Lobby Track.
    The user is supposed to sign out multiple visitors.
    
    Look for:
    - Clicking on visitor names (Margaret, James, Priya)
    - Clicking a "Sign Out", "Check Out", or "Log Out" button
    - Confirmation dialogs appearing
    - The list getting shorter
    
    Did the user perform sign-out actions for MULTIPLE visitors?
    
    Return JSON:
    {
        "sign_out_actions_detected": true/false,
        "multiple_visitors_processed": true/false,
        "visitors_seen": ["list", "of", "names", "if", "clear"],
        "reasoning": "string"
    }
    """
    
    vlm_traj = query_vlm(images=frames, prompt=traj_prompt)
    traj_data = vlm_traj.get('parsed', {})
    
    if traj_data.get('sign_out_actions_detected'):
        score += 25
        if traj_data.get('multiple_visitors_processed'):
            score += 25
            feedback.append("Trajectory confirms multiple sign-out actions.")
        else:
            feedback.append("Trajectory shows sign-out action, but maybe not for everyone.")
    else:
        feedback.append("No sign-out actions detected in trajectory.")

    # Pass logic
    # Must have cleared the list AND shown evidence of doing it
    passed = (score >= 60) and final_data.get('visitor_list_empty', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "final_analysis": final_data,
            "trajectory_analysis": traj_data
        }
    }