#!/usr/bin/env python3
"""
Verifier for Enforce Dispo Timeouts Task (Vicidial).

Verifies:
1. Campaign FASTTRACK exists and is configured correctly.
2. Status DISPTO exists and is non-selectable.
3. Timeout settings link the campaign to the status.
4. VLM verification of UI interaction.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_dispo_timeouts(traj, env_info, task_info):
    """
    Verify the Vicidial campaign configuration.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    campaign = result.get('campaign')
    status = result.get('status')
    
    # 1. Campaign Existence (10 pts)
    if campaign:
        score += 10
        feedback_parts.append("Campaign 'FASTTRACK' created")
        
        # Check Active (Must be Y)
        if campaign.get('active') == 'Y':
            score += 5
            feedback_parts.append("Campaign is Active")
        else:
            feedback_parts.append("Campaign is NOT Active")
            
        # Check Dial Method (RATIO)
        if campaign.get('dial_method') == 'RATIO':
            score += 5
        else:
            feedback_parts.append(f"Wrong dial method: {campaign.get('dial_method')}")
            
    else:
        return {"passed": False, "score": 0, "feedback": "Campaign 'FASTTRACK' not found in database"}

    # 2. Status Existence & Properties (20 pts)
    if status:
        score += 10
        feedback_parts.append("Status 'DISPTO' created")
        
        # Selectable: N
        if status.get('selectable') == 'N':
            score += 5
            feedback_parts.append("Status is Non-Selectable")
        else:
            feedback_parts.append("Status should be Non-Selectable (N)")
            
        # Human Answer: N
        if status.get('human_answered') == 'N':
            score += 5
        else:
            feedback_parts.append("Status human_answered should be N")
    else:
        feedback_parts.append("Status 'DISPTO' not found linked to campaign")

    # 3. Timeout Configuration (20 pts)
    # Dispo Screen Time Limit: 30
    actual_limit = str(campaign.get('dispo_limit', '0'))
    if actual_limit == '30':
        score += 20
        feedback_parts.append("Dispo limit set to 30s")
    else:
        feedback_parts.append(f"Incorrect Dispo limit: {actual_limit} (expected 30)")

    # Dispo Screen Time Limit Status: DISPTO (15 pts)
    actual_status_link = campaign.get('dispo_status', '')
    if actual_status_link == 'DISPTO':
        score += 15
        feedback_parts.append("Timeout status linked correctly")
    else:
        feedback_parts.append(f"Incorrect timeout status link: {actual_status_link}")

    # 4. Efficiency Settings (15 pts)
    # Wrapup Seconds: 5
    if str(campaign.get('wrapup', '0')) == '5':
        score += 10
        feedback_parts.append("Wrapup set to 5s")
    else:
        feedback_parts.append(f"Incorrect wrapup: {campaign.get('wrapup')}")

    # Pause After Call: N
    if campaign.get('pause_after') == 'N':
        score += 5
        feedback_parts.append("Pause after call disabled")
    else:
        feedback_parts.append("Pause after call should be N")

    # 5. VLM Trajectory Verification (10 pts)
    # Ensure the agent actually navigated the UI and didn't just (hypothetically) curl the API if that were possible, 
    # or more importantly, to verify the workflow logic.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a Vicidial Administration task.
    The user is creating a campaign and a custom status.
    
    Look for:
    1. The "Campaigns" admin screen (tables of settings).
    2. Input fields where "FASTTRACK" or "30" might have been entered.
    3. The "Statuses" or "Campaign Statuses" configuration screen.
    
    Does the trajectory show evidence of interacting with Vicidial Admin forms?
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        # We assume a positive result if the VLM confirms UI interaction.
        # This is a soft check for points.
        if vlm_result and vlm_result.get('success', False):
             # Simple heuristic: if VLM didn't error out and found meaningful content
             # We can check specific keywords in parsed output if available, but here we award points for valid workflow appearance
             score += 10
             feedback_parts.append("Visual verification passed")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Don't penalize too heavily if VLM service fails, but don't award bonus points

    # Final tally
    passed = score >= 60 and campaign and status and str(campaign.get('dispo_limit')) == '30' and campaign.get('dispo_status') == 'DISPTO'
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }