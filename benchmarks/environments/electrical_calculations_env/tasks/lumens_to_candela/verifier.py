#!/usr/bin/env python3
"""
Verifier for lumens_to_candela task.
Verifies that the agent calculated the correct luminous intensity and saved the evidence.
"""

import json
import logging
import math
import os
import tempfile
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_lumens_to_candela(traj, env_info, task_info):
    """
    Verify the Lumens to Candela calculation task.
    
    Scoring Criteria:
    1. Result file exists and contains correct number (40 pts)
    2. Result file was created during the task (anti-gaming) (10 pts)
    3. Screenshot file exists (10 pts)
    4. VLM Verification of trajectory/final state (40 pts)
       - Confirms correct calculator usage
       - Confirms correct inputs (4500, 36)
       - Confirms result visibility
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_candela', 14634)
    tolerance_pct = metadata.get('tolerance_percent', 5)
    
    # Define paths
    task_dir = "/sdcard/tasks/lumens_to_candela"
    remote_json = f"{task_dir}/task_result.json"
    remote_screenshot = f"{task_dir}/screenshot.png"
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_json, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Text Result (Numeric correctness)
    file_content = result_data.get('file_content', '').strip()
    file_created = result_data.get('file_created_during_task', False)
    
    numeric_passed = False
    if result_data.get('file_exists'):
        try:
            # Clean non-numeric characters (like "cd" or "Candela")
            import re
            cleaned_val = re.sub(r"[^0-9.]", "", file_content)
            val = float(cleaned_val)
            
            # Calculate allowed range
            lower = expected_val * (1 - tolerance_pct/100)
            upper = expected_val * (1 + tolerance_pct/100)
            
            if lower <= val <= upper:
                score += 40
                numeric_passed = True
                feedback_parts.append(f"✅ Correct numeric result: {val}")
            else:
                feedback_parts.append(f"❌ Incorrect numeric result: {val} (Expected {expected_val} ±{tolerance_pct}%)")
        except ValueError:
            feedback_parts.append(f"❌ Could not parse number from file: '{file_content}'")
    else:
        feedback_parts.append("❌ Result file not found")

    # 3. Verify Timestamp (Anti-gaming)
    if numeric_passed:
        if file_created:
            score += 10
            feedback_parts.append("✅ Result file created during task")
        else:
            feedback_parts.append("⚠️ Result file timestamp indicates pre-existing file")

    # 4. Verify Screenshot Existence
    screenshot_exists = result_data.get('screenshot_exists', False)
    if screenshot_exists:
        score += 10
        feedback_parts.append("✅ Screenshot saved")
    else:
        feedback_parts.append("❌ Screenshot not saved")

    # 5. VLM Verification (Trajectory & Content)
    # We analyze trajectory frames to ensure navigation + final state
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    # If agent saved a specific screenshot, we try to fetch it to verify THAT specifically,
    # otherwise fallback to final frame of trajectory.
    target_image = final_frame
    
    # Optional: fetch the screenshot the agent took
    if screenshot_exists:
        try:
            temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(remote_screenshot, temp_ss.name)
            # We could load this image, but gym_anything VLM utils expects PIL images or bytes.
            # For simplicity, we stick to trajectory frames which are guaranteed available.
            # Using trajectory is often more robust for proving WORKFLOW.
            os.unlink(temp_ss.name)
        except Exception:
            pass

    if not target_image:
         feedback_parts.append("⚠️ No visual evidence available")
    else:
        prompt = f"""
        Review this sequence of interactions with the 'Electrical Calculations' app.
        The user task is: Calculate Candelas from 4500 Lumens and 36 degrees beam angle.
        
        Check for:
        1. Navigation to 'Lighting' or 'Lumens - Candela' calculator.
        2. Input '4500' in a Lumens/Flux field.
        3. Input '36' in a Beam Angle field.
        4. A result displayed on screen (should be approx 14634).
        
        Return JSON:
        {{
          "calculator_opened": boolean,
          "inputs_visible": boolean,
          "result_visible": boolean,
          "result_value_approx": number or null
        }}
        """
        
        vlm_out = query_vlm(
            prompt=prompt,
            images=frames + [final_frame]
        )
        
        vlm_data = vlm_out.get('parsed', {})
        
        vlm_score = 0
        if vlm_data.get('calculator_opened'):
            vlm_score += 10
            feedback_parts.append("✅ Calculator opened")
        else:
            feedback_parts.append("❌ Calculator not seen")
            
        if vlm_data.get('inputs_visible'):
            vlm_score += 15
            feedback_parts.append("✅ Inputs (4500, 36) visible")
        else:
            feedback_parts.append("❌ Inputs not visible")
            
        if vlm_data.get('result_visible'):
            vlm_score += 15
            feedback_parts.append("✅ Result visible on screen")
        
        score += vlm_score

    # Final logic
    passed = (score >= 70) and numeric_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }