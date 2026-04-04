#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_motor_slip_calc(traj, env_info, task_info):
    """
    Verifies the Motor Slip Calculation task.
    
    Criteria:
    1. Result file exists and was created during the task.
    2. Result file contains correct key-value pairs (Sync RPM: 1800, Measured: 1725).
    3. Calculated slip percentage is correct (~4.17%).
    4. VLM verifies the agent navigated to the correct calculator and inputs are visible.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_slip_min = metadata.get('expected_slip_min', 4.10)
    expected_slip_max = metadata.get('expected_slip_max', 4.25)

    score = 0
    max_score = 100
    feedback = []

    # Copy result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence & Anti-Gaming (20 pts)
    if result_data.get("file_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback.append("Result file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Result file not found or not created during task."}

    # 3. Verify File Content & Calculation (40 pts)
    content = result_data.get("file_content_raw", "")
    
    # Parse the content
    # Expected format:
    # Synchronous_RPM: 1800
    # Measured_RPM: 1725
    # Slip_Percentage: 4.166
    
    sync_rpm_match = re.search(r"Synchronous_RPM:\s*(\d+)", content)
    meas_rpm_match = re.search(r"Measured_RPM:\s*(\d+)", content)
    slip_match = re.search(r"Slip_Percentage:\s*([0-9.]+)", content)

    data_correct = True
    
    if sync_rpm_match and int(sync_rpm_match.group(1)) == 1800:
        score += 10
    else:
        feedback.append("Incorrect or missing Synchronous RPM in file.")
        data_correct = False

    if meas_rpm_match and int(meas_rpm_match.group(1)) == 1725:
        score += 10
    else:
        feedback.append("Incorrect or missing Measured RPM in file.")
        data_correct = False

    if slip_match:
        try:
            val = float(slip_match.group(1))
            if expected_slip_min <= val <= expected_slip_max:
                score += 20
                feedback.append(f"Slip calculation correct ({val}%).")
            else:
                feedback.append(f"Slip value out of range (Got {val}%, expected ~4.17%).")
                data_correct = False
        except ValueError:
            feedback.append("Could not parse slip value as number.")
            data_correct = False
    else:
        feedback.append("Slip Percentage not found in file.")
        data_correct = False

    # 4. VLM Verification (40 pts)
    # Check trajectory to ensure they actually used the app
    
    # Select frames: start, middle, end
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # Add final screenshot to analysis set
    if final_screenshot:
        frames.append(final_screenshot)

    if not frames:
        feedback.append("No visual evidence available.")
        # We can't award VLM points, but if calculation is perfect, they might pass
    else:
        vlm_prompt = """
        You are verifying an Android navigation task. 
        The user should have:
        1. Opened 'Electrical Calculations' app.
        2. Navigated to 'Motors' -> 'Motor Slip'.
        3. Entered 1800 (or 60Hz/4Pole) and 1725.
        4. Calculated a result around 4.16%.
        
        Look at the sequence of images.
        - Do you see the 'Motor Slip' calculator screen?
        - Do you see input values like 1800 or 1725?
        - Do you see a result around 4.17?
        
        Return JSON: {"app_used": boolean, "inputs_visible": boolean, "result_visible": boolean}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('app_used'):
                score += 10
            else:
                feedback.append("VLM: App usage not clearly detected.")

            if parsed.get('inputs_visible'):
                score += 15
            else:
                feedback.append("VLM: Inputs (1800/1725) not clearly visible.")

            if parsed.get('result_visible'):
                score += 15
            else:
                feedback.append("VLM: Result calculation screen not clearly visible.")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback.append("Visual verification process failed (non-fatal).")
            # If data is correct, we give benefit of doubt for VLM failure? 
            # Better to rely on data correctness if VLM fails.
            if data_correct:
                score += 40
                feedback.append("Awarding visual points based on correct data output (VLM fallback).")

    # Final scoring
    passed = (score >= 70) and data_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }