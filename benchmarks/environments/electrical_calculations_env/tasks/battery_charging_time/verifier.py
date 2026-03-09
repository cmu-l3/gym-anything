#!/usr/bin/env python3
"""
Verifier for battery_charging_time task.

Checklist:
1. Result file exists and contains a number in valid range (7.5 - 11.5 hours).
2. Result file was created/modified during the task window.
3. Screenshot exists.
4. VLM verifies screenshot shows correct inputs (200 Ah, 25 A) and context.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_battery_charging_time(traj, env_info, task_info):
    """
    Verify the battery charging time calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_hours = metadata.get('min_expected_hours', 7.5)
    max_hours = metadata.get('max_expected_hours', 11.5)

    score = 0
    feedback_parts = []
    
    # Temporary files for extraction
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # 1. Retrieve JSON Report
        try:
            copy_from_env("/sdcard/tasks/battery_charging_time/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve task result data: {str(e)}"
            }

        task_start = result_data.get('task_start', 0)
        
        # 2. Check Result File Content (Numerical Verification)
        file_exists = result_data.get('result_file_exists', False)
        result_content = result_data.get('result_content', "").strip()
        file_mtime = result_data.get('result_file_mtime', 0)
        
        valid_number = False
        parsed_value = 0.0
        
        if file_exists:
            score += 10
            feedback_parts.append("Result file created.")
            
            # Anti-gaming: Check timestamp
            if file_mtime >= task_start:
                score += 10
                feedback_parts.append("File created during task.")
            else:
                feedback_parts.append("File timestamp predates task (stale data).")

            # Parse content
            try:
                # Remove potential text like "hours" or "h"
                cleaned_content = "".join(c for c in result_content if c.isdigit() or c == '.')
                parsed_value = float(cleaned_content)
                
                if min_hours <= parsed_value <= max_hours:
                    score += 30
                    valid_number = True
                    feedback_parts.append(f"Value {parsed_value}h is within expected range ({min_hours}-{max_hours}h).")
                else:
                    feedback_parts.append(f"Value {parsed_value}h is outside expected range ({min_hours}-{max_hours}h).")
            except ValueError:
                feedback_parts.append(f"Could not parse numerical value from: '{result_content}'")
        else:
            feedback_parts.append("Result file not found.")

        # 3. VLM Verification of Screenshot
        screenshot_path_remote = result_data.get('screenshot_path', "")
        screenshot_exists = result_data.get('screenshot_exists', "false")
        
        if screenshot_exists != "false" and screenshot_path_remote:
            try:
                copy_from_env(screenshot_path_remote, temp_screenshot.name)
                
                # Use query_vlm helper
                prompt = (
                    "Analyze this screenshot of an electrical calculation app.\n"
                    "1. Is the 'Battery Charging' or 'Charging Time' calculator visible? (NOT Battery Life/Run Time)\n"
                    "2. Is the Capacity input approximately 200 (Ah)?\n"
                    "3. Is the Current input approximately 25 (A)?\n"
                    "4. Is there a calculated time result shown (likely around 9-10 hours)?\n"
                    "Return JSON: {\"correct_tool\": bool, \"capacity_200\": bool, \"current_25\": bool, \"result_visible\": bool}"
                )
                
                vlm_response = query_vlm(
                    image=temp_screenshot.name,
                    prompt=prompt
                )
                
                if vlm_response.get('success'):
                    parsed = vlm_response.get('parsed', {})
                    
                    if parsed.get('correct_tool', False):
                        score += 20
                        feedback_parts.append("VLM confirmed correct calculator tool.")
                    else:
                        feedback_parts.append("VLM did not identify correct 'Charging Time' calculator.")
                        
                    if parsed.get('capacity_200', False):
                        score += 10
                        feedback_parts.append("VLM confirmed Capacity input (200).")
                    else:
                        feedback_parts.append("VLM did not see Capacity 200.")
                        
                    if parsed.get('current_25', False):
                        score += 10
                        feedback_parts.append("VLM confirmed Current input (25).")
                    else:
                        feedback_parts.append("VLM did not see Current 25.")
                        
                    if parsed.get('result_visible', False):
                        score += 10
                        feedback_parts.append("VLM confirmed result is visible.")
                else:
                    feedback_parts.append("VLM analysis failed.")
                    
            except Exception as e:
                feedback_parts.append(f"Error processing screenshot: {str(e)}")
        else:
            feedback_parts.append("No screenshot available for verification.")

    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }