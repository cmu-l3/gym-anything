#!/usr/bin/env python3
"""
Verifier for GCompris Photo Hunter task.

Verifies:
1. Agent found and entered the 'Photo Hunter' activity (VLM Trajectory).
2. Agent actively found differences (VLM Trajectory - red circles/highlights).
3. Agent completed the level (VLM Final State - success screen).
4. Agent saved the required proof screenshot (File Check).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_photo_hunter_differences(traj, env_info, task_info):
    """
    Verify the agent completed the Photo Hunter difference finding task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Basic Metrics
    proof_exists = result.get("proof_screenshot_exists", False)
    proof_valid = result.get("proof_created_during_task", False)
    app_running = result.get("app_was_running", False)

    # 3. VLM Verification
    # We need to verify the PROCESS, not just the result
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    # Prompt for VLM Analysis
    prompt = """
    You are analyzing an agent playing the 'Photo Hunter' game in GCompris educational software.
    
    The goal of the game is to spot the differences between two side-by-side images.
    When a difference is clicked, it is usually highlighted with a red circle or marker.
    When the level is finished, a 'Congratulations' or 'Success' animation (flower, star, penguin) appears.

    Analyze the sequence of screenshots provided:

    1. ACTIVITY_ENTERED: Do you see the Photo Hunter interface? (Two identical-looking images side-by-side)?
    2. PROGRESS_VISIBLE: Do you see evidence of play? Look for red circles or markers appearing on the images where differences were found.
    3. SUCCESS_STATE: Does the LAST image show a completion screen? (e.g., a large 'OK', a flower, a smiling penguin, or a 'level completed' graphic that overlays the game).
    4. NAVIGATION: Did the agent start at a menu and navigate to this game?

    Return a JSON object:
    {
        "activity_entered": true/false,
        "progress_visible": true/false,
        "success_state": true/false,
        "confidence": "low/medium/high",
        "reasoning": "Explain what you see"
    }
    """

    # Add final screenshot to analysis set if not present
    analysis_images = frames
    if final_screenshot:
        analysis_images.append(final_screenshot)

    vlm_result = query_vlm(images=analysis_images, prompt=prompt)
    
    # Parse VLM Result
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        activity_entered = parsed.get('activity_entered', False)
        progress_visible = parsed.get('progress_visible', False)
        success_state = parsed.get('success_state', False)
        reasoning = parsed.get('reasoning', "No reasoning provided")
    else:
        # Fail safe if VLM fails
        logger.error(f"VLM query failed: {vlm_result.get('error')}")
        activity_entered = False
        progress_visible = False
        success_state = False
        reasoning = "VLM analysis failed"

    # 4. Scoring Logic
    score = 0
    feedback_points = []

    # Criterion 1: Activity Entry (20 pts)
    if activity_entered:
        score += 20
        feedback_points.append("Entered Photo Hunter activity")
    else:
        feedback_points.append("Did not enter Photo Hunter activity")

    # Criterion 2: Visible Progress (30 pts)
    if progress_visible:
        score += 30
        feedback_points.append("Found differences (visible progress)")
    elif activity_entered:
        feedback_points.append("Entered activity but no progress/clicks detected")

    # Criterion 3: Success State (40 pts)
    if success_state:
        score += 40
        feedback_points.append("Completed level (success screen)")
    else:
        feedback_points.append("Did not complete level")

    # Criterion 4: Proof Screenshot (10 pts)
    if proof_exists and proof_valid:
        score += 10
        feedback_points.append("Proof screenshot saved correctly")
    elif proof_exists:
        # Exists but old? (Shouldn't happen in clean env, but good to handle)
        score += 5
        feedback_points.append("Proof screenshot exists (timestamp issue)")
    else:
        feedback_points.append("Proof screenshot missing")

    # Penalties
    if not app_running and score > 0:
        score = max(0, score - 5)
        feedback_points.append("Penalty: GCompris was closed")

    # Final Pass/Fail
    # Must have entered activity AND shown progress AND reached success state OR saved proof
    # Threshold: 90 (Requires almost perfect execution)
    passed = score >= 90

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_points),
        "details": {
            "vlm_reasoning": reasoning,
            "proof_file": proof_exists
        }
    }