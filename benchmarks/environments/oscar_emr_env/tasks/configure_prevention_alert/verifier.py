#!/usr/bin/env python3
"""
Verifier for configure_prevention_alert task.

Verifies:
1. Prevention rule exists with correct name "Senior Weight Monitor" (30pts)
2. Minimum age is set to 65 (20pts)
3. Frequency is set to 12 Months (20pts)
4. Alert message contains "unexpected weight loss" (15pts)
5. Linked to correct measurement type (Weight/WT) (15pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_prevention_alert(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract rule data
    rule = result.get('rule', {})
    found_by_name = result.get('found_by_name', False)
    
    # --- Criterion 1: Rule Created (30 pts) ---
    if found_by_name:
        score += 30
        feedback.append("Success: Rule 'Senior Weight Monitor' found.")
    elif result.get('current_count', 0) > result.get('initial_count', 0):
        # Fallback: Rule created but wrong name
        score += 10
        feedback.append(f"Partial: A new rule was created, but name '{rule.get('name')}' != expected 'Senior Weight Monitor'.")
    else:
        feedback.append("Fail: No new prevention rule detected.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- Criterion 2: Age Correct (20 pts) ---
    # Database might return "65" or "65.0"
    try:
        age_min = float(rule.get('age_min', 0))
        if age_min == 65:
            score += 20
            feedback.append("Age minimum is 65.")
        else:
            feedback.append(f"Incorrect Age: expected 65, got {age_min}.")
    except ValueError:
        feedback.append(f"Invalid Age value: {rule.get('age_min')}.")

    # --- Criterion 3: Frequency Correct (20 pts) ---
    # Duration = 12, Unit = Month(s) OR Duration = 1, Unit = Year(s)
    try:
        dur = float(rule.get('duration', 0))
        unit = str(rule.get('unit', '')).lower()
        
        valid_months = (dur == 12 and 'month' in unit)
        valid_years = (dur == 1 and 'year' in unit)
        
        if valid_months or valid_years:
            score += 20
            feedback.append(f"Frequency correct ({dur} {unit}).")
        else:
            feedback.append(f"Incorrect Frequency: got {dur} {unit}, expected 12 months.")
    except ValueError:
        feedback.append("Invalid Duration value.")

    # --- Criterion 4: Alert Text (15 pts) ---
    msg = rule.get('message', '').lower()
    expected_text = metadata.get('expected_text_fragment', 'unexpected weight loss').lower()
    
    if expected_text in msg:
        score += 15
        feedback.append("Alert text matches keywords.")
    else:
        feedback.append(f"Alert text missing keywords '{expected_text}'.")

    # --- Criterion 5: Measurement Type (15 pts) ---
    # Type code 'WT' or desc 'Weight'
    type_code = str(rule.get('type_code', '')).upper()
    type_desc = str(rule.get('type_desc', '')).lower()
    
    if 'WT' in type_code or 'weight' in type_desc:
        score += 15
        feedback.append("Correctly linked to Weight.")
    else:
        feedback.append(f"Incorrect Measurement Type: got code '{type_code}' / desc '{type_desc}'.")

    # --- Pass Threshold ---
    # Need 85 points (allows failing text or type, but not core logic)
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }