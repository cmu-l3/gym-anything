#!/usr/bin/env python3
"""
Verifier for Cable Reel Capacity Task.

Checks:
1. Result file existence and correct numeric range (300-600m).
2. Evidence screenshot existence.
3. VLM verification of the calculator state (inputs and result).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cable_reel_capacity(traj, env_info, task_info):
    """
    Verifies the cable reel capacity calculation task.
    """
    # 1. Setup and Resources
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_meters = metadata.get('min_expected_meters', 300)
    max_meters = metadata.get('max_expected_meters', 600)
    
    score = 0
    feedback_parts = []
    
    # 2. Retrieve JSON Result from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Criterion: Output File Existence and Content (40 points)
    output_exists = result_data.get('output_exists', False)
    raw_content = result_data.get('output_content', "").strip()
    
    val_meters = None
    if output_exists and raw_content:
        # Try to parse number
        try:
            # Remove potential text like " meters" or "m"
            clean_content = ''.join(c for c in raw_content if c.isdigit() or c == '.')
            val_meters = float(clean_content)
            
            if min_meters <= val_meters <= max_meters:
                score += 40
                feedback_parts.append(f"Correct calculated value: {val_meters}m")
            else:
                score += 10 # Partial credit for format
                feedback_parts.append(f"Value out of range: {val_meters}m (Expected {min_meters}-{max_meters}m)")
        except ValueError:
            feedback_parts.append(f"Could not parse numeric value from file: '{raw_content}'")
    else:
        feedback_parts.append("Result file not found or empty")

    # 4. Criterion: Evidence Screenshot (20 points)
    screenshot_exists = result_data.get('screenshot_exists', False)
    if screenshot_exists:
        score += 20
        feedback_parts.append("Evidence screenshot saved")
    else:
        feedback_parts.append("Evidence screenshot missing")

    # 5. Criterion: VLM Verification of Workflow (40 points)
    # We check if they actually used the calculator
    frames = sample_trajectory_frames(traj, n=3)
    final_screen = get_final_screenshot(traj)
    
    # Combine frames to check trajectory
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if images_to_check:
        vlm_prompt = """
        Review these screenshots of an Android app. 
        The user is supposed to be using a 'Cable Reel Capacity' or 'Drum Capacity' calculator.
        
        Look for:
        1. A screen titled 'Cable Reel', 'Drum Capacity', or similar.
        2. Inputs fields showing roughly:
           - Flange/Diameter: 800
           - Barrel/Core: 400
           - Width: 500
           - Cable: 16
        3. A calculated result around 350-550 meters.
        
        Answer JSON:
        {
            "calculator_visible": true/false,
            "inputs_visible": true/false,
            "result_visible": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=images_to_check)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('calculator_visible'):
                score += 10
                feedback_parts.append("VLM: Calculator found")
            
            if parsed.get('inputs_visible'):
                score += 15
                feedback_parts.append("VLM: Inputs verified")
                
            if parsed.get('result_visible'):
                score += 15
                feedback_parts.append("VLM: Result verified")
                
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM verification unavailable")
            # Fallback: if value was correct, grant VLM points to avoid penalizing for VLM error
            if val_meters and min_meters <= val_meters <= max_meters:
                score += 40
                feedback_parts.append("VLM points granted based on correct file output")

    # 6. Anti-Gaming Check
    if not result_data.get('file_created_during_task', False) and output_exists:
        score = 0
        feedback_parts.append("FAIL: Result file timestamp indicates it was not created during this task")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }