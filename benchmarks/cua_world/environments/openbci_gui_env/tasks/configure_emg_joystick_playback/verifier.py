#!/usr/bin/env python3
"""
Verifier for configure_emg_joystick_playback task.

Criteria:
1. Agent-generated screenshot exists and was created during task.
2. VLM analysis of screenshot confirms:
   - EMG Joystick widget is visible.
   - Channel mappings are correct (Right=3, Left=4, Up=1, Down=2).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_emg_joystick(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check file existence and timestamp (20 points)
    if result_data.get("agent_screenshot_exists") and result_data.get("agent_screenshot_valid"):
        score += 20
        feedback.append("Screenshot file created successfully.")
    else:
        feedback.append("Screenshot file missing or created before task started.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 2. Retrieve the screenshot for VLM analysis
    # We prefer the agent's screenshot as it represents their claim of completion
    agent_screenshot_path = result_data.get("agent_screenshot_path")
    local_screenshot_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    
    try:
        copy_from_env(agent_screenshot_path, local_screenshot_path)
    except Exception:
        feedback.append("Could not retrieve screenshot from container.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. VLM Verification (80 points)
    # prompt specifically checks for the widget and the mappings
    prompt = """
    Analyze this OpenBCI GUI screenshot.
    1. Is the "EMG Joystick" widget visible? (Look for a circular joystick control or the text "EMG Joystick").
    2. Check the channel number dropdowns/indicators for the directions:
       - Right (or +X): Is it set to Channel 3?
       - Left (or -X): Is it set to Channel 4?
       - Up (or +Y): Is it set to Channel 1?
       - Down (or -Y): Is it set to Channel 2?
    
    Return JSON:
    {
      "widget_visible": true/false,
      "mappings": {
        "right_is_3": true/false,
        "left_is_4": true/false,
        "up_is_1": true/false,
        "down_is_2": true/false
      }
    }
    """
    
    try:
        vlm_response = query_vlm(
            prompt=prompt,
            image=local_screenshot_path
        )
        
        parsed = vlm_response.get("parsed", {})
        
        # Scoring based on VLM
        if parsed.get("widget_visible"):
            score += 30
            feedback.append("EMG Joystick widget found.")
        else:
            feedback.append("EMG Joystick widget NOT found.")
            
        mappings = parsed.get("mappings", {})
        correct_mappings = 0
        if mappings.get("right_is_3"): correct_mappings += 1
        if mappings.get("left_is_4"): correct_mappings += 1
        if mappings.get("up_is_1"): correct_mappings += 1
        if mappings.get("down_is_2"): correct_mappings += 1
        
        # 12.5 points per correct mapping (total 50)
        mapping_score = correct_mappings * 12.5
        score += mapping_score
        feedback.append(f"Correct mappings found: {correct_mappings}/4.")

    except Exception as e:
        feedback.append(f"VLM analysis failed: {str(e)}")
        # Fallback scoring if VLM fails entirely is dangerous, better to fail secure or manual review
    finally:
        if os.path.exists(local_screenshot_path):
            os.unlink(local_screenshot_path)

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }