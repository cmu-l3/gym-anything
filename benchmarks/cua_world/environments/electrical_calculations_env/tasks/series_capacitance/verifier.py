#!/usr/bin/env python3
"""
Verifier for series_capacitance task.

Strategy:
1. Verify app was focused at the end (basic check).
2. Use VLM to analyze the trajectory and final screenshot to confirm:
   - Navigation to "Series" capacitor calculator.
   - Entry of correct values (100, 220, 470).
   - Display of correct result (~59.98).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_series_capacitance(traj, env_info, task_info):
    """
    Verifies that the agent calculated series capacitance correctly.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    # Load result JSON from the Android environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Basic heuristic checks
    score = 0
    feedback_parts = []
    
    # Check 1: App Focused (15 pts)
    if result_data.get("app_focused", False):
        score += 15
        feedback_parts.append("App was open and focused.")
    else:
        feedback_parts.append("App was NOT focused at the end.")

    # Check 2: Timestamp validity (Anti-gaming)
    task_start = result_data.get("task_start", 0)
    task_end = result_data.get("task_end", 0)
    if task_end > task_start and task_start > 0:
        # Pass (this is a prerequisite, no points directly, but failure is fatal)
        pass
    else:
        return {"passed": False, "score": 0, "feedback": "Invalid task timestamps (anti-gaming check failed)."}

    # 3. VLM Verification (85 pts total)
    # We sample frames to see navigation, and check final frame for result.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
         return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Construct VLM Prompt
    # We ask for specific visual evidence corresponding to the task steps.
    prompt = """
    You are verifying an electrical calculation task on an Android app.
    The user must calculate Series Capacitance for three values: 100, 220, and 470.
    The expected result is approximately 59.98.

    Analyze the screenshots and answer the following in JSON format:

    1. "is_series_calculator": (boolean) Does the screen title or header indicate "Series" (and not "Parallel")?
    2. "inputs_visible": (boolean) Can you see the numbers 100, 220, and 470 entered in input fields?
    3. "result_visible": (boolean) Is a result around 59.9 or 60 visible?
    4. "result_value": (number/null) What is the exact number displayed as the result?
    5. "parallel_mistake": (boolean) Does the result look like 790 (which would be the Parallel sum)?
    """

    try:
        vlm_response = query_vlm(images=frames + [final_screen], prompt=prompt)
        analysis = vlm_response.get("parsed", {})
        
        # Scoring based on VLM analysis
        
        # Check A: Correct Calculator (15 pts)
        if analysis.get("is_series_calculator", False):
            score += 15
            feedback_parts.append("Correctly navigated to Series Calculator.")
        elif analysis.get("parallel_mistake", False):
            feedback_parts.append("Mistake: Used Parallel calculator instead of Series.")
        else:
            feedback_parts.append("Could not verify correct calculator type.")

        # Check B: Inputs Entered (25 pts)
        if analysis.get("inputs_visible", False):
            score += 25
            feedback_parts.append("All input values (100, 220, 470) are visible.")
        else:
            feedback_parts.append("Input values were not clearly visible.")

        # Check C: Result Correct (45 pts)
        # We allow a small visual tolerance or VLM reading error
        detected_value = analysis.get("result_value")
        result_visible = analysis.get("result_visible", False)
        
        valid_result = False
        if detected_value is not None:
            try:
                val = float(detected_value)
                if 58.0 <= val <= 62.0:
                    valid_result = True
            except ValueError:
                pass
        
        # Fallback if VLM says result is visible and correct but fails to parse number
        if result_visible and not valid_result and detected_value is None:
             # If VLM is confident it saw ~59.98 but returned null for exact value
             valid_result = True

        if valid_result:
            score += 45
            feedback_parts.append("Correct result (~59.98) is displayed.")
        elif analysis.get("parallel_mistake", False):
             feedback_parts.append("Incorrect result: 790 (Parallel calculation).")
        else:
            feedback_parts.append(f"Correct result not found. VLM saw: {detected_value}")

    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("Manual verification required (VLM error).")

    # Final Pass/Fail Determination
    # Threshold: 70 points.
    # Essential: Must have inputs and result correct to pass high threshold.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }