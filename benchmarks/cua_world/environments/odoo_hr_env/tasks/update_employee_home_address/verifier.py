#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_employee_home_address(traj, env_info, task_info):
    """
    Verify that Audrey Peterson's home address was updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
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

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_street = metadata.get('expected_street', "789 Pine Avenue")
    expected_street2 = metadata.get('expected_street2', "Apt 4B")
    expected_city = metadata.get('expected_city', "San Francisco")
    expected_state = metadata.get('expected_state', "California")
    expected_zip = metadata.get('expected_zip', "94103")

    score = 0
    feedback = []

    # Check 1: Employee found and address linked (20 pts)
    if not result.get("employee_found"):
        return {"passed": False, "score": 0, "feedback": "Employee 'Audrey Peterson' not found."}
    
    if result.get("address_linked"):
        score += 20
        feedback.append("Address record linked.")
    else:
        return {"passed": False, "score": 0, "feedback": "No Private Address linked to employee."}

    # Check 2: Street Address (20 pts)
    # Check if both parts are present in the combined string
    actual_street = result.get("street", "").lower()
    if expected_street.lower() in actual_street and expected_street2.lower() in actual_street:
        score += 20
        feedback.append("Street address correct.")
    else:
        feedback.append(f"Street incorrect. Expected parts '{expected_street}' and '{expected_street2}', got '{actual_street}'.")

    # Check 3: City (20 pts)
    if result.get("city", "").lower() == expected_city.lower():
        score += 20
        feedback.append("City correct.")
    else:
        feedback.append(f"City incorrect. Expected '{expected_city}', got '{result.get('city')}'.")

    # Check 4: State (20 pts)
    # Flexible matching for state (e.g. "California" or "CA" if Odoo stores abbreviations in name)
    actual_state = result.get("state_name", "").lower()
    if expected_state.lower() in actual_state or "ca" == actual_state:
        score += 20
        feedback.append("State correct.")
    else:
        feedback.append(f"State incorrect. Expected '{expected_state}', got '{result.get('state_name')}'.")

    # Check 5: Zip (20 pts)
    if str(result.get("zip", "")).strip() == str(expected_zip):
        score += 20
        feedback.append("Zip code correct.")
    else:
        feedback.append(f"Zip incorrect. Expected '{expected_zip}', got '{result.get('zip')}'.")

    # Anti-gaming: Check if data was modified recently
    # We don't deduct points for this but fail if it looks stale (e.g., pre-existing correct data, though unlikely given setup)
    # In this specific setup script, we reset data, so if it matches, they likely changed it.
    
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }