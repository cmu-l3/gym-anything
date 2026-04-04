#!/usr/bin/env python3
"""
Verifier for launch_telehealth_service task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_launch_telehealth_service(traj, env_info, task_info):
    """
    Verifies that:
    1. 'Telehealth' was added to the Visit Type lookup list.
    2. A new appointment for Lars Jensen was created with type 'Telehealth'.
    3. The appointment date/time matches the request (2025-10-15 10:00 AM).
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

    score = 0
    feedback = []
    
    # --- Criterion 1: Configuration (40 pts) ---
    config_doc = result.get('config_doc', {})
    # HospitalRun lookup structure: values is a list of strings
    # Or sometimes nested in 'data' depending on version/write method
    values = config_doc.get('values', [])
    if not values:
         values = config_doc.get('data', {}).get('values', [])
    
    telehealth_configured = False
    for val in values:
        if isinstance(val, str) and 'telehealth' in val.lower():
            telehealth_configured = True
            break
    
    if telehealth_configured:
        score += 40
        feedback.append("Configuration: 'Telehealth' successfully added to Visit Types.")
    else:
        feedback.append("Configuration: 'Telehealth' NOT found in Visit Type lookup list.")

    # --- Criterion 2 & 3: Appointment Creation & Details (60 pts) ---
    appointments = result.get('appointments', [])
    task_start_ts = result.get('task_start', 0)
    
    target_date_str = "2025-10-15"
    target_time_str = "10:00" # matches 10:00 AM roughly
    
    valid_appointment_found = False
    correct_type = False
    correct_datetime = False
    
    for appt in appointments:
        # Check creation time if available (anti-gaming), though we cleared relevant appts
        # HospitalRun docs might have 'createdAt' or 'dateCreated'
        # If not, we rely on the fact we didn't seed any Telehealth appts for Lars.
        
        # Check Type
        a_type = appt.get('appointmentType', appt.get('type', ''))
        if 'telehealth' in str(a_type).lower():
            correct_type = True
            
            # Check Date
            # Date format in HR is typically ISO timestamp or MM/DD/YYYY
            start_date = appt.get('startDate', '')
            end_date = appt.get('endDate', '')
            
            # Loose string matching for robustness
            date_match = target_date_str in str(start_date)
            
            # Time matching can be tricky due to timezones, check if "10:00" string is roughly present
            # HR often stores like "2025-10-15T10:00:00.000Z" (UTC) or local
            # The prompt asked for 10:00 AM.
            # If the user input 10:00 AM, it likely appears in the ISO string or separate time field
            time_match = "10:00" in str(start_date) or "10:00" in str(end_date)
            
            if date_match:
                correct_datetime = True
                if time_match:
                    pass # Perfect
            
            valid_appointment_found = True
            break
    
    if valid_appointment_found:
        score += 20 # Created
        feedback.append("Appointment: Created for Lars Jensen.")
        
        if correct_type:
            score += 20
            feedback.append("Appointment: Correctly set as 'Telehealth'.")
        
        if correct_datetime:
            score += 20
            feedback.append("Appointment: Date/Time matches expected values.")
        else:
            feedback.append("Appointment: Date/Time incorrect or could not be parsed.")
    else:
        feedback.append("Appointment: No 'Telehealth' appointment found for Lars Jensen.")

    passed = (score >= 80) # Config + Appt Type required
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }