#!/usr/bin/env python3
"""
Verifier for configure_custom_channel_filters task.

Strategy:
1. Verify OpenBCI is running and screenshot was saved (basics).
2. Use VLM to inspect the *Agent's Screenshot* (preferred) or Final Screenshot.
3. VLM checks:
   - Is the Filters window open?
   - Is Ch1 set to 4-8 Hz?
   - Is Ch2 set to 8-13 Hz?
   - Is Playback mode active (context)?
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_filters(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic signals from JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # Basic Checks
    if result_data.get("app_running"):
        score += 10
        feedback.append("OpenBCI GUI is running.")
    else:
        feedback.append("OpenBCI GUI was closed.")

    has_agent_screenshot = result_data.get("agent_screenshot_exists") and result_data.get("agent_screenshot_fresh")
    if has_agent_screenshot:
        score += 10
        feedback.append("Agent saved the requested evidence screenshot.")
    else:
        feedback.append("Agent did not save a fresh screenshot to the correct path.")

    # 2. VLM Verification
    # We prioritize the agent's screenshot if it exists, as it likely frames the relevant UI.
    # Otherwise, we use the final state screenshot.
    images_to_check = []
    
    # Try to get agent's evidence image
    if has_agent_screenshot:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/tmp/agent_evidence.png", temp_img.name)
            images_to_check.append(temp_img.name)
        except Exception:
            pass

    # Add final state screenshot
    final_screen = get_final_screenshot(traj)
    if final_screen:
        images_to_check.append(final_screen)
        
    # Add a trajectory frame in case they closed the window before the end
    traj_frames = sample_trajectory_frames(traj, n=3)
    images_to_check.extend(traj_frames)

    if not images_to_check:
        return {"passed": False, "score": score, "feedback": "No images available for verification."}

    # Construct Prompt
    # We ask the VLM to look for the specific table values.
    prompt = """
    You are verifying an OpenBCI GUI task. 
    The user is supposed to:
    1. Be in PLAYBACK mode (look for playback progress bar or 'Playback' text).
    2. Have the 'Filters' window open.
    3. Have Channel 1 configured to Bandpass 4.0 - 8.0 Hz.
    4. Have Channel 2 configured to Bandpass 8.0 - 13.0 Hz.

    Examine the provided images. 
    Can you see the Filters configuration table?
    Does Row 1 (Channel 1) show 4.0 (or 4) and 8.0 (or 8)?
    Does Row 2 (Channel 2) show 8.0 (or 8) and 13.0 (or 13)?
    
    Output JSON:
    {
        "filters_window_visible": boolean,
        "playback_mode_active": boolean,
        "channel_1_correct": boolean,
        "channel_2_correct": boolean,
        "reasoning": "string"
    }
    """

    # Query VLM
    # We pass the most likely best image first (agent screenshot)
    vlm_result = query_vlm(
        prompt=prompt,
        images=images_to_check,  # Framework handles list of paths/images
        model="gpt-4o" # Use high capacity model for reading text/numbers
    )

    if not vlm_result.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM Verification failed: {vlm_result.get('error')}"}

    parsed = vlm_result.get("parsed", {})
    
    # Scoring based on VLM
    if parsed.get("playback_mode_active"):
        score += 20
        feedback.append("VLM confirmed Playback mode.")
    
    if parsed.get("filters_window_visible"):
        score += 20
        feedback.append("VLM confirmed Filters window is open.")
        
        # Only verify values if window is visible
        if parsed.get("channel_1_correct"):
            score += 20
            feedback.append("VLM confirmed Channel 1 filter (4-8 Hz).")
        else:
            feedback.append("Channel 1 filter incorrect or not visible.")

        if parsed.get("channel_2_correct"):
            score += 20
            feedback.append("VLM confirmed Channel 2 filter (8-13 Hz).")
        else:
            feedback.append("Channel 2 filter incorrect or not visible.")
    else:
        feedback.append("Filters window not found in screenshots.")

    # Final tally
    passed = score >= 60 and parsed.get("filters_window_visible")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": parsed
    }