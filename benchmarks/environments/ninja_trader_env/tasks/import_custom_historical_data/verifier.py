#!/usr/bin/env python3
"""
Verifier for import_custom_historical_data task.

Verification Strategy:
1. File Analysis: Checks if workspace XML contains the custom instrument 'SYNTH101' and a Chart definition.
2. VLM Verification: Uses trajectory frames to verify the agent actually opened a chart with visible data bars.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_custom_historical_data(traj, env_info, task_info):
    """
    Verifies that the agent imported custom data and displayed it on a chart.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Workspace Check (50 pts) ---
    if result.get("workspace_modified", False):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace not saved")

    if result.get("instrument_in_workspace", False):
        score += 20
        feedback_parts.append("Instrument 'SYNTH101' found in workspace (+20)")
    else:
        feedback_parts.append("Instrument 'SYNTH101' NOT found")

    if result.get("chart_created", False):
        score += 20
        feedback_parts.append("Chart window detected (+20)")
    else:
        feedback_parts.append("No Chart window detected")

    # --- Criterion 2: VLM Visual Verification (50 pts) ---
    # We check if the chart actually displays data (bars/candles) rather than being blank.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
    
    vlm_prompt = """
    You are verifying a trading software task. 
    The user was supposed to import data for a custom instrument 'SYNTH101' and open a daily chart.
    
    Look at the sequence of images and the final screen.
    1. Is there a chart visible with the title containing 'SYNTH101'?
    2. Does the chart show price bars, candles, or a line graph (visual data)? 
       (Contrast this with an empty grid or blank chart area).
    3. Is there any error message indicating 'No Data'?
    
    Respond in JSON:
    {
        "chart_title_visible": boolean,
        "data_visible": boolean,
        "error_message": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("chart_title_visible"):
            vlm_score += 20
            feedback_parts.append("VLM: SYNTH101 Chart title visible (+20)")
        else:
            feedback_parts.append("VLM: Chart title not clear")
            
        if parsed.get("data_visible"):
            vlm_score += 30
            feedback_parts.append("VLM: Data bars visible on chart (+30)")
        else:
            feedback_parts.append("VLM: Chart appears empty (no data imported?)")
            
        if parsed.get("error_message"):
            vlm_score = 0
            feedback_parts.append("VLM: Error message detected (-All VLM points)")
    else:
        feedback_parts.append("VLM verification failed to run")
    
    score += vlm_score

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }