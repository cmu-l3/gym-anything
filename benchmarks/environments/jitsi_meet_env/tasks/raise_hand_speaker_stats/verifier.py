#!/usr/bin/env python3
"""
Verifier for raise_hand_speaker_stats task.

Verification Strategy:
1. Programmatic: Check agent is in correct meeting room (URL check).
2. VLM (Trajectory): Verify agent clicked "Join", "Raise Hand", and "Speaker Stats".
3. VLM (Final State): Verify "Raised Hand" icon AND "Speaker Stats" panel are visible.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_raise_hand_speaker_stats(traj, env_info, task_info):
    """
    Verify the agent raised hand and opened speaker stats.
    """
    # 1. Setup - Load result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # 2. Programmatic Checks (30 points)
    
    # Check if Firefox is running (5 pts)
    if result.get("firefox_running", False):
        score += 5
    else:
        feedback_parts.append("Firefox is not running.")

    # Check correct URL (25 pts)
    # Expected: .../InterpreterSession2024
    current_url = result.get("current_url", "")
    target_room = "InterpreterSession2024"
    
    if target_room.lower() in current_url.lower():
        score += 25
        feedback_parts.append(f"Correct meeting room joined ({target_room}).")
    else:
        feedback_parts.append(f"Incorrect URL or not in meeting. Found: {current_url}")

    # 3. VLM Verification (70 points)
    
    # Sample frames to see workflow
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No screenshots available for verification."
        }
        
    all_images = frames + [final_frame]
    
    # Prompt for VLM Analysis
    prompt = """
    You are verifying a Jitsi Meet video conferencing task.
    The agent was supposed to:
    1. Join the meeting "InterpreterSession2024" as "Maria Interpreter".
    2. Raise their hand (look for hand icon on toolbar or video tile).
    3. Open the "Speaker Stats" panel (look for a table with names and time bars).

    Analyze the sequence of images.
    
    Check for these specific criteria:
    1. JOINED: Did the agent leave the pre-join screen and enter the meeting?
    2. NAME_SET: Is the name "Maria Interpreter" visible anywhere (e.g. on a video tile or in stats)?
    3. HAND_RAISED: Is there a blue/white hand icon visible on the user's tile or highlighted in the toolbar?
    4. STATS_OPEN: Is the "Speaker Statistics" window/panel open and visible in the FINAL frame?
    
    Respond in JSON format:
    {
        "joined_meeting": true/false,
        "name_visible": true/false,
        "hand_raised_visible": true/false,
        "speaker_stats_visible": true/false,
        "workflow_score": 0-100,
        "reasoning": "explanation"
    }
    """
    
    try:
        vlm_resp = query_vlm(prompt=prompt, images=all_images)
        analysis = vlm_resp.get("parsed", {})
        
        # Scoring based on VLM
        if analysis.get("joined_meeting", False):
            score += 15
            feedback_parts.append("VLM confirmed meeting join.")
            
        if analysis.get("name_visible", False):
            score += 10
            feedback_parts.append("VLM confirmed display name set.")
            
        if analysis.get("hand_raised_visible", False):
            score += 20
            feedback_parts.append("VLM confirmed hand raised.")
            
        if analysis.get("speaker_stats_visible", False):
            score += 25
            feedback_parts.append("VLM confirmed Speaker Stats open.")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed (technical error).")

    # 4. Final Assessment
    passed = score >= 60 and analysis.get("speaker_stats_visible", False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }