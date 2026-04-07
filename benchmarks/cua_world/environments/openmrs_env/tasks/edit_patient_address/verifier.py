#!/usr/bin/env python3
"""
Verifier for edit_patient_address task.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_omrs_date(date_str):
    """Parses OpenMRS ISO-like date strings."""
    if not date_str:
        return 0
    # Common formats: "2023-10-25T14:30:00.000+0000"
    try:
        # Simplistic parsing ignoring timezone nuances for this check
        # (We just need to know if it's generally after the start time)
        # Python 3.7+ handles ISO fromisoformat somewhat, but OpenMRS format can vary.
        # Let's clean it up slightly
        clean_str = date_str.split('+')[0]
        dt = datetime.strptime(clean_str, "%Y-%m-%dT%H:%M:%S.%f")
        return dt.timestamp()
    except Exception:
        return 0

def verify_edit_patient_address(traj, env_info, task_info):
    """
    Verifies that the patient address was updated correctly.
    
    Criteria:
    1. Patient exists (10 pts)
    2. Address Line 1 updated to '4521 Pine Ridge Drive' (25 pts)
    3. City updated to 'Austin' (20 pts)
    4. State updated to 'Texas' (20 pts)
    5. Postal Code updated to '78745' (15 pts)
    6. Modification happened AFTER task start (10 pts) - Anti-gaming
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_addr1 = metadata.get('expected_address1', '4521 Pine Ridge Drive')
    expected_city = metadata.get('expected_city', 'Austin')
    expected_state = metadata.get('expected_state', 'Texas')
    expected_postal = metadata.get('expected_postal', '78745')

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Criteria
    score = 0
    feedback = []
    
    # Check 1: Patient Found
    if not result.get('patient_found'):
        return {"passed": False, "score": 0, "feedback": "Patient 'Angela Rivera' could not be found in the system."}
    score += 10
    feedback.append("Patient record found.")

    addr = result.get('preferred_address', {})
    if not addr:
        return {"passed": False, "score": 10, "feedback": "Patient has no preferred address."}

    # Check 2: Address Line 1
    # Allow partial match for "Pine Ridge" in case of minor typos or "Dr" vs "Drive"
    actual_addr1 = addr.get('address1', '')
    if expected_addr1.lower() in actual_addr1.lower() or "4521 pine ridge" in actual_addr1.lower():
        score += 25
        feedback.append(f"Address Line 1 correct ({actual_addr1}).")
    else:
        feedback.append(f"Address Line 1 incorrect. Expected '{expected_addr1}', got '{actual_addr1}'.")

    # Check 3: City
    actual_city = addr.get('cityVillage', '')
    if expected_city.lower() == actual_city.lower():
        score += 20
        feedback.append(f"City correct ({actual_city}).")
    else:
        feedback.append(f"City incorrect. Expected '{expected_city}', got '{actual_city}'.")

    # Check 4: State
    actual_state = addr.get('stateProvince', '')
    if expected_state.lower() == actual_state.lower() or actual_state.lower() == "tx":
        score += 20
        feedback.append(f"State correct ({actual_state}).")
    else:
        feedback.append(f"State incorrect. Expected '{expected_state}', got '{actual_state}'.")

    # Check 5: Postal Code
    actual_postal = addr.get('postalCode', '')
    if expected_postal in actual_postal:
        score += 15
        feedback.append(f"Postal Code correct ({actual_postal}).")
    else:
        feedback.append(f"Postal Code incorrect. Expected '{expected_postal}', got '{actual_postal}'.")

    # Check 6: Anti-Gaming (Timestamp)
    task_start = result.get('task_start_time', 0)
    audit = addr.get('auditInfo', {})
    # dateChanged is preferred, dateCreated if it was a new object
    mod_date_str = audit.get('dateChanged') or audit.get('dateCreated')
    mod_time = parse_omrs_date(mod_date_str)

    if mod_time > task_start:
        score += 10
        feedback.append("Modification confirmed during task session.")
    else:
        feedback.append(f"Warning: Data does not appear modified during task (Mod Time: {mod_time} vs Start: {task_start}). This may be a pre-existing state or 'do nothing'.")
        # If the address is correct but timestamp is old, it means they did nothing and we accidentally started with the goal state (unlikely due to setup script) or they are gaming.
        # Since setup resets to San Francisco, getting Austin with old timestamp is impossible unless setup failed.
        # If values match but timestamp is old, it's suspicious. We withhold these points.

    passed = (score >= 80) # Requires most fields correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }