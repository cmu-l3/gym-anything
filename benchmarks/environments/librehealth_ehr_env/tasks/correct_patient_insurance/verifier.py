#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_patient_insurance(traj, env_info, task_info):
    """
    Verifies that the patient's insurance record was updated correctly.
    
    Criteria:
    1. Policy Number matches 'XJ9942010' (40 pts)
    2. Copay matches '25.00' (40 pts)
    3. The original record ID was preserved (updated, not replaced) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    final_policy = str(result.get('final_policy_number', '')).strip()
    final_copay_str = str(result.get('final_copay', '')).strip()
    initial_id = str(result.get('initial_insurance_id', ''))
    final_id = str(result.get('final_insurance_id', ''))

    expected_policy = "XJ9942010"
    expected_copay_val = 25.0

    score = 0
    feedback = []

    # 1. Verify Policy Number
    if final_policy == expected_policy:
        score += 40
        feedback.append("Policy Number correct.")
    else:
        feedback.append(f"Policy Number incorrect. Expected '{expected_policy}', found '{final_policy}'.")

    # 2. Verify Copay
    # Handle copay string (might be '25', '25.00', '25.0')
    try:
        copay_val = float(final_copay_str)
        if abs(copay_val - expected_copay_val) < 0.01:
            score += 40
            feedback.append("Copay amount correct.")
        else:
            feedback.append(f"Copay incorrect. Expected '{expected_copay_val}', found '{copay_val}'.")
    except ValueError:
        feedback.append(f"Copay invalid. Found '{final_copay_str}'.")

    # 3. Verify Record Preservation (Update vs Replace)
    # The ID should exist and match the initial ID
    if final_id and final_id == initial_id:
        score += 20
        feedback.append("Existing record updated correctly.")
    elif final_id and final_id != initial_id:
        feedback.append("New record created instead of updating existing one (ID changed).")
    else:
        feedback.append("No primary insurance record found.")

    # Pass threshold
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }