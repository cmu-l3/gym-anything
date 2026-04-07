#!/usr/bin/env python3
"""
Verifier for stream_filtered_playback_lsl task.

Checks:
1. Agent created the requested screenshot (anti-gaming check).
2. VLM analyzes screenshot to confirm:
   - Playback mode is active (real data).
   - Notch filter is 60Hz.
   - Bandpass filter is 1-50Hz.
   - Networking widget is set to LSL.
   - Stream name is 'NeuroPrep_Stream'.
   - 'Transmit Filtered' is enabled.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_filtered_playback_lsl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function missing"}

    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. File Verification (20 points)
    # Did the agent save the screenshot as requested?
    if result.get('agent_screenshot_exists') and result.get('agent_screenshot_valid_time'):
        score += 20
        feedback.append("Screenshot saved correctly.")
        # Retrieve the agent's screenshot for VLM analysis if possible
        agent_screenshot_path = result.get('agent_screenshot_path')
        local_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env(agent_screenshot_path, local_screenshot)
            verification_image = local_screenshot
        except:
            # Fallback to final frame if agent screenshot retrieval fails
            verification_image = get_final_screenshot(traj)
    else:
        feedback.append("Screenshot not found or created before task start.")
        verification_image = get_final_screenshot(traj)

    if not result.get('app_running'):
        feedback.append("Warning: OpenBCI GUI was not running at the end.")

    # 2. VLM Verification (80 points)
    # We analyze the verification image (either agent's screenshot or final frame)
    
    prompt = """
    Analyze this OpenBCI GUI screenshot for a data streaming task.
    Check the following criteria carefully:
    
    1. **Session Mode**: Is it in 'Playback' mode? (Look for playback controls, file name, or 'Playback' text).
    2. **Notch Filter**: Is the Notch filter set to 60 Hz? (Look for 'Notch 60Hz' or similar in the top bar or settings).
    3. **Bandpass Filter**: Is the Bandpass filter set to 1-50 Hz? (Look for 'BP 1-50Hz' or similar).
    4. **Networking/LSL**: 
       - Is the Networking widget visible?
       - Is 'LSL' selected?
       - Is the name 'NeuroPrep_Stream'?
       - Is the 'Filter' or 'Filtered' toggle/button ACTIVE/CHECKED? (This is critical).
       - Is the stream status 'Running' or 'Stop' (implying it is started)?

    Respond in JSON format:
    {
        "playback_mode": boolean,
        "notch_60hz": boolean,
        "bandpass_1_50hz": boolean,
        "lsl_selected": boolean,
        "name_correct": boolean,
        "filtered_toggle_active": boolean,
        "stream_active": boolean
    }
    """
    
    # We use the trajectory frames + final image to catch the workflow if the final state is ambiguous
    images_to_check = sample_trajectory_frames(traj, 2)
    if verification_image:
        images_to_check.append(verification_image)
        
    vlm_response = query_vlm(
        prompt=prompt,
        images=images_to_check,
        model="gpt-4o" # High capability needed for reading small UI text
    )
    
    try:
        # VLM output parsing
        analysis = vlm_response.get('parsed', {})
        if not analysis and 'result' in vlm_response:
             # Fallback if direct parsing failed but text exists
             import re
             json_match = re.search(r'\{.*\}', vlm_response['result'], re.DOTALL)
             if json_match:
                 analysis = json.loads(json_match.group(0))

        # Scoring based on VLM analysis
        if analysis.get('playback_mode'):
            score += 10
            feedback.append("Playback mode confirmed.")
        else:
            feedback.append("Could not confirm Playback mode.")

        if analysis.get('notch_60hz'):
            score += 15
            feedback.append("Notch 60Hz confirmed.")
        else:
            feedback.append("Notch filter incorrect or not visible.")

        if analysis.get('bandpass_1_50hz'):
            score += 15
            feedback.append("Bandpass 1-50Hz confirmed.")
        else:
            feedback.append("Bandpass filter incorrect (expected 1-50Hz).")

        if analysis.get('lsl_selected'):
            score += 10
            feedback.append("LSL protocol selected.")
        
        if analysis.get('name_correct'):
            score += 10
            feedback.append("Stream name 'NeuroPrep_Stream' confirmed.")
        else:
            feedback.append("Stream name incorrect.")

        if analysis.get('filtered_toggle_active'):
            score += 20
            feedback.append("'Transmit Filtered' is enabled.")
        else:
            feedback.append("'Transmit Filtered' option NOT detected (Critical).")

    except Exception as e:
        logger.error(f"VLM parsing error: {e}")
        feedback.append(f"Verification error during image analysis. Raw VLM: {vlm_response.get('result', 'No result')}")
        # Partial credit for file existence if VLM fails completely
        if score < 20 and result.get('agent_screenshot_exists'):
            score = 20

    # Cleanup local temp file
    if 'local_screenshot' in locals() and os.path.exists(local_screenshot):
        os.unlink(local_screenshot)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }