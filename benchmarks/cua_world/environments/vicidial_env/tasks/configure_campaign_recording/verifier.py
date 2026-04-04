#!/usr/bin/env python3
"""
Verifier for configure_campaign_recording task.

Checks database values for:
1. campaign_rec (ALLFORCE)
2. campaign_rec_filename (Specific format)
3. allcalls_delay (3)

Also uses VLM to verify the agent actually navigated the UI.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_recording(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_rec_mode = metadata.get('expected_rec_mode', 'ALLFORCE')
    expected_filename = metadata.get('expected_filename', 'FINSVC01_|FULLDATE|_|CUSTPHONE|_|AGENT|')
    expected_delay = metadata.get('expected_delay', '3')

    # Retrieve result JSON
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
    
    # 1. Check Recording Mode (30 pts)
    actual_rec_mode = result.get('actual_rec_mode', '')
    if actual_rec_mode == expected_rec_mode:
        score += 30
        feedback_parts.append(f"Recording Mode Correct ({actual_rec_mode})")
    else:
        feedback_parts.append(f"Recording Mode Incorrect: Expected '{expected_rec_mode}', got '{actual_rec_mode}'")

    # 2. Check Filename (30 pts)
    actual_filename = result.get('actual_filename', '')
    if actual_filename == expected_filename:
        score += 30
        feedback_parts.append("Filename Format Correct")
    else:
        feedback_parts.append(f"Filename Incorrect: Expected '{expected_filename}', got '{actual_filename}'")

    # 3. Check Delay (20 pts)
    actual_delay = str(result.get('actual_delay', ''))
    if actual_delay == expected_delay:
        score += 20
        feedback_parts.append(f"Delay Correct ({actual_delay}s)")
    else:
        feedback_parts.append(f"Delay Incorrect: Expected '{expected_delay}', got '{actual_delay}'")

    # 4. Anti-Gaming / Modification Check (10 pts)
    mod_count = result.get('modification_log_count', 0)
    if mod_count > 0:
        score += 10
        feedback_parts.append("Modification verified in admin logs")
    else:
        feedback_parts.append("Warning: No admin log entries found for this campaign since task start")

    # 5. VLM Trajectory Verification (10 pts)
    # Ensure the agent actually visited the campaign modify screen
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = """
    You are verifying a Vicidial configuration task.
    Look at these screenshots of the agent's session.
    
    1. Did the agent navigate to a "Campaigns" or "Campaign Modification" screen?
    2. Is the form for campaign 'FINSVC01' visible in any frame?
    3. Are there input fields for 'Recording' or 'Filename' visible?
    
    Return JSON: {"campaign_screen_seen": boolean, "details": "string"}
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        if parsed.get('campaign_screen_seen', False):
            vlm_score = 10
            feedback_parts.append("VLM confirmed campaign screen navigation")
        else:
            feedback_parts.append("VLM could not visually confirm navigation to campaign settings")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if data is correct, give benefit of doubt for VLM points to avoid false failures on visual glitches
        if score >= 80: 
            vlm_score = 10
            feedback_parts.append("VLM skipped (data valid)")

    score += vlm_score

    # Determine pass/fail
    # Must have at least Mode AND Filename correct (60 pts base) to pass
    passed = (score >= 60) and (actual_rec_mode == expected_rec_mode) and (actual_filename == expected_filename)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }