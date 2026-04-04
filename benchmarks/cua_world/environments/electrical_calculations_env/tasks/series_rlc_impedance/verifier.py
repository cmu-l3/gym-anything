#!/usr/bin/env python3
"""
Verifier for series_rlc_impedance task.

Requires:
1. Result file existence and valid timestamp.
2. Numeric accuracy of the calculated impedance (Tolerance: +/- 5%).
3. VLM verification of app usage (trajectory analysis).
"""

import json
import os
import tempfile
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_series_rlc_impedance(traj, env_info, task_info):
    """
    Verifies the Series RLC Impedance calculation task.
    """
    # 1. Setup and connection check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth_ohms', 124.38)
    tolerance_pct = metadata.get('tolerance_percent', 5.0)
    
    score = 0
    feedback_parts = []
    
    # 2. Retrieve Result JSON from Environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/tasks/series_rlc_impedance/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Criterion: File Existence & Anti-Gaming (25 pts)
    file_exists = result_data.get('file_exists', False)
    is_new_file = result_data.get('is_new_file', False)
    
    if file_exists and is_new_file:
        score += 25
        feedback_parts.append("Result file created successfully.")
    elif file_exists:
        score += 10
        feedback_parts.append("Result file exists but timestamp check failed (stale file?).")
    else:
        feedback_parts.append("Result file not found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback_parts)}

    # 4. Criterion: Value Accuracy (45 pts)
    content = result_data.get('file_content', "").strip()
    try:
        # Extract first float found in text
        match = re.search(r"[-+]?\d*\.\d+|\d+", content)
        if match:
            user_val = float(match.group())
            
            error = abs(user_val - ground_truth)
            pct_error = (error / ground_truth) * 100
            
            if pct_error <= 2.0:
                score += 45
                feedback_parts.append(f"Value {user_val} is highly accurate (Error: {pct_error:.2f}%).")
            elif pct_error <= tolerance_pct:
                score += 30
                feedback_parts.append(f"Value {user_val} is within tolerance (Error: {pct_error:.2f}%).")
            else:
                feedback_parts.append(f"Value {user_val} is incorrect (Expected ~{ground_truth}, Error: {pct_error:.2f}%).")
        else:
            feedback_parts.append(f"Could not parse a number from file content: '{content}'.")
    except Exception as e:
        feedback_parts.append(f"Error parsing value: {str(e)}")

    # 5. Criterion: VLM Trajectory Verification (30 pts)
    # Did they actually open the app and use the calculator?
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("No trajectory frames available for visual verification.")
    else:
        prompt = """
        You are verifying an Android task. The user should:
        1. Open 'Electrical Engineering Calculations' app.
        2. Navigate to 'Impedance' or 'RLC' calculator.
        3. Enter values (R=120, L=300mH, C=33uF).
        
        Look at these screenshots.
        - Do you see the Electrical Calculations app interface?
        - Do you see an impedance or RLC calculation screen?
        - Do you see input fields for Resistance, Inductance, or Capacitance?
        
        Answer JSON: {"app_seen": bool, "calculator_seen": bool, "confidence": float}
        """
        
        try:
            vlm_resp = query_vlm(frames, prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            if vlm_data.get('app_seen', False):
                score += 10
                feedback_parts.append("App usage verified.")
                
            if vlm_data.get('calculator_seen', False):
                score += 20
                feedback_parts.append("Calculator navigation verified.")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if value is correct, give benefit of doubt for visualization
            if score >= 60:
                score += 15
                feedback_parts.append("Visual verification skipped, trusting correct output.")

    # 6. Final Scoring
    passed = score >= 60 and file_exists and is_new_file
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }