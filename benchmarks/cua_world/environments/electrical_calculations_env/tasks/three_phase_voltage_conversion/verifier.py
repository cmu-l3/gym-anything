#!/usr/bin/env python3
"""
Verifier for three_phase_voltage_conversion task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_three_phase_voltage(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated the phase voltage.
    
    Strategy:
    1. Check if agent created the requested screenshot (Evidence).
    2. Use VLM to analyze the screen (either agent's screenshot or fallback).
    3. Confirm inputs (480) and outputs (~277) and context (Line to Phase).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Define paths based on export script
    remote_json_path = "/sdcard/tmp/three_phase/result.json"
    
    # Load result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env(remote_json_path, f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result JSON: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}

    # Determine which image to verify
    # Prefer the agent's saved screenshot if it exists and is fresh
    agent_screenshot_path = task_result.get("agent_screenshot_path")
    fallback_screenshot_path = task_result.get("fallback_screenshot_path")
    
    image_to_verify_local = None
    using_agent_screenshot = False
    
    if task_result.get("agent_screenshot_exists") and task_result.get("agent_screenshot_fresh"):
        remote_img = agent_screenshot_path
        using_agent_screenshot = True
    else:
        remote_img = fallback_screenshot_path
        
    # Copy image
    if remote_img:
        try:
            tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
            copy_from_env(remote_img, tmp_img.name)
            tmp_img.close()
            image_to_verify_local = tmp_img.name
        except Exception as e:
            logger.error(f"Failed to copy screenshot: {e}")

    if not image_to_verify_local:
         return {"passed": False, "score": 0, "feedback": "No screenshot evidence available for verification."}

    # VLM Verification
    prompt = """
    Analyze this screenshot from an electrical calculation app.
    
    I need to verify if the user is performing a "Line to Phase" voltage conversion.
    
    Check for the following:
    1. Is the screen showing a "Line to Phase" or "Line-Phase" converter? (NOT Impedance/Star-Delta)
    2. Is the Input value (Line Voltage) set to 480?
    3. Is the Result value (Phase Voltage) showing approximately 277 (e.g., 277, 277.1, 277.12)?
    
    Return JSON:
    {
        "is_correct_tool": boolean,
        "input_value_480_visible": boolean,
        "result_value_277_visible": boolean,
        "incorrect_tool_detected": string or null
    }
    """
    
    vlm_out = query_vlm(
        prompt=prompt,
        image=image_to_verify_local
    )
    
    # Clean up local image
    if os.path.exists(image_to_verify_local):
        os.unlink(image_to_verify_local)

    if not vlm_out.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed."}
        
    analysis = vlm_out.get("parsed", {})
    
    # Scoring
    score = 0
    feedback = []
    
    # Criterion 1: Correct Tool (30 pts)
    if analysis.get("is_correct_tool"):
        score += 30
        feedback.append("Correct converter tool selected.")
    else:
        feedback.append("Incorrect tool or screen.")
        
    # Criterion 2: Input Entry (20 pts)
    if analysis.get("input_value_480_visible"):
        score += 20
        feedback.append("Input 480V detected.")
    else:
        feedback.append("Input 480V NOT detected.")
        
    # Criterion 3: Calculation Accuracy (30 pts)
    if analysis.get("result_value_277_visible"):
        score += 30
        feedback.append("Result 277V detected.")
    else:
        feedback.append("Result 277V NOT detected.")
        
    # Criterion 4: Evidence (20 pts)
    if using_agent_screenshot:
        score += 20
        feedback.append("Screenshot saved correctly by agent.")
    else:
        feedback.append("Agent did not save the result to the specified path (used fallback).")

    # Pass logic
    # Must have used correct tool and got correct result to pass
    passed = analysis.get("is_correct_tool") and analysis.get("result_value_277_visible") and score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }