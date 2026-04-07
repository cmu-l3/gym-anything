#!/usr/bin/env python3
"""
Verifier for configure_fft_channel_select task.

Verification Strategy:
1. Primary: VLM analysis of final screenshot and trajectory.
   - Count active traces in FFT widget (Target: 4).
   - Count active traces in Time Series widget (Target: 8).
   - Verify specific channels (1, 3, 5, 7) are the ones visible in FFT if possible (color/label).
2. Secondary: Check if app is running.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fft_configuration(traj, env_info, task_info):
    """
    Verify that the agent correctly configured the FFT widget channels.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load basic result info
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

    # Basic checks
    if not result.get('app_running', False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was closed or crashed."}

    # VLM Verification
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if final_img is None:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification."}

    # Prompt for VLM
    # We ask specifically about the two widgets to distinguish global vs local settings
    prompt = """
    You are verifying an OpenBCI GUI task. 
    The user was asked to configure the "FFT Plot" (frequency spectrum) to show ONLY channels 1, 3, 5, and 7.
    The "Time Series" (waveform scrolling) widget must still show ALL 8 channels.
    
    Analyze the final screenshot:
    1. Locate the FFT Plot widget (usually a line graph showing frequency Hz on x-axis). Count how many colored lines/traces are visible in it.
    2. Locate the Time Series widget (scrolling waveforms). Count how many distinct channel lines are visible (usually stacked vertically).
    3. Check if the channel buttons inside the FFT widget settings (if visible) match the 1,3,5,7 pattern.
    
    Return a JSON object with:
    {
        "fft_trace_count": <number>,
        "time_series_trace_count": <number>,
        "channels_1_3_5_7_visible_in_fft": <boolean>,
        "channels_2_4_6_8_hidden_in_fft": <boolean>,
        "all_channels_visible_in_time_series": <boolean>,
        "explanation": "<text>"
    }
    """

    vlm_response = query_vlm(
        prompt=prompt,
        images=frames + [final_img] # Send context to help identify widgets
    )

    try:
        # Check if the VLM response is a dictionary or string
        if isinstance(vlm_response, dict) and "parsed" in vlm_response:
             analysis = vlm_response["parsed"]
        elif isinstance(vlm_response, dict):
             analysis = vlm_response
        else:
             # Fallback if raw string (though query_vlm usually returns parsed JSON)
             # This part depends on the specific query_vlm implementation details in the env
             return {"passed": False, "score": 0, "feedback": "VLM returned unparseable response"}
             
        score = 0
        feedback = []

        # Criterion 1: FFT Traces (Max 40 points)
        fft_count = analysis.get("fft_trace_count", 8)
        
        if fft_count == 4:
            score += 40
            feedback.append("Correctly showing exactly 4 traces in FFT.")
        elif fft_count < 8:
            score += 20
            feedback.append(f"Partially correct: showing {fft_count} traces in FFT (expected 4).")
        else:
            feedback.append(f"Failed: showing {fft_count} traces in FFT (expected 4).")

        # Criterion 2: Time Series Traces (Max 40 points)
        # This is critical - did they break the global stream?
        ts_count = analysis.get("time_series_trace_count", 0)
        
        if ts_count >= 8:
            score += 40
            feedback.append("Correctly maintained all 8 channels in Time Series.")
        else:
            feedback.append(f"Failed: Time Series shows only {ts_count} channels (expected 8). You likely turned off channels globally instead of just in the FFT widget.")

        # Criterion 3: Specific Channel Selection (Max 20 points)
        if analysis.get("channels_1_3_5_7_visible_in_fft", False) and analysis.get("channels_2_4_6_8_hidden_in_fft", False):
            score += 20
            feedback.append("Specific channel selection appears correct.")
        
        passed = (score >= 80)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback) + f" (VLM: {analysis.get('explanation', '')})"
        }

    except Exception as e:
        logger.error(f"Error parsing VLM response: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }