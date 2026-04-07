#!/usr/bin/env python3
"""
Verifier for add_focus_widget task.
Uses VLM to verify that the Focus Widget was added and is displaying metrics.
"""

import json
import os
import sys
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_focus_widget(traj, env_info, task_info):
    """
    Verifies that the agent added the Focus Widget to the OpenBCI dashboard.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Programmatic Checks (Base Score: 20)
    score = 0
    feedback_parts = []
    
    if result_data.get("app_was_running", False):
        score += 20
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was NOT running at the end.")
        return {"passed": False, "score": 0, "feedback": "Application crashed or closed."}

    # 3. VLM Verification (Score: 80)
    # We analyze the trajectory to ensure the agent actually performed the task
    # and didn't just find a state where it was already there (anti-gaming).
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame:
        return {"passed": False, "score": score, "feedback": "No final screenshot available."}
        
    all_images = frames + [final_frame]
    
    # Prompt designed to verify both process and outcome
    prompt = """
    You are verifying a task in the OpenBCI GUI. 
    The goal is to add the 'Focus Widget' to the dashboard.
    
    Please analyze the image sequence. 
    1. Look for the 'Focus Widget'. It is a circular or radial gauge widget that displays 'Attention' and 'Relaxation' values.
    2. Check if this widget appears in the FINAL frame.
    3. Check if the widget was absent in earlier frames (indicating the agent added it).
    4. Check if the 'Time Series' (waveform graphs) are visible and appear to be streaming (lines not flat).
    
    Provide your assessment in JSON format:
    {
        "focus_widget_visible_in_final": true/false,
        "focus_widget_metrics_active": true/false,
        "data_streaming": true/false,
        "workflow_observed": "describe if you see a dropdown menu being opened or widget selection happening",
        "confidence": 0-10
    }
    """
    
    vlm_response = query_vlm(
        images=all_images,
        prompt=prompt
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}
        
    analysis = vlm_response.get("parsed", {})
    
    # Evaluate VLM response
    focus_visible = analysis.get("focus_widget_visible_in_final", False)
    metrics_active = analysis.get("focus_widget_metrics_active", False)
    streaming = analysis.get("data_streaming", False)
    
    if focus_visible:
        score += 40
        feedback_parts.append("Focus Widget is visible.")
    else:
        feedback_parts.append("Focus Widget NOT found in final screenshot.")
        
    if metrics_active:
        score += 20
        feedback_parts.append("Neurofeedback metrics are active.")
    else:
        feedback_parts.append("Metrics do not appear active (widget may be empty).")

    if streaming:
        score += 20
        feedback_parts.append("Data session is streaming.")
    else:
        feedback_parts.append("Data stream appears stopped.")

    # 4. Final Scoring
    passed = (score >= 80) and focus_visible
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": analysis
    }