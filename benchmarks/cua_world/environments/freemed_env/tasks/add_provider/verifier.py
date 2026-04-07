#!/usr/bin/env python3
"""
Verifier for add_provider task in FreeMED.
Ensures provider record is created with correct credentials and performs anti-gaming checks.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_provider(traj, env_info, task_info):
    """
    Verify that the new provider was added correctly to the FreeMED database.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'Maria')
    expected_lname = metadata.get('expected_lname', 'Rodriguez')
    expected_mname = metadata.get('expected_mname', 'Elena')
    expected_npi = metadata.get('expected_npi', '1528364791')
    expected_dea = metadata.get('expected_dea', 'AR5836472')
    expected_city = metadata.get('expected_city', 'Springfield')
    expected_state = metadata.get('expected_state', 'IL')
    expected_zip = metadata.get('expected_zip', '62704')
    expected_phone = metadata.get('expected_phone', '(217) 555-0183')
    expected_email = metadata.get('expected_email', 'm.rodriguez@riversidemedical.org')

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/add_provider_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    provider_found = result.get('provider_found', False)
    provider = result.get('provider', {})
    
    # 1. Provider Record Exists (20 pts)
    if provider_found:
        score += 20
        feedback_parts.append("Provider record found")
    else:
        feedback_parts.append("Provider record NOT found")
        # Early exit if main record doesn't exist
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. NPI Correct (20 pts)
    actual_npi = provider.get('npi', '').strip()
    if actual_npi == expected_npi:
        score += 20
        feedback_parts.append("NPI correct")
    else:
        feedback_parts.append(f"NPI mismatch (Expected: {expected_npi}, Got: {actual_npi})")

    # 3. DEA Correct (15 pts)
    actual_dea = provider.get('dea', '').strip().upper()
    if actual_dea == expected_dea.upper():
        score += 15
        feedback_parts.append("DEA correct")
    else:
        feedback_parts.append(f"DEA mismatch")

    # 4. Middle Name Set (5 pts)
    actual_mname = provider.get('mname', '').strip().lower()
    if expected_mname.lower() in actual_mname:
        score += 5
        feedback_parts.append("Middle name correct")
    else:
        feedback_parts.append("Middle name missing/mismatch")

    # 5. Address Fields Populated (10 pts)
    actual_city = provider.get('city', '').strip().lower()
    actual_state = provider.get('state', '').strip().lower()
    actual_zip = provider.get('zip', '').strip()
    
    addr_match = 0
    if expected_city.lower() in actual_city: addr_match += 1
    if expected_state.lower() in actual_state: addr_match += 1
    if expected_zip in actual_zip: addr_match += 1
    
    if addr_match == 3:
        score += 10
        feedback_parts.append("Address fields correct")
    elif addr_match > 0:
        score += 5
        feedback_parts.append("Address fields partially correct")
    else:
        feedback_parts.append("Address fields missing")

    # 6. Phone or Email Present (10 pts)
    actual_phone = provider.get('phone', '').strip()
    actual_email = provider.get('email', '').strip().lower()
    
    phone_clean = re.sub(r'\D', '', actual_phone)
    exp_phone_clean = re.sub(r'\D', '', expected_phone)
    
    phone_match = phone_clean == exp_phone_clean and len(phone_clean) > 0
    email_match = expected_email.lower() in actual_email
    
    if phone_match and email_match:
        score += 10
        feedback_parts.append("Phone & Email correct")
    elif phone_match or email_match:
        score += 8
        feedback_parts.append("Phone OR Email correct")
    else:
        feedback_parts.append("Contact info missing")

    # 7. Specialty Set (5 pts)
    actual_specialty = provider.get('specialty', '').strip().lower()
    if 'internal' in actual_specialty or 'medicine' in actual_specialty:
        score += 5
        feedback_parts.append("Specialty correct")
    else:
        feedback_parts.append("Specialty mismatch")

    # 8. New Record / Anti-Gaming (15 pts)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    initial_max_id = result.get('initial_max_id', 0)
    provider_id = provider.get('id', 0)
    
    if current_count > initial_count and provider_id > initial_max_id:
        score += 15
        feedback_parts.append("Anti-gaming: Record newly created")
    else:
        feedback_parts.append("Anti-gaming: Failed - Record does not appear new")

    # Final scoring: pass threshold is 60/100
    passed = score >= 60 and provider_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }