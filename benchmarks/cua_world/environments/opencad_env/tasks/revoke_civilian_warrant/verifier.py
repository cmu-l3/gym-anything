#!/usr/bin/env python3
"""
Verifier for revoke_civilian_warrant task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_revoke_civilian_warrant(traj, env_info, task_info):
    """
    Verify that the specific warrant was removed while preserving the civilian.
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/revoke_warrant_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Database Verification (Primary Signal)
    
    # Criterion 1: Warrant Removed (40 pts)
    warrant_removed = result.get("warrant_removed", False)
    if warrant_removed:
        score += 40
        feedback_parts.append("Success: The 'Failure to Appear' warrant was removed.")
    else:
        feedback_parts.append("Fail: The target warrant still exists in the database.")

    # Criterion 2: Civilian Preserved (20 pts)
    civilian_preserved = result.get("civilian_preserved", False)
    if civilian_preserved:
        score += 20
        feedback_parts.append("Success: Civilian record 'Marcus Vance' was preserved.")
    else:
        feedback_parts.append("Critical Fail: The civilian identity was deleted! You should only delete the warrant.")

    # Criterion 3: Count Integrity (15 pts)
    # Ensure they didn't just truncate the table. Diff should be exactly 1 (or small if they deleted duplicates).
    count_diff = result.get("count_difference", 0)
    if count_diff == 1:
        score += 15
        feedback_parts.append("Database Integrity: Exactly one warrant record was removed.")
    elif count_diff > 1:
        score += 5
        feedback_parts.append(f"Warning: {count_diff} warrants were removed. Only 1 was expected.")
    elif count_diff <= 0:
        # If warrant_removed is true but count didn't decrease, something weird happened (maybe added one then deleted?)
        if warrant_removed:
            feedback_parts.append("Warning: Warrant removed but total count didn't decrease (new warrants added?).")
        else:
            feedback_parts.append("No records removed.")

    # 3. VLM Verification (Visual Signal)
    
    # We want to verify the agent actually searched and interacted with the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a Computer Aided Dispatch (OpenCAD) system.
    I am looking for evidence of the following workflow:
    1. Searching for a civilian named "Marcus Vance".
    2. Viewing a list of warrants or a civilian profile.
    3. Clicking a "Delete", "Remove", or "Revoke" button next to a "Failure to Appear" warrant.
    
    Does the user appear to perform these actions?
    Answer YES or NO and provide a brief reason.
    """
    
    try:
        vlm_response = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        vlm_text = vlm_response.get('parsed', {}).get('response', vlm_response.get('response', '')).lower()
        
        if "yes" in vlm_text:
            score += 25
            feedback_parts.append("VLM: Workflow visually confirmed (Search -> Identify -> Delete).")
        else:
            feedback_parts.append("VLM: Could not visually confirm the specific deletion workflow.")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback scoring if VLM fails but DB is correct
        if warrant_removed and civilian_preserved:
             score += 10 # Give partial credit if we can't see it but DB proves it
             feedback_parts.append("VLM check skipped (error).")

    # 4. Final Scoring
    passed = (score >= 60) and warrant_removed and civilian_preserved

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }