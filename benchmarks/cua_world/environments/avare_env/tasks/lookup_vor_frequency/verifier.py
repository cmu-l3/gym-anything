#!/usr/bin/env python3
"""
Verifier for lookup_vor_frequency task.

Verifies:
1. Output file existence and content (Programmatic)
2. App usage and navigation flow (VLM Trajectory)
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lookup_vor_frequency(traj, env_info, task_info):
    """
    Verify OAK VOR lookup task.
    
    Scoring:
    - 40 pts: Correct frequency (116.8) written to file
    - 10 pts: File contains correct identifier (OAK)
    - 10 pts: File created during task (anti-gaming)
    - 40 pts: VLM verifies search interface was used correctly
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Programmatic Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/data/local/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Scoring
    score = 0
    feedback = []

    if result_data.get("file_exists"):
        if result_data.get("file_created_during_task"):
            score += 10
            feedback.append("Output file created.")
        else:
            feedback.append("Warning: Output file timestamp invalid.")
        
        if result_data.get("correct_id"):
            score += 10
            feedback.append("Correct Identifier (OAK) found.")
        
        if result_data.get("correct_frequency"):
            score += 40
            feedback.append("Correct Frequency (116.8) found.")
        else:
            feedback.append(f"Incorrect frequency in file: {result_data.get('file_content_preview')}")
    else:
        feedback.append("Output file not found.")

    # 3. VLM Trajectory Verification
    # We want to see evidence of the 'Find' screen and 'OAK' search.
    # Just checking the final screen isn't enough because they might be in a text editor.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Construct VLM prompt
    images = frames + ([final_screen] if final_screen else [])
    
    prompt = """
    Analyze these screenshots from an Android aviation app task.
    The user is supposed to:
    1. Open the 'Find' or 'Search' screen.
    2. Search for 'OAK'.
    3. View details for the OAK VOR (not just the airport).
    
    Look for:
    - A search bar or 'Find' tab active.
    - The text 'OAK' typed in a search field.
    - A list of results or a detail screen showing 'OAK' and '116.8'.
    
    Does the trajectory show the user performing these steps?
    """
    
    vlm_result = query_vlm(images=images, prompt=prompt)
    
    vlm_passed = False
    if vlm_result and vlm_result.get("success"):
        # We expect a positive confirmation from VLM
        analysis = vlm_result.get("response", "").lower()
        # Simple keyword heuristic on the VLM's reasoning
        if "yes" in analysis or "shows" in analysis or "confirm" in analysis:
            vlm_passed = True
            score += 40
            feedback.append("VLM verified search workflow.")
        else:
            feedback.append("VLM could not verify search workflow.")
    else:
        # Fallback if VLM fails technically, grant partial points if programmatic passed
        feedback.append("VLM verification unavailable.")
        if score >= 60:
            score += 20 # Benefit of doubt if answer is correct

    # Final Pass/Fail
    passed = score >= 80  # Requires correct answer + file creation + partial VLM or full VLM
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }