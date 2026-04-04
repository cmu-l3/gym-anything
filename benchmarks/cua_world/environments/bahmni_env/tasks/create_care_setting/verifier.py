#!/usr/bin/env python3
"""
Verifier for create_care_setting task.
Checks if the 'Telemedicine' care setting was created correctly in OpenMRS.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_care_setting(traj, env_info, task_info):
    """
    Verifies the creation of the Telemedicine care setting.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract data
    api_result = result.get("api_result", {})
    initial_count = int(result.get("initial_count", 0))
    final_count = int(api_result.get("total_count", 0))
    
    found = api_result.get("found", False)
    name = api_result.get("name", "")
    description = api_result.get("description", "")
    care_type = api_result.get("careSettingType", "")
    retired = api_result.get("retired", False)

    metadata = task_info.get("metadata", {})
    expected_keywords = metadata.get("expected_description_keywords", ["Remote", "consultation"])
    expected_type = metadata.get("expected_type", "OUTPATIENT")

    score = 0
    feedback = []

    # Criterion 1: Existence (40 pts)
    if found and name == "Telemedicine":
        score += 40
        feedback.append("Care Setting 'Telemedicine' found.")
    else:
        feedback.append("Care Setting 'Telemedicine' NOT found.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # Criterion 2: Care Setting Type (30 pts)
    # OpenMRS might return "OUTPATIENT" or "Outpatient" or an enum. Flexible check.
    if str(care_type).upper() == expected_type.upper():
        score += 30
        feedback.append(f"Correct type: {care_type}.")
    else:
        feedback.append(f"Incorrect type. Expected {expected_type}, got '{care_type}'.")

    # Criterion 3: Description (10 pts)
    desc_score = 0
    if description:
        hits = [k for k in expected_keywords if k.lower() in description.lower()]
        if len(hits) > 0:
            desc_score = 10
            feedback.append("Description contains required keywords.")
        else:
            feedback.append(f"Description '{description}' missing keywords.")
    else:
        feedback.append("Description is empty.")
    score += desc_score

    # Criterion 4: Active Status (10 pts)
    if not retired:
        score += 10
        feedback.append("Care Setting is active.")
    else:
        feedback.append("Care Setting is retired (inactive).")

    # Criterion 5: New Record Created (10 pts)
    # Prevents just renaming an existing one if we didn't purge correctly, 
    # but primarily confirms action happened.
    if final_count > initial_count:
        score += 10
        feedback.append("New record count increased.")
    else:
        feedback.append("No increase in record count (reused existing?).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }