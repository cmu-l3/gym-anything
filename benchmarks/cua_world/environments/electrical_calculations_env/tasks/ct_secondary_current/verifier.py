#!/usr/bin/env python3
"""
Verifier for ct_secondary_current task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ct_secondary_current(traj, env_info, task_info):
    """
    Verifies that the agent calculated the CT secondary current correctly.
    
    Criteria:
    1. File /sdcard/ct_check.txt exists and was created during task.
    2. File content matches expected value (3.5).
    3. VLM confirms the agent used the CT calculator (not just guessed).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_result', 3.5)
    tolerance = metadata.get('tolerance', 0.1)

    # 1. Retrieve Result JSON from Android device
    local_json_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/sdcard/task_result.json", local_json_path)
        with open(local_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {str(e)}"
        }
    finally:
        if os.path.exists(local_json_path):
            os.remove(local_json_path)

    score = 0
    feedback_parts = []

    # 2. Verify File Existence & Anti-Gaming (20 pts)
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Result file created successfully.")
    else:
        feedback_parts.append("Result file not found or not created during task.")

    # 3. Verify Numerical Value (40 pts)
    content = result_data.get("file_content", "").strip()
    match = re.search(r"secondary_current\s*=\s*([0-9.]+)", content)
    
    value_correct = False
    if match:
        try:
            val = float(match.group(1))
            if abs(val - expected_val) <= tolerance:
                score += 40
                value_correct = True
                feedback_parts.append(f"Correct value calculated: {val}")
            else:
                feedback_parts.append(f"Incorrect value: {val} (Expected {expected_val})")
        except ValueError:
            feedback_parts.append("Could not parse number from file.")
    else:
        feedback_parts.append(f"File format incorrect. Content: '{content}'")

    # 4. VLM Verification (40 pts)
    # Check if the agent actually used the CT calculator UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt focusing on the specific UI elements of a CT calculator
    prompt = """
    Analyze these screenshots from an Android electrical app.
    I am looking for evidence that the user performed a Current Transformer (CT) calculation.
    
    Look for:
    1. A screen titled "CT / PT" or "Current Transformer" or "Transformation Ratio".
    2. Input fields where numbers like '400' (Primary) or '5' (Secondary) or '280' (Measured) are visible.
    3. A result showing '3.5' or similar.
    
    Did the user navigate to a transformer calculator and enter these values?
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=prompt
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        # We trust the VLM's judgment on boolean keys if we ask for JSON, 
        # but here we'll use the generic success/reasoning pattern or assume 
        # the framework parses a simple Yes/No or positive sentiment.
        # For robustness, let's look at the text or assume the VLM wrapper provides a score/bool.
        # Assuming query_vlm returns a dict with 'parsed' if we requested JSON, 
        # or we inspect 'response'.
        
        # Let's assume a manual parsing of response text for positive keywords if 'parsed' isn't there
        response_text = vlm_result.get("response", "").lower()
        if "yes" in response_text or "confirmed" in response_text or "evidence" in response_text:
            vlm_score = 40
            feedback_parts.append("VLM confirmed correct calculator usage.")
        else:
            # Partial credit if inputs are seen but maybe not result
            if "400" in response_text or "280" in response_text:
                vlm_score = 20
                feedback_parts.append("VLM saw inputs but wasn't fully sure of workflow.")
            else:
                feedback_parts.append("VLM did not see evidence of CT calculator usage.")
    else:
        feedback_parts.append("VLM analysis failed.")
    
    score += vlm_score

    # Final Pass/Fail
    passed = (score >= 60) and value_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }