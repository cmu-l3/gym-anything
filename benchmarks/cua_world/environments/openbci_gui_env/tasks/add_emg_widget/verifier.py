#!/usr/bin/env python3
"""
Verifier for add_emg_widget task using VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_emg_widget(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Started a session (moved past Control Panel).
    2. Added the EMG widget.
    3. Set uV limit to 200.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Capabilities missing (copy/VLM)"}

    # 1. Check basic file result (Application running)
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

    if not result.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was not running at end of task."}

    # 2. VLM Verification
    # We use trajectory frames to ensure they actually interacted with the menu
    # and the final frame to verify the final configuration.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available."}
    
    all_images = frames + [final_frame]
    
    prompt = """
    You are verifying an OpenBCI GUI task. The user must:
    1. Start a 'Synthetic' session (waveforms should be visible and moving/streaming).
    2. Add the 'EMG' widget to one of the panels.
    3. Set the EMG widget's uV Limit to '200'.

    Analyze the provided screenshots (trajectory + final state).
    
    Look for:
    - Evidence of the System Control Panel being left and a dashboard appearing.
    - A widget labeled "EMG" (distinct from Time Series, FFT, etc).
    - Inside the EMG widget, a setting or dropdown reading "200" or "200 uV".
    - Active data streaming (squiggly lines/waveforms in Time Series or changing bars in EMG).

    Return JSON:
    {
        "session_started": boolean,
        "emg_widget_visible": boolean,
        "uv_limit_is_200": boolean,
        "data_streaming": boolean,
        "explanation": "string"
    }
    """
    
    vlm_resp = query_vlm(images=all_images, prompt=prompt)
    
    if not vlm_resp.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM verification failed."}
        
    analysis = vlm_resp.get("parsed", {})
    
    # Scoring
    score = 0
    feedback = []
    
    if analysis.get("session_started"):
        score += 20
        feedback.append("Session started successfully.")
    else:
        feedback.append("Failed to start session.")
        
    if analysis.get("emg_widget_visible"):
        score += 40
        feedback.append("EMG widget visible.")
    else:
        feedback.append("EMG widget NOT found.")
        
    if analysis.get("uv_limit_is_200"):
        score += 30
        feedback.append("uV limit set to 200.")
    else:
        feedback.append("uV limit NOT set to 200.")

    if analysis.get("data_streaming"):
        score += 10
        feedback.append("Data is streaming.")
    else:
        feedback.append("Data stream inactive.")

    passed = score >= 90  # Strict pass: needs widget + config + streaming
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback) + f" ({analysis.get('explanation', '')})"
    }