#!/usr/bin/env python3
"""
Verifier for Inductor Color Code Identification Task.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inductor_id(traj, env_info, task_info):
    """
    Verifies that the agent correctly identified the inductor value and tolerance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_mh = metadata.get('expected_val_mh', 1.0)
    expected_tol = metadata.get('expected_tolerance', "10%")

    # Retrieve result JSON from Android device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timing (20 pts)
    if result.get("file_exists") and result.get("created_during_task"):
        score += 20
        feedback_parts.append("Result file created successfully.")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("Result file exists but timestamp check failed (pre-existing?).")
    else:
        feedback_parts.append("Result file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Content Verification (40 pts)
    content = result.get("file_content", "")
    lines = content.split('\\n') # Handle the escaped newline from shell script
    if len(lines) < 2:
        # Try splitting by actual newline if escape didn't work as expected
        lines = content.split('\n')
    
    val_correct = False
    tol_correct = False
    
    if len(lines) >= 1:
        # Check Value (1.0 mH)
        # We accept 1, 1.0, 1.00. We DO NOT accept 1000 (which would be uH)
        try:
            val_str = lines[0].strip().lower().replace("mh", "").replace("m", "").strip()
            val_float = float(val_str)
            if 0.95 <= val_float <= 1.05:
                score += 30
                val_correct = True
                feedback_parts.append(f"Value correct: {val_float} mH.")
            elif 990 <= val_float <= 1010:
                feedback_parts.append(f"Value wrong unit: {val_float} (likely uH, expected mH).")
            else:
                feedback_parts.append(f"Value incorrect: {val_float} (Expected {expected_mh}).")
        except ValueError:
            feedback_parts.append(f"Could not parse value: {lines[0]}")

    if len(lines) >= 2:
        # Check Tolerance (10%)
        tol_str = lines[1].strip()
        if "10" in tol_str:
            score += 10
            tol_correct = True
            feedback_parts.append("Tolerance correct.")
        else:
            feedback_parts.append(f"Tolerance incorrect: {tol_str} (Expected 10%).")

    # 3. VLM Verification (40 pts)
    # Check trajectory to ensure correct tool usage (Inductor vs Resistor)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + [final_screen] if final_screen else frames

    vlm_prompt = """
    Analyze these screens from an electrical calculation app.
    1. Is the "Inductor Color Code" calculator visible? (Look for title 'Inductor' or symbol 'L', NOT 'Resistor' or symbol 'Ω').
    2. Are the color inputs set to: Brown, Black, Red, Silver?
    3. Is the result shown as approx "1000 µH" or "1 mH"?
    
    Return JSON:
    {
        "is_inductor_tool": true/false,
        "is_resistor_tool": true/false,
        "colors_match": true/false,
        "result_visible": true/false
    }
    """
    
    vlm_result = query_vlm(images=images_to_check, prompt=vlm_prompt)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("is_inductor_tool"):
            score += 20
            feedback_parts.append("Correct tool used (Inductor).")
        elif parsed.get("is_resistor_tool"):
            feedback_parts.append("Wrong tool used (Resistor Calculator).")
            
        if parsed.get("colors_match"):
            score += 10
            feedback_parts.append("Colors entered correctly.")
            
        if parsed.get("result_visible"):
            score += 10
            feedback_parts.append("Calculation result visible.")
    else:
        feedback_parts.append("VLM verification failed to process images.")

    # Final Pass Check
    # Must have value correct AND correct tool used to pass
    passed = val_correct and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }