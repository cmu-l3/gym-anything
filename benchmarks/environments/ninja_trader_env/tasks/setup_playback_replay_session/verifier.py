#!/usr/bin/env python3
"""
Verifier for setup_playback_replay_session task.

Verifies:
1. Workspace was saved (file timestamp)
2. XML contains SPY instrument with Daily bars
3. XML contains EMA indicator with Period 20
4. Playback connection was established (via Window detection or XML)
5. VLM confirms Playback Controller visual presence
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_playback_replay_session(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    result_path = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\setup_playback_replay_session_result.json"
    local_result = {}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: copy_from_env must handle Windows paths if the host is Linux and container is Windows
        # The framework typically handles this.
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            local_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        # Determine if failure is due to missing file (agent didn't run script/save) or other
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Programmatic Signals
    workspace_saved = local_result.get('workspace_saved', False)
    has_spy_daily = local_result.get('has_spy_daily', False)
    has_ema_20 = local_result.get('has_ema_20', False)
    playback_detected = local_result.get('has_playback_connection', False) or local_result.get('playback_window_visible', False)

    # 3. VLM Verification (Visual Confirmation)
    # We need to confirm the Playback Controller is actually visible and configured
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of NinjaTrader 8.
    The user is supposed to:
    1. Connect to 'Playback' (Market Replay).
    2. Open a Daily chart for SPY.
    3. Add an EMA 20 indicator.
    
    Look for:
    - A 'Playback Controller' window (small window with play/pause buttons and a date slider/input).
    - A chart window titled 'SPY' or 'SPY Daily'.
    - A line indicator overlaid on the chart (the EMA).
    - The Connection indicator (bottom left of Control Center) showing green or 'Playback'.
    
    Return JSON:
    {
        "playback_controller_visible": true/false,
        "spy_chart_visible": true/false,
        "ema_indicator_visible": true/false,
        "connection_status_playback": true/false
    }
    """
    
    vlm_data = {}
    try:
        # Query VLM with frames
        # We append final frame to ensuring we see the end state
        images_to_check = frames + [final_frame] if final_frame else frames
        if images_to_check:
            vlm_response = query_vlm(images=images_to_check, prompt=vlm_prompt)
            if vlm_response.get('success'):
                vlm_data = vlm_response.get('parsed', {})
    except Exception as e:
        logger.error(f"VLM check failed: {e}")

    # 4. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Workspace Saved (15 pts)
    if workspace_saved:
        score += 15
        feedback.append("Workspace saved.")
    else:
        feedback.append("Workspace NOT saved.")

    # Criterion 2: Playback Connection (25 pts)
    # Strong signal: Programmatic detection OR VLM distinct sighting
    if playback_detected or vlm_data.get('playback_controller_visible') or vlm_data.get('connection_status_playback'):
        score += 25
        feedback.append("Playback connection verified.")
    else:
        feedback.append("Playback connection NOT detected.")

    # Criterion 3: SPY Daily Chart (25 pts)
    if has_spy_daily:
        score += 25
        feedback.append("SPY Daily chart configuration found in XML.")
    elif vlm_data.get('spy_chart_visible'):
        score += 15 # Partial credit if visual only but not saved/detected in XML
        feedback.append("SPY chart visible but not verified in XML.")
    else:
        feedback.append("SPY Daily chart NOT detected.")

    # Criterion 4: EMA 20 Indicator (20 pts)
    if has_ema_20:
        score += 20
        feedback.append("EMA 20 indicator found in XML.")
    elif vlm_data.get('ema_indicator_visible'):
        score += 10 # Partial credit
        feedback.append("Indicator visible but not verified in XML.")
    else:
        feedback.append("EMA 20 indicator NOT detected.")
        
    # Criterion 5: Workflow/App Running (15 pts)
    if score > 0:
        score += 15
        feedback.append("Application interaction detected.")

    passed = (score >= 70) and (playback_detected or vlm_data.get('playback_controller_visible'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }