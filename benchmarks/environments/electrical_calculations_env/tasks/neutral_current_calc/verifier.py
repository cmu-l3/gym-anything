#!/usr/bin/env python3
"""
Verifier for neutral_current_calc task.

Verification Logic:
1. File Verification (Programmatic):
   - Checks if result text file exists and was created during task.
   - Parses the value and checks if it matches ~25.98 A (within tolerance).
2. Evidence Verification (VLM):
   - Checks trajectory/final screenshot to confirm the "Neutral Current" calculator was used.
   - Verifies inputs (145, 130, 160) are visible on screen.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_neutral_current(traj, env_info, task_info):
    """
    Verify neutral current calculation task.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_value', 25.98)
    tolerance = metadata.get('tolerance', 0.5)
    
    # Load result JSON from device
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (60 points)
    
    # Check if file was created (10 pts)
    if result_data.get('text_exists') and result_data.get('file_created_during_task'):
        score += 10
        feedback_parts.append("Result file created successfully.")
    else:
        feedback_parts.append("Result file missing or pre-existing.")

    # Check value accuracy (40 pts)
    raw_value = result_data.get('text_value', '').strip()
    # Extract number from string (handles cases like "25.98 A" or "25.98")
    match = re.search(r"([0-9]+\.?[0-9]*)", raw_value)
    
    value_correct = False
    if match:
        try:
            val = float(match.group(1))
            if abs(val - expected_val) <= tolerance:
                score += 40
                value_correct = True
                feedback_parts.append(f"Calculated value {val} is correct (Target: {expected_val}).")
            else:
                feedback_parts.append(f"Calculated value {val} is incorrect (Target: {expected_val}).")
        except ValueError:
            feedback_parts.append(f"Could not parse number from: {raw_value}")
    else:
        feedback_parts.append("No valid number found in result file.")

    # Check user screenshot existence (10 pts)
    if result_data.get('screenshot_exists'):
        score += 10
        feedback_parts.append("User saved screenshot as requested.")
    else:
        feedback_parts.append("User failed to save screenshot.")

    # 3. VLM Verification (40 points)
    # We use trajectory frames to ensure the agent actually used the app interface
    
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen and not frames:
        feedback_parts.append("No visual evidence available for VLM.")
    else:
        # Construct prompt
        images = frames + [final_screen] if final_screen else frames
        prompt = """
        Review these screenshots from an Android electrical calculation app.
        1. Is the 'Neutral Current' calculator visible? (Look for title 'Neutral Current' or similar)
        2. Are the input values 145, 130, and 160 entered into the fields?
        3. Is the result approximately 25.98 displayed?
        
        Return JSON: {"calculator_visible": bool, "inputs_correct": bool, "result_visible": bool}
        """
        
        vlm_resp = query_vlm(prompt=prompt, images=images)
        
        if vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            
            if analysis.get('calculator_visible'):
                score += 10
                feedback_parts.append("VLM confirmed correct calculator usage.")
            else:
                feedback_parts.append("VLM could not confirm 'Neutral Current' calculator usage.")
                
            if analysis.get('inputs_correct'):
                score += 20
                feedback_parts.append("VLM confirmed correct inputs (145, 130, 160).")
            elif value_correct:
                # If value is correct but VLM missed inputs (maybe scrolled away), give partial credit
                score += 10 
                feedback_parts.append("VLM missed inputs, but final value was correct.")
                
            if analysis.get('result_visible'):
                score += 10
                feedback_parts.append("VLM confirmed result visibility.")
        else:
            feedback_parts.append("VLM analysis failed.")

    # 4. Final Verdict
    # Pass if value is correct AND file was created AND (score >= 80)
    passed = value_correct and result_data.get('file_created_during_task') and score >= 80
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }