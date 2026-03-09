#!/usr/bin/env python3
"""
Verifier for configure_skills_based_routing task.

Checks:
1. Agent navigated to Inbound Groups and changed AGENTDIRECT routing to 'rank'.
2. Agent navigated to Users and changed User 6666 rank for AGENTDIRECT to 9.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_skills_routing(traj, env_info, task_info):
    # 1. Retrieve Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    final_routing = result.get("final_routing_method", "").lower().strip()
    final_rank_str = str(result.get("final_user_rank", "0")).strip()
    
    try:
        final_rank = int(final_rank_str)
    except ValueError:
        final_rank = -1
        
    is_allowed = int(result.get("is_user_allowed", 0)) > 0

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion A: Inbound Group Routing (40 pts)
    # Note: Vicidial allows 'rank', 'call_count_rank', etc. The task asked for 'rank'.
    if final_routing == "rank":
        score += 40
        feedback.append("Success: Inbound Group routing set to 'rank'.")
    elif "rank" in final_routing:
        score += 20
        feedback.append(f"Partial: Inbound Group routing set to '{final_routing}' (contains rank).")
    else:
        feedback.append(f"Fail: Inbound Group routing is '{final_routing}' (expected 'rank').")

    # Criterion B: User Rank (40 pts)
    if final_rank == 9:
        score += 40
        feedback.append("Success: User rank set to 9.")
    elif final_rank > 0 and final_rank != 9:
        score += 10
        feedback.append(f"Fail: User rank set to {final_rank} (expected 9).")
    elif final_rank == 0:
        feedback.append("Fail: User rank is 0 (default/unchanged).")
    
    # Criterion C: User Allowed (10 pts)
    if is_allowed:
        score += 10
        feedback.append("Success: User is allowed in the group.")
    else:
        feedback.append("Fail: User is not configured for the group.")

    # Criterion D: VLM Trajectory Verification (10 pts)
    # We want to see if the agent actually visited the relevant pages.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of a Vicidial Admin task.
    I am looking for evidence that the user:
    1. Visited an "Inbound Group" configuration page (look for 'Next Agent Call' dropdown).
    2. Visited a "User" modification page (look for 'Allowed Inbound Groups' or 'Grade'/'Rank' fields).
    
    Answer strictly YES or NO for each.
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        resp_text = vlm_resp.get("response", "").lower() if isinstance(vlm_resp, dict) else ""
        
        if "inbound group" in resp_text or "next agent call" in resp_text or "yes" in resp_text:
            vlm_score += 5
        if "user" in resp_text or "rank" in resp_text:
            vlm_score += 5
            
        score += vlm_score
        if vlm_score > 0:
            feedback.append("VLM Verification: UI Navigation detected.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Grant partial credit if VLM fails to prevent punishment for infra issues
        score += 5 

    # Final Pass/Fail
    passed = (final_routing == "rank") and (final_rank == 9)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }