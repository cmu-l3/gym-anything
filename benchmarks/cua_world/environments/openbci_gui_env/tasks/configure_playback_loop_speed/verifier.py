#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_playback_speed(traj, env_info, task_info):
    """
    Verifies that the OpenBCI GUI is in playback mode with 2.0x speed and Loop enabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Load basic file/state checks from JSON
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Criterion 1: App Running (10 pts)
    if task_result.get("app_was_running", False):
        score += 10
        feedback.append("OpenBCI GUI was running.")
    else:
        feedback.append("OpenBCI GUI was NOT running at the end.")

    # Criterion 2: Agent Saved Screenshot (10 pts)
    # This proves they knew how to take the screenshot as requested
    if task_result.get("agent_screenshot_exists", False):
        score += 10
        feedback.append("Agent saved the requested screenshot.")
    else:
        feedback.append("Agent failed to save the screenshot at the specific path.")

    # Criterion 3 & 4 & 5: VLM Verification of State (80 pts total)
    # We check the final state of the GUI to verify settings.
    # Using trajectory frames helps confirm they navigated there, but final state is key for settings.
    
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot is None:
         return {"passed": False, "score": score, "feedback": "No visual evidence available (screenshot failed)."}

    # Prompt designed to extract the specific UI states
    prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    I need to verify three specific configurations:
    1. Is the data source in 'Playback' mode? (Look for 'Playback' text, a file progress bar, or playback controls like Play/Pause).
    2. Is the Playback Speed set to '2.0x' or '200%'? (Look closely at the speed indicator number).
    3. Is 'Looping' enabled? (Look for a Loop icon, usually circular arrows, that is highlighted/active or checked).
    4. Is data actively streaming? (Are there waveforms visible in the main Time Series graph area?)

    Return a JSON object with keys:
    - "is_playback_mode": boolean
    - "speed_is_2x": boolean
    - "loop_is_active": boolean
    - "data_is_streaming": boolean
    - "reasoning": string
    """

    try:
        vlm_resp = query_vlm(
            prompt=prompt,
            images=[final_screenshot],
            model="gpt-4o" # or equivalent high-capacity model
        )
        
        # Safe parsing of VLM response
        if isinstance(vlm_resp, dict):
            # If the wrapper returns a dict directly
            analysis = vlm_resp
        else:
            # If it returns a string (older interface), try to parse JSON
            # This block assumes the query_vlm tool handles parsing or returns an object
            # Adjust based on specific gym_anything interface
            analysis = vlm_resp.get('parsed', {}) if isinstance(vlm_resp, dict) else {}

        # Fallback if parsing fails but text exists (simplified for robustness)
        if not analysis and isinstance(vlm_resp, dict) and 'response' in vlm_resp:
             # Basic keyword matching if JSON parsing failed
             text = vlm_resp['response'].lower()
             analysis = {
                 "is_playback_mode": "playback" in text,
                 "speed_is_2x": "2.0" in text or "2x" in text or "200" in text,
                 "loop_is_active": "loop" in text and ("active" in text or "enabled" in text or "highlighted" in text),
                 "data_is_streaming": "wave" in text or "stream" in text
             }

        # Scoring based on VLM analysis
        if analysis.get("is_playback_mode", False):
            score += 20
            feedback.append("Verified: Playback mode active.")
        else:
            feedback.append("Failed: Could not verify Playback mode.")

        if analysis.get("speed_is_2x", False):
            score += 30
            feedback.append("Verified: Speed set to 2.0x.")
        else:
            feedback.append("Failed: Playback speed does not appear to be 2.0x.")

        if analysis.get("loop_is_active", False):
            score += 20
            feedback.append("Verified: Loop mode enabled.")
        else:
            feedback.append("Failed: Loop mode does not appear enabled.")

        if analysis.get("data_is_streaming", False):
            score += 10
            feedback.append("Verified: Data waveforms visible.")
        else:
            feedback.append("Failed: No data streaming visible.")

    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback.append(f"Verification error: {str(e)}")

    passed = score >= 70  # Threshold requires correct speed and loop + basic setup
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }