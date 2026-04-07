#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_water_balance(traj, env_info, task_info):
    """
    Verify the Agricultural Water Balance Modeling task.
    
    Scoring Criteria:
    1. Process Creation (20 pts): Process 'Wheat Cultivation...' found in DB.
    2. Inputs Correct (20 pts): Rain (~1200) and Surface/Irrigation (~500).
    3. Runoff Output (20 pts): Output flow ~100.
    4. Evapotranspiration Calc (30 pts): Output flow to air ~1599.85.
    5. CSV Export (10 pts): File exists and created during task.
    
    Pass Threshold: 60 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_evap = metadata.get('target_evapotranspiration', 1599.85)
    tolerance = metadata.get('tolerance', 1.0)

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. CSV Export (10 pts)
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 10
        feedback.append("CSV exported successfully.")
    elif result.get("csv_exists"):
        score += 5
        feedback.append("CSV exists but timestamp uncertain.")
    else:
        feedback.append("CSV file not found.")

    # 2. Process Creation (20 pts)
    if result.get("process_found"):
        score += 20
        feedback.append("Process 'Wheat Cultivation' found in database.")
    else:
        feedback.append("Process NOT found in database.")
        # If process not found, we can't verify exchanges
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Parse Exchange Data
    # Format from Derby usually looks like:
    # IS_INPUT | AMOUNT | NAME
    # 1        | 1200.0 | Water, rain
    raw_data = result.get("exchange_query_output", "")
    
    # Helper to parse logic
    inputs = {}
    outputs = {}
    
    # Regex to find rows: (0 or 1)\s+\|\s+([0-9.]+)\s+\|\s+(.*?)($|\s\s)
    # Note: raw_data might be one long string with newlines replaced by spaces in shell script
    # Let's try to match patterns broadly
    
    # Look for Inputs (IS_INPUT = 1)
    # We look for number 1, followed by amount, followed by name
    input_matches = re.findall(r'1\s+(\d+\.?\d*)\s+([a-zA-Z0-9, _-]+)', raw_data)
    for amt, name in input_matches:
        inputs[name.strip()] = float(amt)

    # Look for Outputs (IS_INPUT = 0)
    output_matches = re.findall(r'0\s+(\d+\.?\d*)\s+([a-zA-Z0-9, _-]+)', raw_data)
    for amt, name in output_matches:
        outputs[name.strip()] = float(amt)

    logger.info(f"Parsed Inputs: {inputs}")
    logger.info(f"Parsed Outputs: {outputs}")

    # 3. Verify Inputs (20 pts)
    rain_found = any("rain" in name.lower() and abs(amt - 1200.0) <= tolerance for name, amt in inputs.items())
    surface_found = any(("surface" in name.lower() or "fresh" in name.lower() or "irrigation" in name.lower()) and abs(amt - 500.0) <= tolerance for name, amt in inputs.items())
    
    if rain_found:
        score += 10
        feedback.append("Rain input correct.")
    else:
        feedback.append("Rain input missing or incorrect value.")

    if surface_found:
        score += 10
        feedback.append("Irrigation/Surface input correct.")
    else:
        feedback.append("Irrigation input missing or incorrect value.")

    # 4. Verify Outputs (Runoff) (20 pts)
    runoff_found = False
    # Runoff is likely just "Water" or "Water, surface" output, amount 100
    for name, amt in outputs.items():
        if abs(amt - 100.0) <= tolerance:
            runoff_found = True
            break
    
    if runoff_found:
        score += 20
        feedback.append("Runoff output correct.")
    else:
        feedback.append("Runoff output missing or incorrect value.")

    # 5. Verify Evapotranspiration (30 pts)
    # This is the calculated value: ~1599.85
    evap_found = False
    for name, amt in outputs.items():
        if abs(amt - target_evap) <= tolerance:
            evap_found = True
            break
            
    if evap_found:
        score += 30
        feedback.append(f"Evapotranspiration calculated correctly ({target_evap} +/- {tolerance}).")
    else:
        feedback.append(f"Evapotranspiration value incorrect. Expected ~{target_evap}.")

    # VLM Verification (Bonus/Confirmation)
    # If score is borderline, we check VLM to confirm they were in the editor
    if score >= 40 and score < 100:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = "Is this an OpenLCA process editor showing a list of Inputs and Outputs? Do you see values like 1200, 500, or 1599?"
        vlm_res = query_vlm(prompt=prompt, images=frames + [final])
        
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("positive_match", False):
            # No points added, but validates the effort
            pass

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }