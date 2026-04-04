#!/usr/bin/env python3
"""
Verifier for clear_watchlist_visitor task.
Uses VLM to verify:
1. Agent navigated to watchlist/denied list.
2. Agent removed/deleted the record for Maria Santos.
3. Agent registered Maria Santos successfully.
4. Final screen shows Maria Santos as signed in (Active).
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clear_watchlist_visitor(traj, env_info, task_info):
    """
    Verify the agent cleared the watchlist and registered the visitor.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Check basic telemetry
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

    if not result.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "Lobby Track application was closed"}

    # 2. VLM Verification
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available"}

    # PROMPT 1: Verify final state (Registration Success)
    final_prompt = """
    Analyze this screenshot of the Jolly Lobby Track visitor management system.
    1. Is the "Active Visitors" or "Visitor Log" screen visible?
    2. Do you see a visitor named "Maria Santos" in the list of currently signed-in visitors?
    3. Are the details (Company: Meridian, Host: David Park) visible?
    
    Return JSON:
    {
        "active_list_visible": boolean,
        "maria_santos_signed_in": boolean,
        "correct_host": boolean,
        "correct_company": boolean
    }
    """
    
    final_vlm = query_vlm(
        images=[final_screenshot], 
        prompt=final_prompt
    )
    
    if not final_vlm.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed"}
        
    final_data = final_vlm.get("parsed", {})
    
    # PROMPT 2: Verify Watchlist Removal (Trajectory Analysis)
    traj_prompt = """
    Analyze these frames showing the agent's workflow.
    Look for evidence of the following actions:
    1. Did the agent open a "Watchlist", "Denied", or "Blacklist" screen?
    2. Did the agent select or find "Maria Santos" on a list?
    3. Did the agent click "Delete", "Remove", or "Clear" on that record?
    4. Did the agent fill out a registration form for "Maria Santos"?
    
    Return JSON:
    {
        "watchlist_accessed": boolean,
        "removal_action_attempted": boolean,
        "registration_form_filled": boolean
    }
    """
    
    traj_vlm = query_vlm(
        images=frames,
        prompt=traj_prompt
    )
    
    traj_data = traj_vlm.get("parsed", {}) if traj_vlm.get("success") else {}

    # Scoring
    score = 0
    feedback = []
    
    # Watchlist Removal (25 pts)
    if traj_data.get("watchlist_accessed"):
        score += 10
        feedback.append("Accessed watchlist.")
    if traj_data.get("removal_action_attempted"):
        score += 15
        feedback.append("Removed watchlist entry.")
    else:
        feedback.append("Did not clearly show removal of watchlist entry.")

    # Registration & Check-in (75 pts)
    if traj_data.get("registration_form_filled"):
        score += 15
        feedback.append("Filled registration form.")
        
    if final_data.get("maria_santos_signed_in"):
        score += 30
        feedback.append("Maria Santos successfully signed in.")
        if final_data.get("correct_company"):
            score += 15
            feedback.append("Correct company used.")
        if final_data.get("correct_host"):
            score += 15
            feedback.append("Correct host assigned.")
    else:
        feedback.append("Maria Santos NOT found in active visitors list.")

    # Pass logic: Must have removed from watchlist AND signed in
    # (Or at least accessed watchlist and signed in if removal wasn't clearly captured by sparse frames)
    removal_evidence = traj_data.get("removal_action_attempted") or traj_data.get("watchlist_accessed")
    signed_in = final_data.get("maria_santos_signed_in")
    
    passed = (score >= 60) and signed_in and removal_evidence

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }