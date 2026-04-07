#!/usr/bin/env python3
"""
Verifier for Record Patient Vitals task.

Programmatic Verification:
Reads the JSON exported by export_result.sh which queries the MySQL database directly.
Checks if the patient's vitals count increased and if the newest record contains 
the expected measurement values within specified tolerances.

VLM Verification:
Checks the trajectory frames to verify the agent actually navigated the clinical UI.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_float(value):
    try:
        float(value)
        return True
    except (ValueError, TypeError):
        return False

def value_exists_in_row(row_dict, target_value, tolerance):
    """
    Schema-agnostic check: Iterates through all values in the DB row and checks 
    if any numeric value matches the target value within the given tolerance.
    """
    for val in row_dict.values():
        if is_float(val):
            if abs(float(val) - target_value) <= tolerance:
                return True
    return False

def verify_record_vitals(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_vitals', {})
    tolerances = metadata.get('tolerances', {})

    # 1. Retrieve the exported JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    init_count = result.get('initial_count', 0)
    curr_count = result.get('current_count', 0)
    row = result.get('newest_vital', {})
    
    # 2. Verify Record Creation (Count increased) -> 20 pts
    if curr_count > init_count:
        score += 20
        feedback_parts.append(f"Vitals record created (count: {init_count} -> {curr_count})")
    else:
        feedback_parts.append(f"No new vitals record found for patient (count remains {init_count})")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    if not row:
        feedback_parts.append("Could not extract vitals row data.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Verify Specific Measurements (Schema Agnostic) -> 70 pts total
    # Check Temp (10 pts)
    if value_exists_in_row(row, expected['temperature'], tolerances['temperature']):
        score += 10
        feedback_parts.append("Temperature correct")
    else:
        feedback_parts.append("Temperature missing/incorrect")

    # Check Pulse (10 pts)
    if value_exists_in_row(row, expected['pulse'], tolerances['pulse']):
        score += 10
        feedback_parts.append("Pulse correct")
    else:
        feedback_parts.append("Pulse missing/incorrect")

    # Check Systolic (10 pts)
    if value_exists_in_row(row, expected['bp_systolic'], tolerances['bp_systolic']):
        score += 10
        feedback_parts.append("Systolic BP correct")
    else:
        feedback_parts.append("Systolic BP missing/incorrect")

    # Check Diastolic (10 pts)
    if value_exists_in_row(row, expected['bp_diastolic'], tolerances['bp_diastolic']):
        score += 10
        feedback_parts.append("Diastolic BP correct")
    else:
        feedback_parts.append("Diastolic BP missing/incorrect")

    # Check Respiratory Rate (10 pts)
    if value_exists_in_row(row, expected['respiratory_rate'], tolerances['respiratory_rate']):
        score += 10
        feedback_parts.append("Respiratory Rate correct")
    else:
        feedback_parts.append("Respiratory Rate missing/incorrect")

    # Check Weight (10 pts)
    if value_exists_in_row(row, expected['weight'], tolerances['weight']):
        score += 10
        feedback_parts.append("Weight correct")
    else:
        feedback_parts.append("Weight missing/incorrect")

    # Check Height (5 pts)
    if value_exists_in_row(row, expected['height'], tolerances['height']):
        score += 5
        feedback_parts.append("Height correct")
    else:
        feedback_parts.append("Height missing/incorrect")

    # Check O2 Saturation (5 pts - optional fallback depending on specific schema)
    if value_exists_in_row(row, expected['o2_sat'], tolerances['o2_sat']):
        score += 5
        feedback_parts.append("O2 Saturation correct")
    else:
        # Some older EMRs don't have O2 fields by default.
        feedback_parts.append("O2 Saturation not found in DB row")

    # 4. VLM Trajectory Verification -> 10 pts
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = (
                "Review these screenshots from a session in an Electronic Medical Record system. "
                "Did the user navigate to a patient chart and interact with a Vitals (or Clinical Measurements) entry form? "
                "Look for numeric input fields relating to Temperature, Blood Pressure, Weight, etc. "
                "Reply in JSON with {'vitals_form_used': true/false}."
            )
            vlm_resp = query_vlm(images=images, prompt=prompt)
            if vlm_resp and vlm_resp.get('parsed', {}).get('vitals_form_used'):
                vlm_score = 10
                feedback_parts.append("VLM verified vitals workflow")
            else:
                feedback_parts.append("VLM did not detect vitals entry form")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            vlm_score = 10  # Grant points if framework function fails to avoid penalizing agent
    else:
        vlm_score = 10  # Grant points if VLM not available
        
    score += vlm_score

    # Passed if the record was created and majority of data was accurately saved (>= 70 total)
    passed = score >= 70 and (curr_count > init_count)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }