#!/usr/bin/env python3
"""
Verifier for disable_channels_5_to_8 task.

Evaluates:
1. File Verification: Agent created the requested screenshot file.
2. VLM Verification:
   - Session was started (waveforms visible).
   - Channels 5-8 were toggled off (progression).
   - Final state shows exactly 4 active channels (1-4).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_disable_channels(traj, env_info, task_info):
    """
    Verify the agent disabled channels 5-8 in OpenBCI GUI.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Verification infrastructure missing (copy or VLM)"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. File Verification (20 points max)
    output_exists = result.get('output_exists', False)
    file_created_during = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists:
        if output_size > 10240: # > 10KB
            score += 10
            feedback_parts.append("Screenshot file created.")
            if file_created_during:
                score += 10
                feedback_parts.append("File timestamp valid.")
            else:
                feedback_parts.append("File timestamp stale (pre-existing?).")
        else:
            feedback_parts.append("Screenshot file too small (empty?).")
    else:
        feedback_parts.append("Screenshot file NOT found.")

    # 3. Application State (5 points)
    if result.get('app_was_running', False):
        score += 5
    else:
        feedback_parts.append("OpenBCI GUI was closed at end.")

    # 4. VLM Verification (75 points max)
    # We sample frames to see the progression of turning off channels
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # If we have the agent's output file, we could verify that too, but the system screenshot 
    # of the app is more reliable for state verification.
    
    vlm_prompt = """
    You are verifying an OpenBCI GUI task. The user must:
    1. Start a synthetic session (showing scrolling waveform graphs).
    2. Turn OFF channels 5, 6, 7, and 8 using the channel buttons.
    3. Keep channels 1, 2, 3, and 4 ON.
    
    Examine the sequence of images and the final state.
    
    Q1. Is the OpenBCI GUI Time Series widget visible with scrolling waveform data?
    Q2. In the final state, how many channels appear to be ACTIVE (showing a trace line)?
    Q3. specifically, are the bottom 4 channels (5-8) disabled/grayed out/missing traces?
    Q4. Are the top 4 channels (1-4) still active?
    
    Return JSON:
    {
      "session_active": boolean,
      "visible_active_channel_count": number (approximate),
      "channels_5_8_disabled": boolean,
      "channels_1_4_active": boolean,
      "reasoning": "string"
    }
    """
    
    images_to_check = frames + [final_screenshot]
    vlm_response = query_vlm(
        prompt=vlm_prompt,
        images=images_to_check,
        model="gpt-4o" 
    )
    
    vlm_data = vlm_response.get('parsed', {})
    
    # Scoring VLM results
    if vlm_data.get('session_active', False):
        score += 15
        feedback_parts.append("Session successfully started.")
    else:
        feedback_parts.append("No active session detected.")
        
    active_count = vlm_data.get('visible_active_channel_count', 8)
    # Allow some leniency in VLM counting (3-5 is acceptable for 4)
    if 3 <= active_count <= 5:
        score += 20
        feedback_parts.append(f"Correct channel count active (~{active_count}).")
    else:
        feedback_parts.append(f"Incorrect channel count visible (~{active_count}, expected 4).")
        
    if vlm_data.get('channels_5_8_disabled', False):
        score += 20
        feedback_parts.append("Channels 5-8 disabled.")
    else:
        feedback_parts.append("Channels 5-8 NOT clearly disabled.")

    if vlm_data.get('channels_1_4_active', False):
        score += 20
        feedback_parts.append("Channels 1-4 active.")
    else:
        feedback_parts.append("Channels 1-4 NOT active.")

    # Calculate final status
    passed = score >= 60 and vlm_data.get('channels_5_8_disabled', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": vlm_data
    }