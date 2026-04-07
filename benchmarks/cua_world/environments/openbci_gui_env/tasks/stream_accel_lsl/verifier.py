#!/usr/bin/env python3
"""
Verifier for stream_accel_lsl task.

Verifies that:
1. The OpenBCI GUI is running.
2. The Network widget is configured for LSL + Accelerometer.
3. The stream is active.
4. A screenshot was taken by the agent.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_accel_lsl(traj, env_info, task_info):
    """
    Verify LSL Accelerometer streaming configuration using VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
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

    # Basic Checks
    score = 0
    feedback = []
    
    if result.get("app_running"):
        score += 10
        feedback.append("OpenBCI GUI is running (+10)")
    else:
        feedback.append("OpenBCI GUI is NOT running")

    # Screenshot Check
    user_screenshot_valid = result.get("user_screenshot_valid", False)
    user_screenshot_path = result.get("user_screenshot_path", "")
    final_screenshot_path = result.get("final_screenshot_path", "/tmp/task_final.png")
    
    image_to_check = None
    
    if user_screenshot_valid:
        score += 20
        feedback.append("Agent screenshot created successfully (+20)")
        # We prefer to verify the agent's screenshot as it likely focuses on the widget
        # Copy it out for VLM
        try:
            local_user_shot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            copy_from_env(user_screenshot_path, local_user_shot)
            image_to_check = local_user_shot
        except:
            feedback.append("Warning: Could not retrieve agent screenshot, using final state")
    else:
        feedback.append("Agent failed to save screenshot at expected path")

    # Fallback to final screenshot if agent screenshot missing/failed
    if not image_to_check:
        try:
            local_final_shot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
            copy_from_env(final_screenshot_path, local_final_shot)
            image_to_check = local_final_shot
        except:
            return {"passed": False, "score": score, "feedback": "Failed to retrieve any screenshots for verification"}

    # VLM Verification
    # We verify the specific configuration details
    prompt = """
    Analyze this screenshot of the OpenBCI GUI Network Widget.
    I need to verify the streaming configuration.
    
    Please check:
    1. Is the 'Network' widget visible? (Look for a panel titled 'Network' or 'Networking')
    2. Is the Protocol set to 'LSL'? (Look for 'LSL' in a dropdown or label)
    3. Is the Data Type set to 'Accelerometer', 'Accel', or 'Aux'? (It should NOT be 'Raw' or 'TimeSeries')
    4. Is the stream START button active or is there a STOP button? (Indicating it is running)

    Return JSON:
    {
        "network_widget_visible": boolean,
        "protocol_is_lsl": boolean,
        "datatype_is_accel": boolean,
        "stream_is_running": boolean
    }
    """
    
    vlm_response = query_vlm(image=image_to_check, prompt=prompt)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}
        
    data = vlm_response.get("parsed", {})
    
    # Scoring VLM results
    if data.get("network_widget_visible"):
        score += 20
        feedback.append("Network widget found (+20)")
        
        if data.get("protocol_is_lsl"):
            score += 25
            feedback.append("Protocol is LSL (+25)")
        else:
            feedback.append("Protocol is NOT LSL")
            
        if data.get("datatype_is_accel"):
            score += 25
            feedback.append("Data Type is Accelerometer/Aux (+25)")
        else:
            feedback.append("Data Type is NOT Accelerometer")
            
        if data.get("stream_is_running"):
            score += 10
            feedback.append("Stream is running (+10)")
        else:
            feedback.append("Stream is NOT running (Start button visible)")
    else:
        feedback.append("Network widget NOT found in screenshot")

    # Clean up temp images
    if image_to_check and os.path.exists(image_to_check):
        os.unlink(image_to_check)

    # Pass logic: Must have LSL and Accel correct (Critical criteria)
    # Total possible: 10 + 20 + 20 + 25 + 25 + 10 = 110? No, let's check.
    # App running (10) + Screenshot (20) + Widget (20) + LSL (25) + Accel (25) + Running (10) = 110.
    # Cap at 100.
    final_score = min(100, score)
    
    passed = data.get("protocol_is_lsl") and data.get("datatype_is_accel") and final_score >= 80

    return {
        "passed": passed,
        "score": final_score,
        "feedback": "; ".join(feedback)
    }