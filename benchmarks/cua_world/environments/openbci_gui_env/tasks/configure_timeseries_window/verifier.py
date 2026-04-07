#!/usr/bin/env python3
import json
import os
import base64
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_timeseries_window(traj, env_info, task_info):
    """
    Verifies the OpenBCI GUI Time Series configuration task.
    
    Verification Signals:
    1. Config File (Programmatic): Checks for existence and correct key-value pairs.
    2. VLM (Visual): Checks the GUI state for:
       - Playback mode active
       - Time Series widget visibility
       - "5 s" window setting
       - "50 uV" vertical scale setting
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification (50 points total)
    score = 0
    feedback_parts = []
    
    # Check 1: App Running (5 pts)
    if result.get('app_running', False):
        score += 5
    else:
        feedback_parts.append("OpenBCI GUI was not running at end of task.")

    # Check 2: Config File Existence & Timestamp (15 pts)
    config_exists = result.get('config_file_exists', False)
    config_fresh = result.get('config_created_during_task', False)
    
    if config_exists:
        if config_fresh:
            score += 15
            feedback_parts.append("Config file created successfully.")
        else:
            score += 5
            feedback_parts.append("Config file exists but timestamp is old (anti-gaming check failed).")
    else:
        feedback_parts.append("Config file not found.")

    # Check 3: Config Content (30 pts)
    # Expected: window_seconds=5, vertical_scale_uv=50, mode=playback
    content_b64 = result.get('config_content_base64', '')
    content = ""
    if content_b64:
        try:
            content = base64.b64decode(content_b64).decode('utf-8')
        except:
            pass
            
    if "window_seconds=5" in content:
        score += 10
    else:
        feedback_parts.append("Missing or incorrect 'window_seconds' in config.")

    if "vertical_scale_uv=50" in content:
        score += 10
    else:
        feedback_parts.append("Missing or incorrect 'vertical_scale_uv' in config.")
        
    if "mode=playback" in content.lower():
        score += 10
    else:
        feedback_parts.append("Missing or incorrect 'mode' in config.")

    # 3. VLM Verification (50 points total)
    # We use trajectory frames to ensure they actually interacted with the GUI
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    Analyze these screenshots of the OpenBCI GUI. The user is supposed to be playing back an EEG recording and configuring the Time Series widget.
    
    Check for the following specific visual elements:
    1. **Time Series Widget**: Is a widget displaying EEG waveforms visible?
    2. **Horizontal Window**: Look for the time duration dropdown or label on the Time Series widget. Does it say "5 s" or show a 5-second interval?
    3. **Vertical Scale**: Look for the vertical scale dropdown/label. Does it say "50 uV"?
    4. **Data Streaming**: Are there visible waveforms (lines) in the plot area, indicating data is loaded?
    5. **Playback Mode**: Is the top status bar or data source indicating "Playback" or showing a file progress bar?

    Return a JSON object with boolean keys:
    {
        "time_series_visible": true/false,
        "window_is_5s": true/false,
        "scale_is_50uv": true/false,
        "data_waveforms_visible": true/false,
        "is_playback_mode": true/false
    }
    """
    
    vlm_response = query_vlm(frames, vlm_prompt)
    
    # Default VLM scores
    vlm_score = 0
    if vlm_response and 'parsed' in vlm_response:
        analysis = vlm_response['parsed']
        
        if analysis.get('time_series_visible', False):
            vlm_score += 10
        else:
            feedback_parts.append("VLM: Time Series widget not visible.")
            
        if analysis.get('window_is_5s', False):
            vlm_score += 10
            feedback_parts.append("VLM confirmed 5s window.")
        else:
            feedback_parts.append("VLM: Could not verify 5s window setting.")
            
        if analysis.get('scale_is_50uv', False):
            vlm_score += 10
            feedback_parts.append("VLM confirmed 50uV scale.")
        else:
            feedback_parts.append("VLM: Could not verify 50uV scale setting.")
            
        if analysis.get('data_waveforms_visible', False):
            vlm_score += 10
        else:
            feedback_parts.append("VLM: No EEG waveforms visible (stream might not be running).")
            
        if analysis.get('is_playback_mode', False):
            vlm_score += 10
        
    score += vlm_score

    # Final Pass/Fail
    # Threshold: 60 points total, MUST have config file created and VLM confirm at least data visibility
    passed = (score >= 60) and config_fresh and (vlm_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }