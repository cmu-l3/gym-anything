#!/usr/bin/env python3
"""
Verifier for GCompris Left/Right Orientation task.
Uses VLM trajectory analysis to verify activity navigation, gameplay, and completion.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for trajectory verification
VERIFICATION_PROMPT = """
You are verifying an agent's performance in the GCompris educational software "Left and Right" activity.

The agent must:
1. Navigate to the "Left and Right" activity (usually via search or menu).
2. Play the game: A hand or object is shown, and the agent must click "Left" or "Right".
3. Complete the level: A congratulations animation (flower, star, penguin, etc.) appears.

Review the provided screenshots (chronological trajectory + final state).

Assess the following:
1. ACTIVITY_FOUND: Did the agent find and open the "Left and Right" activity? (Look for a screen with a central hand image and side buttons).
2. GAMEPLAY_PROGRESSION: Do the screenshots show different hands/objects being displayed over time? (This proves the agent is answering questions).
3. SUCCESS_STATE: Does the FINAL screenshot (or near-final) show a "Congratulations", "Well Done", or a victory animation (e.g., a flower appearing, a penguin waving)?
4. SEARCH_USAGE: Is there evidence the agent used the search bar (magnifying glass) or browsed menus?

Respond in JSON format:
{
    "activity_found": true/false,
    "gameplay_progression": true/false,
    "success_state": true/false,
    "search_usage": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what was observed"
}
"""

def verify_left_right_orientation(traj, env_info, task_info):
    """
    Verify that the agent completed the Left/Right orientation activity.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve basic task result (app running status)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    app_running = result.get("app_was_running", False)
    
    # 2. Prepare VLM verification
    # Sample frames to see progression
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No screenshots available"}
    
    # Combine frames for VLM context
    verification_images = frames + [final_screenshot]
    
    # Query VLM
    vlm_response = query_vlm(
        images=verification_images,
        prompt=VERIFICATION_PROMPT
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}
    
    parsed = vlm_response.get("parsed", {})
    
    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criteria 1: App Stability (10 pts)
    if app_running:
        score += 10
        feedback_parts.append("App remained open")
    else:
        feedback_parts.append("App closed unexpectedly")

    # Criteria 2: Activity Found (20 pts)
    if parsed.get("activity_found"):
        score += 20
        feedback_parts.append("Activity located")
    else:
        feedback_parts.append("Activity not found")

    # Criteria 3: Gameplay Progression (30 pts)
    if parsed.get("gameplay_progression"):
        score += 30
        feedback_parts.append("Progression observed")
    else:
        feedback_parts.append("No gameplay progression")

    # Criteria 4: Success State (40 pts)
    if parsed.get("success_state"):
        score += 40
        feedback_parts.append("Level completed")
    else:
        feedback_parts.append("Level not completed")

    # Pass Threshold
    passed = score >= 90  # Requires completion
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": parsed
    }