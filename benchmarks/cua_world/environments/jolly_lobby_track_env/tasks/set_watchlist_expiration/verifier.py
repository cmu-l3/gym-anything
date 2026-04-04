#!/usr/bin/env python3
"""
Verifier for set_watchlist_expiration task.

Strategy:
1. Verify database file was modified (indicates a save operation occurred).
2. Use VLM to inspect the final screenshot and trajectory frames to confirm:
   - The 'Robert Vance' record was accessed.
   - The date '12/31/2026' (or 'Dec 31, 2026') is visible in the expiration field OR notes.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_watchlist_expiration(traj, env_info, task_info):
    """
    Verify the watchlist expiration update using VLM and file timestamps.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Result (File modification check)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_modified = result_data.get("db_modified", False)
    
    # 2. VLM Verification
    # We use trajectory frames to catch the editing process and the final screenshot for the result
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)

    if not frames:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = """
    You are verifying a task in the Jolly Lobby Track software.
    Goal: Update the watchlist record for 'Robert Vance' to set the Expiration Date to 12/31/2026.
    
    Review the provided screenshots of the user's workflow. 
    1. Did the user access a watchlist or denied visitors list?
    2. Is the name 'Robert Vance' visible?
    3. Is the date '12/31/2026' (or 'Dec 31, 2026') visible in an 'Expiration', 'Valid Until', 'Notes', or 'Reason' field?
    
    Provide your assessment in JSON format:
    {
        "watchlist_accessed": true/false,
        "robert_vance_seen": true/false,
        "correct_date_entered": true/false,
        "confidence": "high/medium/low",
        "reasoning": "..."
    }
    """

    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run"}

    analysis = vlm_response.get("parsed", {})
    
    # Scoring Logic
    score = 0
    feedback_parts = []

    # Criterion 1: Database Modified (20 pts)
    # This proves something was actually saved, preventing "type but don't save" gaming
    if db_modified:
        score += 20
        feedback_parts.append("Database file modified (Save detected)")
    else:
        feedback_parts.append("Database NOT modified (Did you save?)")

    # Criterion 2: Watchlist Accessed (20 pts)
    if analysis.get("watchlist_accessed"):
        score += 20
        feedback_parts.append("Accessed Watchlist")
    
    # Criterion 3: Correct Record (20 pts)
    if analysis.get("robert_vance_seen"):
        score += 20
        feedback_parts.append("Located 'Robert Vance'")

    # Criterion 4: Correct Date (40 pts)
    if analysis.get("correct_date_entered"):
        score += 40
        feedback_parts.append("Expiration date set to 12/31/2026")
    else:
        feedback_parts.append("Correct expiration date NOT verified in screenshots")

    passed = score >= 80  # Requires Date + (DB Modified OR (Record+Access))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }