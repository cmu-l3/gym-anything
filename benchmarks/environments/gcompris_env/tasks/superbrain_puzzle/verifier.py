#!/usr/bin/env python3
"""
Verifier for GCompris Super Brain (Mastermind) Task.

Verification Strategy:
1. Programmatic: Check if GCompris was running and if data files were modified (activity evidence).
2. VLM (Trajectory):
   - Confirm navigation to "Super Brain" (game board visible).
   - Confirm gameplay (rows of pegs filled).
   - Confirm success (celebration animation or Level 2 prompt).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed, 
# though we usually expect standard gym_anything imports in the environment.
# For this script, we'll assume the standard verifier signature.

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_superbrain_puzzle(traj, env_info, task_info):
    """
    Verify the agent completed Level 1 of Super Brain.
    """
    # 1. Setup & Imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm') 
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System capabilities missing (copy/VLM)"}

    # 2. Retrieve Exported Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Base Scoring (Programmatic)
    score = 0
    feedback_log = []
    
    # Check 1: App was running at end (10 pts)
    if result_data.get("app_was_running", False):
        score += 10
        feedback_log.append("GCompris was open.")
    else:
        feedback_log.append("GCompris was NOT open at end.")

    # Check 2: Data modification (Activity played) (10 pts)
    if result_data.get("activity_data_modified", False):
        score += 10
        feedback_log.append("Activity data modified (gameplay detected).")
    else:
        feedback_log.append("No activity data modified.")

    # 4. VLM Verification (Trajectory Analysis)
    # We sample frames to see the progression.
    from gym_anything.vlm import sample_trajectory_frames
    
    frames = sample_trajectory_frames(traj, n=4)
    
    prompt = """
    You are analyzing screenshots of a user playing the 'Super Brain' game in GCompris (educational software).
    This is a Mastermind-style logic puzzle where the user drags colored pegs into rows to guess a hidden code.
    
    Analyze the sequence of images and answer the following JSON:
    {
        "activity_found": boolean, // Is the Super Brain game board visible in any frame? (Look for rows of empty circular slots or colored pegs, usually dark background)
        "gameplay_progress": boolean, // Did the user place pegs? Are there rows filled with colored pegs?
        "level_completed": boolean, // Is there a success state? Look for: A flower/star/penguin celebration animation, OR a 'Level 2' indicator, OR a 'Great' message.
        "description": "Brief description of what you see."
    }
    """
    
    vlm_response = query_vlm(images=frames, prompt=prompt)
    
    if not vlm_response.get('success'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"VLM Verification failed: {vlm_response.get('error')}"
        }
        
    analysis = vlm_response.get('parsed', {})
    
    # Score VLM components
    # Activity Found (25 pts)
    if analysis.get("activity_found"):
        score += 25
        feedback_log.append("Super Brain activity identified.")
    else:
        feedback_log.append("Could not confirm Super Brain activity was opened.")

    # Gameplay Progress (25 pts)
    if analysis.get("gameplay_progress"):
        score += 25
        feedback_log.append("Gameplay attempts (guesses) detected.")
    else:
        feedback_log.append("No gameplay attempts visible.")

    # Completion (30 pts)
    if analysis.get("level_completed"):
        score += 30
        feedback_log.append("Level completion verified (Success screen).")
    else:
        feedback_log.append("Level completion NOT detected.")

    # 5. Final Determination
    # Pass threshold: 70/100 (Must have found activity + some gameplay + running app, or full completion)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log),
        "details": analysis
    }