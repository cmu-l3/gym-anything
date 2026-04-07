#!/usr/bin/env python3
"""
Verifier for add_cleanup_contractor task.
Verifies that the agent added 'EcoResponse Services' to the CAMEO database with correct details.
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_cleanup_contractor(traj, env_info, task_info):
    """
    Verify the cleanup contractor was added correctly.
    
    Criteria:
    1. Record exists in database (20 pts)
    2. Phone numbers match (20 pts)
    3. Address matches (20 pts)
    4. Notes/Capabilities contain required keywords (30 pts)
    5. Database was modified during task (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    metadata = task_info.get('metadata', {})
    
    # Check 1: Record Found (20 pts)
    if result.get('record_found'):
        score += 20
        feedback.append("Record 'EcoResponse Services' found in database.")
    else:
        return {"passed": False, "score": 0, "feedback": "Record 'EcoResponse Services' NOT found in database."}

    data = result.get('data', {})
    
    # Check 2: Phone Numbers (20 pts)
    # Normalize phone numbers (remove non-digits)
    def normalize_phone(p):
        return ''.join(filter(str.isdigit, str(p))) if p else ""

    exp_phone = normalize_phone(metadata.get('expected_phone', '2195550123'))
    exp_emerg = normalize_phone(metadata.get('expected_emergency_phone', '8005559988'))
    
    act_phone = normalize_phone(data.get('Phone', ''))
    act_emerg = normalize_phone(data.get('EmergencyPhone', ''))
    
    if exp_phone in act_phone and exp_emerg in act_emerg:
        score += 20
        feedback.append("Phone numbers correct.")
    else:
        feedback.append(f"Phone mismatch. Expected business end in {exp_phone[-4:]}, emergency {exp_emerg[-4:]}.")
        # Partial credit
        if exp_phone in act_phone: score += 10
        if exp_emerg in act_emerg: score += 10

    # Check 3: Address (20 pts)
    city_match = metadata.get('expected_city', 'Gary').lower() == data.get('City', '').lower()
    state_match = metadata.get('expected_state', 'IN').lower() == data.get('State', '').lower()
    
    if city_match and state_match:
        score += 20
        feedback.append("City and State correct.")
    else:
        feedback.append(f"Address mismatch. Got {data.get('City')}, {data.get('State')}.")
        if city_match: score += 10
        if state_match: score += 5

    # Check 4: Notes/Capabilities (30 pts)
    notes = (data.get('Notes', '') + " " + data.get('Description', '')).lower()
    keywords = [k.lower() for k in metadata.get('required_notes_keywords', [])]
    
    found_keywords = [k for k in keywords if k in notes]
    
    if len(found_keywords) == len(keywords):
        score += 30
        feedback.append("All capability keywords found in notes.")
    else:
        partial = int(30 * (len(found_keywords) / len(keywords)))
        score += partial
        feedback.append(f"Missing keywords. Found {len(found_keywords)}/{len(keywords)}.")

    # Check 5: Anti-gaming / DB Modification (10 pts)
    task_start = result.get('task_start_time', 0)
    db_mod = result.get('db_last_modified', 0)
    
    # If DB was modified after task start
    if db_mod > task_start:
        score += 10
        feedback.append("Database file modified during task session.")
    else:
        feedback.append("Warning: Database file timestamp suggests no changes saved during session.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": data
    }