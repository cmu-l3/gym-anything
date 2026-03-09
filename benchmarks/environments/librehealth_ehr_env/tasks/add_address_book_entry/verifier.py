#!/usr/bin/env python3
import json
import os
import tempfile
import re

def normalize_phone(phone_str):
    """Normalize phone number to digits only for comparison."""
    if not phone_str:
        return ""
    return re.sub(r'\D', '', str(phone_str))

def verify_add_address_book_entry(traj, env_info, task_info):
    """
    Verifies that the agent added 'Elena Rodriguez' to the address book with correct details.
    """
    # 1. Setup: Load result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Metadata (Expected Values)
    metadata = task_info.get('metadata', {})
    
    # 3. Grading Logic
    score = 0
    feedback_log = []
    
    # Check if entry was found at all
    if not result.get('found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No address book entry found for 'Elena Rodriguez'. Agent did not create the record."
        }

    data = result['data']
    
    # Anti-gaming: Check ID is new
    initial_max_id = result.get('initial_max_id', 999999999)
    if data['id'] <= initial_max_id:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Detected pre-existing record. The agent must create a NEW entry during the task."
        }
    
    # Criterion 1: Entry Exists (already verified found + new ID)
    score += 15
    feedback_log.append("Entry created successfully (15/15)")

    # Criterion 2: Entry Type (10 pts)
    # abook_type often indicates 'referee' (referring provider) or is empty depending on exact form usage
    # We look for indications it's not a patient/user
    if data.get('abook_type') in ['referee', 'physician', 'provider'] or not data.get('password'):
        # Usually referring providers don't have passwords/login, but exact type string varies.
        # 'referee' is the standard internal value for 'Referring Provider' in many OpenEMR forks.
        score += 10
        feedback_log.append("Entry type appears correct (10/10)")
    else:
        feedback_log.append("Entry type might be incorrect (0/10)")

    # Criterion 3: Organization (10 pts)
    # Flexible match for "City General Hospital"
    if "city general" in data.get('organization', '').lower():
        score += 10
        feedback_log.append("Organization matches (10/10)")
    else:
        feedback_log.append(f"Organization mismatch: '{data.get('organization')}' (0/10)")

    # Criterion 4: Phone (10 pts)
    expected_phone = metadata.get('expected_phone', '5554827100')
    actual_phone = normalize_phone(data.get('phone', ''))
    # Check if expected is contained in actual (handles extensions or formatting diffs)
    if expected_phone in actual_phone:
        score += 10
        feedback_log.append("Phone number matches (10/10)")
    else:
        feedback_log.append(f"Phone mismatch: '{actual_phone}' vs expected '{expected_phone}' (0/10)")

    # Criterion 5: Fax (10 pts)
    expected_fax = metadata.get('expected_fax', '5554827101')
    actual_fax = normalize_phone(data.get('fax', ''))
    if expected_fax in actual_fax:
        score += 10
        feedback_log.append("Fax number matches (10/10)")
    else:
        feedback_log.append("Fax number mismatch (0/10)")

    # Criterion 6: Email (10 pts)
    expected_email = metadata.get('expected_email', '').lower()
    actual_email = data.get('email', '').lower()
    if expected_email == actual_email:
        score += 10
        feedback_log.append("Email matches (10/10)")
    else:
        feedback_log.append(f"Email mismatch: '{actual_email}' (0/10)")

    # Criterion 7: Street Address (10 pts)
    expected_street = metadata.get('expected_street', '').lower()
    actual_street = data.get('street', '').lower()
    if expected_street in actual_street:
        score += 10
        feedback_log.append("Street address matches (10/10)")
    else:
        feedback_log.append("Street address mismatch (0/10)")

    # Criterion 8: City/State/Zip (15 pts)
    geo_score = 0
    if metadata.get('expected_city', '').lower() == data.get('city', '').lower(): geo_score += 5
    if metadata.get('expected_state', '').lower() == data.get('state', '').lower(): geo_score += 5
    if metadata.get('expected_zip', '') in data.get('zip', ''): geo_score += 5
    score += geo_score
    feedback_log.append(f"City/State/Zip checks ({geo_score}/15)")

    # Criterion 9: Specialty (10 pts)
    # Specialty is sometimes stored in 'specialty' column or 'notes' depending on layout
    expected_specialty = metadata.get('expected_specialty', 'Cardiology').lower()
    actual_specialty = (data.get('specialty') or '').lower() + " " + (data.get('notes') or '').lower()
    if expected_specialty in actual_specialty:
        score += 10
        feedback_log.append("Specialty matches (10/10)")
    else:
        feedback_log.append("Specialty mismatch (0/10)")

    # 4. Final Assessment
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_log)
    }