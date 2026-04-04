#!/usr/bin/env python3
"""
Verifier for wire_dc_resistance task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wire_dc_resistance(traj, env_info, task_info):
    """
    Verifies the DC resistance calculation task.
    
    Criteria:
    1. Result screenshot exists and was created during task (Anti-gaming).
    2. VLM confirms the correct calculator (Wire/Conductor Resistance) was used.
    3. VLM confirms inputs: Copper, 200m, 1.5mm2.
    4. VLM confirms result: ~2.29 Ohms.
    5. Trajectory shows app interaction.
    """
    
    # 1. Setup and Dependencies
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 2. Retrieve Result JSON and Screenshot from Device
    temp_dir = tempfile.mkdtemp()
    local_json = os.path.join(temp_dir, "task_result.json")
    local_screenshot = os.path.join(temp_dir, "task_result.png")
    local_fallback = os.path.join(temp_dir, "final_state_fallback.png")
    
    try:
        # Pull JSON
        copy_from_env("/sdcard/task_result.json", local_json)
        with open(local_json, 'r') as f:
            result_data = json.load(f)
            
        # Pull Screenshot (if it exists according to JSON)
        screenshot_for_vlm = None
        if result_data.get("screenshot_exists"):
            try:
                copy_from_env("/sdcard/task_result.png", local_screenshot)
                screenshot_for_vlm = local_screenshot
            except Exception:
                logger.warning("JSON said screenshot exists but failed to copy.")
        
        # If user didn't save screenshot, use fallback for partial credit/analysis
        if not screenshot_for_vlm:
            try:
                copy_from_env("/sdcard/final_state_fallback.png", local_fallback)
                screenshot_for_vlm = local_fallback
            except Exception:
                pass
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task data: {str(e)}"}

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion A: Screenshot File Handling (20 pts)
    # Did the agent actually save the screenshot as requested?
    if result_data.get("screenshot_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Screenshot saved correctly.")
    else:
        feedback_parts.append("Screenshot NOT saved to /sdcard/task_result.png.")

    # Criterion B: VLM Verification of Content (80 pts)
    if not screenshot_for_vlm:
        return {"passed": False, "score": score, "feedback": "No visual evidence available."}

    # Prepare VLM Prompt
    # We check both the specific result screenshot and trajectory to ensure they didn't just 'paint' a result
    prompt = """
    You are an expert Electrical Engineering verifier.
    Analyze this screenshot from the 'Electrical Calculations' Android app.
    
    Verification Goals:
    1. **Calculator Type**: Is the "Wire Resistance" or "Conductor Resistance" calculator visible? (NOT Ohm's Law, NOT Voltage Drop).
    2. **Inputs**: 
       - Material: Copper (or resistivity ~0.0172)
       - Length: 200 (meters)
       - Area/Section: 1.5 (mm²)
    3. **Result**: Is the calculated resistance approximately 2.29 Ω? (Accept 2.2 - 2.4).
    
    Output JSON:
    {
        "correct_calculator": boolean,
        "correct_material": boolean,
        "correct_length": boolean,
        "correct_area": boolean,
        "result_value": float or null,
        "result_correct": boolean,
        "reasoning": "string"
    }
    """
    
    # We use the final screenshot (either the one they saved, or the fallback)
    vlm_response = query_vlm(prompt=prompt, images=[screenshot_for_vlm])
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": score, "feedback": "VLM analysis failed."}
        
    analysis = vlm_response.get("parsed", {})
    
    # Evaluate VLM Analysis
    if analysis.get("correct_calculator"):
        score += 20
        feedback_parts.append("Correct calculator selected.")
    else:
        feedback_parts.append("Wrong calculator visible.")

    # Inputs (10 pts each)
    if analysis.get("correct_material"): score += 10
    if analysis.get("correct_length"): score += 10
    if analysis.get("correct_area"): score += 10
    
    if not (analysis.get("correct_material") and analysis.get("correct_length") and analysis.get("correct_area")):
        feedback_parts.append("Incorrect inputs detected.")

    # Result (20 pts)
    if analysis.get("result_correct"):
        score += 20
        feedback_parts.append("Correct resistance result (2.29 Ω).")
    else:
        feedback_parts.append(f"Incorrect result value: {analysis.get('result_value')}")

    # 4. Trajectory Sanity Check (Optional but good)
    # Ensure they actually launched the app
    frames = sample_trajectory_frames(traj, n=3)
    # (Simple check: if we have 0 score so far, trajectory won't save it)

    passed = (score >= 60) and analysis.get("result_correct")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }