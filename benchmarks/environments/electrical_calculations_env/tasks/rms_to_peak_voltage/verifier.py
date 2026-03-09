#!/usr/bin/env python3
"""
Verifier for rms_to_peak_voltage task.
"""

import json
import tempfile
import os
import logging
import math
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rms_to_peak_voltage(traj, env_info, task_info):
    """
    Verify the RMS to Peak voltage calculation task.
    
    Criteria:
    1. Text file '/sdcard/tasks/peak_voltage.txt' exists and contains ~169.7.
    2. Screenshot '/sdcard/tasks/rms_to_peak_result.png' exists.
    3. VLM verifies the screenshot shows the correct calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_peak = metadata.get('expected_peak', 169.7)
    tolerance = metadata.get('tolerance', 1.5)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Paths in container/device
    result_json_path = "/sdcard/tasks/task_result.json"
    screenshot_path = "/sdcard/tasks/rms_to_peak_result.png"
    
    # Temp files for local analysis
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # 1. Load Result JSON
        try:
            copy_from_env(result_json_path, temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check Text File Content (40 points)
        txt_content = result_data.get('txt_content', '').strip()
        txt_exists = result_data.get('txt_exists', False)
        
        val_correct = False
        if txt_exists and txt_content:
            try:
                # Remove non-numeric chars except dot
                cleaned_val = ''.join(c for c in txt_content if c.isdigit() or c == '.')
                val = float(cleaned_val)
                if math.isclose(val, expected_peak, abs_tol=tolerance):
                    score += 40
                    val_correct = True
                    feedback_parts.append(f"Correct value recorded: {val}")
                else:
                    feedback_parts.append(f"Value recorded ({val}) is outside tolerance of {expected_peak}")
            except ValueError:
                feedback_parts.append(f"Could not parse number from text file: '{txt_content}'")
        else:
            feedback_parts.append("Result text file not found or empty")

        # 3. Check Screenshot Existence (20 points)
        png_exists = result_data.get('png_exists', False)
        if png_exists:
            score += 20
            feedback_parts.append("Screenshot file exists")
            # Retrieve the screenshot for VLM
            try:
                copy_from_env(screenshot_path, temp_png.name)
                screenshot_available = True
            except:
                screenshot_available = False
                feedback_parts.append("Failed to download screenshot for verification")
        else:
            feedback_parts.append("Screenshot file missing")
            screenshot_available = False

        # 4. VLM Verification (40 points)
        # We verify the specific screenshot saved by the agent, OR the final frame if that fails
        image_to_check = None
        if screenshot_available and os.path.getsize(temp_png.name) > 0:
            image_to_check = temp_png.name
        else:
            # Fallback to final trajectory frame
            image_to_check = get_final_screenshot(traj)
            feedback_parts.append("Using final frame for visual verification")

        if image_to_check:
            prompt = f"""
            Analyze this screenshot from an electrical calculation app.
            1. Is the app showing a "Peak / RMS" or "Value Conversion" calculator?
            2. Is the input value (RMS) approximately 120?
            3. Is the result value (Peak) approximately 169.7?
            
            Return JSON: {{ "is_conversion_screen": bool, "input_120_visible": bool, "result_169_visible": bool }}
            """
            
            vlm_res = query_vlm(image=image_to_check, prompt=prompt)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('is_conversion_screen'):
                    score += 10
                if parsed.get('input_120_visible'):
                    score += 10
                if parsed.get('result_169_visible'):
                    score += 20
                    feedback_parts.append("Visual verification passed")
                else:
                    feedback_parts.append("Visual verification: Result 169.7 not clearly visible")
            else:
                feedback_parts.append("VLM analysis failed")
        
        # Pass Condition
        passed = (score >= 80)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_png.name):
            os.unlink(temp_png.name)