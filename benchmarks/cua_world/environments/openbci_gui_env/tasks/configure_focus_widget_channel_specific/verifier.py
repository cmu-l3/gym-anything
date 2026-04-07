#!/usr/bin/env python3
"""
Verifier for Configure Focus Widget Task.

Verification Strategy:
1. Programmatic Check: Ensure OpenBCI GUI is still running (Export script).
2. VLM Verification: Analyze the final screenshot to confirm:
   - Session is active (streaming data).
   - "Focus" widget is present.
   - Focus widget settings panel is OPEN.
   - Channel 1 is SELECTED.
   - Channels 2-8 are DESELECTED.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory for shared utilities if needed
# sys.path.insert(0, str(Path(__file__).parent.parent))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_focus_widget(traj, env_info, task_info):
    """
    Verify the Focus widget channel configuration using VLM.
    """
    # 1. Setup & Imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    get_final_screenshot = env_info.get('get_final_screenshot', lambda t: t[-1]['observation']['image'] if t else None)

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: query_vlm not available"}

    # 2. Get Programmatic Result (App State)
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    app_running = task_result.get('app_was_running', False)
    
    # 3. Get Screenshot for VLM
    # Prefer the one captured by export_result.sh if available via copy_from_env,
    # otherwise use the trajectory's final frame.
    final_screenshot = None
    
    # Try to get the high-res screenshot from container
    try:
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        copy_from_env("/tmp/task_final.png", temp_img.name)
        final_screenshot = temp_img.name
    except Exception:
        # Fallback to trajectory frame
        from gym_anything.vlm import get_final_screenshot as gfs
        final_screenshot = gfs(traj)

    if not final_screenshot:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No evidence available: Could not retrieve final screenshot."
        }

    # 4. VLM Verification
    prompt = """
    You are verifying an OpenBCI GUI configuration task.
    
    Task Goal: 
    1. A session should be running (streaming data).
    2. The 'Focus' widget should be visible.
    3. The Focus widget's 'Hardware Settings' or 'Channels' panel must be OPEN.
    4. In that settings panel, CHANNEL 1 must be CHECKED/ON.
    5. CHANNELS 2, 3, 4, 5, 6, 7, and 8 must be UNCHECKED/OFF.

    Analyze the screenshot and answer strictly in JSON format:
    {
        "session_active": boolean,
        "focus_widget_visible": boolean,
        "settings_panel_open": boolean,
        "channel_1_selected": boolean,
        "channels_2_to_8_deselected": boolean,
        "reasoning": "string explanation"
    }
    
    Notes:
    - The settings panel usually shows a list of channel numbers (1-8 or 1-16).
    - Active channels usually have a filled box or colored highlight. Inactive are empty/grey.
    - If the settings panel is NOT visible, set "settings_panel_open" to false.
    """

    vlm_response = query_vlm(
        prompt=prompt,
        images=[final_screenshot]
    )
    
    # 5. Scoring
    score = 0
    feedback_parts = []
    
    try:
        # Handle potential string wrapping of JSON
        if isinstance(vlm_response, str):
             # Try to parse if it returned a string
             import re
             json_match = re.search(r'\{.*\}', vlm_response, re.DOTALL)
             if json_match:
                 data = json.loads(json_match.group(0))
             else:
                 data = {}
        else:
             data = vlm_response
             
        # Normalize keys if VLM deviates
        session_active = data.get('session_active', False)
        widget_visible = data.get('focus_widget_visible', False)
        settings_open = data.get('settings_panel_open', False)
        ch1_ok = data.get('channel_1_selected', False)
        others_ok = data.get('channels_2_to_8_deselected', False)
        reasoning = data.get('reasoning', 'No reasoning provided')

        # Criteria 1: App Running (10 pts)
        if app_running:
            score += 10
            feedback_parts.append("App running")
        else:
            feedback_parts.append("App crashed/closed")

        # Criteria 2: Session Active (20 pts)
        if session_active:
            score += 20
            feedback_parts.append("Session active")
        else:
            feedback_parts.append("Session NOT active")

        # Criteria 3: Widget Visible (20 pts)
        if widget_visible:
            score += 20
            feedback_parts.append("Focus widget found")
        else:
            feedback_parts.append("Focus widget missing")

        # Criteria 4: Settings Open (10 pts)
        if settings_open:
            score += 10
            feedback_parts.append("Settings panel open")
        else:
            feedback_parts.append("Settings panel closed (cannot verify channels)")

        # Criteria 5: Channel Logic (40 pts)
        if settings_open:
            if ch1_ok:
                score += 20
                feedback_parts.append("Ch1 Active")
            else:
                feedback_parts.append("Ch1 Inactive (Fail)")
                
            if others_ok:
                score += 20
                feedback_parts.append("Ch2-8 Inactive")
            else:
                feedback_parts.append("Ch2-8 Active (Fail)")
        else:
            feedback_parts.append("Channel config unverified")

    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Verification error: {str(e)}",
            "details": {"vlm_raw": str(vlm_response)}
        }

    # Pass Threshold
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" [VLM: {reasoning}]",
        "details": data
    }