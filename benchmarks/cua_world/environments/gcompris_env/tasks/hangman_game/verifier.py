#!/usr/bin/env python3
"""
Verifier for GCompris Hangman Game task.
Uses hybrid verification:
1. Programmatic: Checks if screenshot file exists, has valid timestamp, and app is running.
2. VLM: Checks trajectory frames for navigation, gameplay (clicking letters), and completion.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hangman_game(traj, env_info, task_info):
    """
    Verify that the agent played Hangman in GCompris.
    """
    # 1. Setup and read programmatic results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {})
    
    # Load task_result.json
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Calculate Programmatic Score
    score = 0
    feedback_parts = []
    
    # Criterion: App running (10 pts)
    if result.get("app_running", False):
        score += scoring.get("app_running", 10)
        feedback_parts.append("GCompris running")
    else:
        feedback_parts.append("GCompris NOT running")

    # Criterion: Output file valid (15 pts)
    # Must exist, be >10KB (non-empty image), and created during task
    file_exists = result.get("output_file_exists", False)
    file_size = result.get("output_file_size", 0)
    created_during = result.get("output_created_during_task", False)
    
    if file_exists and file_size > 10000 and created_during:
        score += scoring.get("file_valid", 15)
        feedback_parts.append("Screenshot saved correctly")
    elif file_exists:
        score += 5  # Partial credit for file existing but wrong timestamp/size
        feedback_parts.append("Screenshot exists but invalid timestamp/size")
    else:
        feedback_parts.append("No screenshot saved")

    # Criterion: No crash (5 pts)
    if result.get("no_crash", True):
        score += scoring.get("no_crash", 5)
    else:
        feedback_parts.append("Crash detected")

    # 3. VLM Verification
    # We need to verify the ACTUAL gameplay using trajectory frames
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    # Prompt for VLM
    prompt = """
    You are verifying an agent playing the 'Hangman' game in GCompris educational software.
    
    Analyze these screenshots from the agent's session.
    
    I need to verify 4 things:
    1. ACTIVITY_OPEN: Did the agent successfully open the Hangman activity? Look for a screen with a gallows/hangman figure on the left, blank lines for a word, and an on-screen keyboard.
    2. GAMEPLAY_PROGRESS: Did the agent click letters? Look for letters on the on-screen keyboard turning gray or being highlighted, and letters appearing in the blank word slots.
    3. ROUND_COMPLETE: Did the round finish? A finished round shows EITHER the full word revealed OR the hangman figure fully drawn (head, body, arms, legs).
    4. WORKFLOW: Did the agent start at a menu and navigate to this game? (First few frames show menu, later frames show game).
    
    Respond in JSON:
    {
        "activity_open": true/false,
        "gameplay_progress": true/false,
        "round_complete": true/false,
        "workflow_valid": true/false,
        "reasoning": "Explain what you see"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    vlm_data = {}
    if vlm_result and vlm_result.get("success"):
        vlm_data = vlm_result.get("parsed", {})
        
        # Score VLM criteria
        if vlm_data.get("activity_open", False):
            score += scoring.get("vlm_activity_open", 20)
            feedback_parts.append("Hangman activity opened")
            
        if vlm_data.get("gameplay_progress", False):
            score += scoring.get("vlm_gameplay_progress", 20)
            feedback_parts.append("Gameplay detected (letters selected)")
            
        if vlm_data.get("round_complete", False):
            score += scoring.get("vlm_round_complete", 20)
            feedback_parts.append("Round completed")
            
        if vlm_data.get("workflow_valid", False):
            score += scoring.get("vlm_workflow", 10)
    else:
        feedback_parts.append("VLM verification failed")

    # 4. Final Assessment
    # Pass threshold: 50 points (Requires at least App Running + Activity Open + Some Gameplay)
    passed = score >= 50 and vlm_data.get("activity_open", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts),
        "details": {
            "programmatic": result,
            "vlm": vlm_data
        }
    }