#!/usr/bin/env python3
"""
Verifier for motor_efficiency_analysis task.

Criteria:
1. Output file exists and was created during the task.
2. Output file contains the correct efficiency value (~87.7%).
3. VLM Trajectory Verification: Agent actually used the app's calculator.
"""

import json
import re
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_motor_efficiency(traj, env_info, task_info):
    """
    Verifies the motor efficiency calculation task.
    """
    # 1. Setup and copy files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Copy result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Extract Metadata & Results
    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_efficiency_percent', 87.73)
    tolerance = metadata.get('tolerance_percent', 1.5)
    
    file_exists = result_data.get('file_exists', False)
    created_during_task = result_data.get('file_created_during_task', False)
    content = result_data.get('file_content', "")
    
    score = 0
    feedback = []

    # 3. Verify File Existence & Anti-Gaming (30 points)
    if file_exists:
        if created_during_task:
            score += 30
            feedback.append("Report file created successfully.")
        else:
            feedback.append("Report file exists but has old timestamp (pre-task).")
    else:
        feedback.append("Report file not found.")

    # 4. Verify Calculation Value (50 points)
    value_correct = False
    if file_exists and content:
        # Regex to find a percentage value like "87.7%" or "87.7"
        match = re.search(r"(\d+(\.\d+)?)", content)
        if match:
            try:
                agent_val = float(match.group(1))
                diff = abs(agent_val - expected_val)
                if diff <= tolerance:
                    score += 50
                    value_correct = True
                    feedback.append(f"Calculated efficiency {agent_val}% is correct (within tolerance).")
                else:
                    feedback.append(f"Calculated efficiency {agent_val}% is incorrect. Expected ~{expected_val}%.")
            except ValueError:
                feedback.append("Could not parse number from file content.")
        else:
            feedback.append("No numeric value found in file.")

    # 5. VLM Trajectory Verification (20 points)
    # Ensure they didn't just python-calc it, but used the app UI.
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback.append("No trajectory frames available for VLM verification.")
    else:
        prompt = """
        Review these screenshots of an Android agent's actions.
        The goal is to calculate Motor Efficiency using the 'Electrical Engineering Calculations' app.
        
        Look for:
        1. The 'Electrical Engineering Calculations' app interface.
        2. A calculator screen titled 'Efficiency' or 'Motor'.
        3. Input fields showing values like '10' (HP) or '7457' (Watts) and '8.5' (kW) or '8500'.
        4. A result displayed on screen around 87-88%.
        
        Answer with JSON:
        {
            "app_used": true/false,
            "calculator_visible": true/false,
            "inputs_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('app_used') and parsed.get('calculator_visible'):
                    score += 20
                    feedback.append("VLM verified app usage.")
                else:
                    feedback.append("VLM could not confirm correct app usage.")
            else:
                # If VLM fails, grant points if value was correct to avoid false negative
                if value_correct:
                    score += 20
                    feedback.append("VLM unavailable, defaulting to pass based on correct value.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            if value_correct:
                score += 20

    # 6. Final Decision
    passed = (score >= 90) # Requires file, correct value, and some evidence of work
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }