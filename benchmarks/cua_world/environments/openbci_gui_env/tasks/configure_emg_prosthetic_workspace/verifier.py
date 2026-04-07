#!/usr/bin/env python3
"""
Verifier for configure_emg_prosthetic_workspace task.

Verification Strategy:
1. File Check: Confirm `emg_workspace.png` exists and was created during the task.
2. VLM Check: Analyze the final desktop screenshot to verify:
   - Layout is 2 panels.
   - Widgets are 'Time Series' and 'EMG'.
   - Bandpass filter is '5-50 Hz'.
   - Notch filter is 'None' or 'Off'.
   - Vertical Scale is '200 uV'.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_emg_workspace(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    # Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. File-based Scoring (30 points total)
    score = 0
    feedback = []
    
    # App running (10 pts)
    if result_data.get("app_running", False):
        score += 10
        feedback.append("OpenBCI GUI is running (+10)")
    else:
        feedback.append("OpenBCI GUI is NOT running (0)")

    # Target screenshot saved (20 pts)
    if result_data.get("target_file_exists", False):
        if result_data.get("target_file_created_during_task", False):
            if result_data.get("target_file_size", 0) > 10000: # >10KB
                score += 20
                feedback.append("Screenshot saved correctly (+20)")
            else:
                score += 10
                feedback.append("Screenshot file exists but seems too small/empty (+10)")
        else:
            score += 5
            feedback.append("Screenshot file exists but timestamp predates task (+5)")
    else:
        feedback.append("Target screenshot 'emg_workspace.png' not found (0)")

    # 3. VLM-based Visual Verification (70 points total)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback) + " | No visual evidence available."
        }

    vlm_prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    
    I need to verify the following configuration for an EMG workspace:
    1. **Layout**: Are there exactly 2 main widget panels visible side-by-side?
    2. **Widgets**: Do you see a "Time Series" widget and an "EMG" widget?
    3. **Filters**: Look at the top bar or filter settings. 
       - Is the Bandpass Filter set to "5-50 Hz"?
       - Is the Notch Filter set to "None" or "Off"?
    4. **Scale**: Look at the Time Series widget (usually top left button or y-axis labels). Is the vertical scale set to "200 uV"?
    5. **Streaming**: Is there data visible (lines/graphs) indicating the session is active?

    Return a JSON object with these boolean keys:
    {
        "two_panel_layout": true/false,
        "time_series_visible": true/false,
        "emg_widget_visible": true/false,
        "bandpass_5_50": true/false,
        "notch_off": true/false,
        "scale_200uv": true/false,
        "data_streaming": true/false
    }
    """

    vlm_response = query_vlm(prompt=vlm_prompt, image=final_screenshot)
    
    if not vlm_response.get('success'):
        feedback.append(f"Visual verification failed: {vlm_response.get('error')}")
    else:
        parsed = vlm_response.get('parsed', {})
        
        # Scoring logic for VLM
        # Layout & Widgets (30 pts)
        if parsed.get('two_panel_layout', False):
            score += 10
            feedback.append("2-panel layout detected (+10)")
        
        if parsed.get('time_series_visible', False) and parsed.get('emg_widget_visible', False):
            score += 20
            feedback.append("Correct widgets (Time Series + EMG) visible (+20)")
        elif parsed.get('time_series_visible', False) or parsed.get('emg_widget_visible', False):
            score += 10
            feedback.append("One correct widget visible (+10)")

        # Filters (30 pts)
        if parsed.get('bandpass_5_50', False):
            score += 15
            feedback.append("Bandpass 5-50Hz confirmed (+15)")
        else:
            feedback.append("Bandpass incorrect or not visible")

        if parsed.get('notch_off', False):
            score += 15
            feedback.append("Notch Off confirmed (+15)")
        else:
            feedback.append("Notch filter incorrect or not visible")

        # Scale (10 pts)
        if parsed.get('scale_200uv', False):
            score += 10
            feedback.append("Scale 200uV confirmed (+10)")
        else:
            feedback.append("Vertical scale incorrect or not visible")
            
        # Streaming check (Bonus/Safety - ensures they actually started session)
        if not parsed.get('data_streaming', False):
            feedback.append("(Warning: Data stream may not be active)")

    # Final Pass Logic
    # Threshold: 60/100
    # Mandatory: App running AND at least one widget correct AND file saved
    passed = (score >= 60) and result_data.get("app_running", False) and result_data.get("target_file_exists", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }