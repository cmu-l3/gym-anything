#!/usr/bin/env python3
"""
Verifier for Single Phase Power Calculation task.
"""

import json
import tempfile
import os
import re
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_single_phase_power(traj, env_info, task_info):
    """
    Verifies that the agent calculated the correct power values and saved them to a file.
    
    Scoring Criteria:
    1. File Creation (10 pts): File exists.
    2. Data Accuracy (80 pts): Active, Reactive, and Apparent power values are correct (within tolerance).
    3. Workflow Verification (10 pts): VLM confirms app usage (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_p = metadata.get('ground_truth', {}).get('active_kw', 2.735)
    expected_q = metadata.get('ground_truth', {}).get('reactive_kvar', 1.909)
    expected_s = metadata.get('ground_truth', {}).get('apparent_kva', 3.335)
    tolerance = metadata.get('tolerance', 0.05)

    score = 0
    feedback_parts = []
    
    # =========================================================================
    # 1. Retrieve Result Data
    # =========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================================
    # 2. Verify File Existence & Content (90 pts total)
    # =========================================================================
    if result_data.get('file_exists'):
        score += 10
        feedback_parts.append("Output file created.")
        
        content = result_data.get('file_content', '').replace('|', '\n')
        
        # Parse values using regex
        # Look for patterns like "Active Power: 2.735 kW"
        p_match = re.search(r'Active.*?(\d+\.?\d*)', content, re.IGNORECASE)
        q_match = re.search(r'Reactive.*?(\d+\.?\d*)', content, re.IGNORECASE)
        s_match = re.search(r'Apparent.*?(\d+\.?\d*)', content, re.IGNORECASE)
        
        # Check Active Power (30 pts)
        if p_match:
            try:
                val_p = float(p_match.group(1))
                if abs(val_p - expected_p) <= tolerance:
                    score += 30
                    feedback_parts.append(f"Active Power correct ({val_p} kW).")
                else:
                    feedback_parts.append(f"Active Power incorrect (Expected {expected_p}, Got {val_p}).")
            except ValueError:
                feedback_parts.append("Could not parse Active Power value.")
        else:
            feedback_parts.append("Active Power not found in file.")

        # Check Apparent Power (30 pts)
        if s_match:
            try:
                val_s = float(s_match.group(1))
                if abs(val_s - expected_s) <= tolerance:
                    score += 30
                    feedback_parts.append(f"Apparent Power correct ({val_s} kVA).")
                else:
                    feedback_parts.append(f"Apparent Power incorrect (Expected {expected_s}, Got {val_s}).")
            except ValueError:
                feedback_parts.append("Could not parse Apparent Power value.")
        else:
            feedback_parts.append("Apparent Power not found in file.")

        # Check Reactive Power (20 pts)
        if q_match:
            try:
                val_q = float(q_match.group(1))
                if abs(val_q - expected_q) <= tolerance:
                    score += 20
                    feedback_parts.append(f"Reactive Power correct ({val_q} kVAR).")
                else:
                    feedback_parts.append(f"Reactive Power incorrect (Expected {expected_q}, Got {val_q}).")
            except ValueError:
                feedback_parts.append("Could not parse Reactive Power value.")
        else:
            feedback_parts.append("Reactive Power not found in file.")

    else:
        feedback_parts.append("Output file NOT found.")

    # =========================================================================
    # 3. VLM Verification (10 pts)
    # =========================================================================
    # We check if the agent actually used the calculator UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames and query_vlm:
        prompt = """
        Review these screenshots of an agent using an Android app.
        1. Did the agent navigate to a "Power" or "Single Phase" calculator?
        2. Are input fields visible with numbers like 230 (Volts) or 14.5 (Amps)?
        3. Does the final screen show calculated power results (kW, kVA)?
        
        Answer JSON: {"valid_workflow": true/false, "reason": "..."}
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_response.get("success") and vlm_response.get("parsed", {}).get("valid_workflow"):
                score += 10
                feedback_parts.append("VLM verified valid workflow.")
            else:
                feedback_parts.append("VLM could not verify calculator usage.")
        except Exception:
            # Fallback if VLM fails, don't penalize if file is perfect
            if score >= 90:
                score += 10
                feedback_parts.append("VLM skipped, assuming valid due to correct result.")

    # =========================================================================
    # Final Decision
    # =========================================================================
    # Must get at least Active and Apparent power correct to pass (Score >= 70)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }