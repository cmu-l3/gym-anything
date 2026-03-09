#!/usr/bin/env python3
"""
Verifier for update_clinic_details task.
Checks if the facility record in Oscar EMR was updated correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_clinic_details(traj, env_info, task_info):
    """
    Verifies that the main clinic facility record was updated with new details.
    
    Criteria:
    1. Address contains '455 Dovercourt' and 'Suite 102' (40 pts)
    2. Phone matches '416-555-0198' (20 pts)
    3. Fax matches '416-555-0199' (30 pts)
    4. Anti-gaming: The existing record (ID 1) was updated, not a new one created (10 pts)
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

    metadata = task_info.get('metadata', {})
    expected_addr_part = metadata.get('expected_address_part', '455 Dovercourt').lower()
    expected_suite = metadata.get('expected_suite', '102').lower()
    expected_phone = metadata.get('expected_phone', '416-555-0198')
    expected_fax = metadata.get('expected_fax', '416-555-0199')

    score = 0
    feedback = []
    
    # Analyze data
    # We prefer the ID 1 record if it exists, otherwise look at the matching record
    facility = result.get('facility_id_1')
    matching = result.get('facility_matching_target')
    
    initial_count = result.get('initial_count', 0)
    final_count = result.get('final_count', 0)
    
    target_record = facility if facility else matching
    
    if not target_record:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No facility record found matching ID 1 or the target phone number."
        }

    # 1. Verify Address (40 pts)
    # Concatenate address fields to be safe (Oscar sometimes splits address lines)
    full_address = (str(target_record.get('address', '')) + " " + str(target_record.get('city', ''))).lower()
    
    if expected_addr_part in full_address and expected_suite in full_address:
        score += 40
        feedback.append("Address updated correctly.")
    elif expected_addr_part in full_address:
        score += 20
        feedback.append("Address partially correct (missing suite).")
    else:
        feedback.append(f"Address mismatch. Expected '{expected_addr_part}', got '{full_address}'.")

    # 2. Verify Phone (20 pts)
    phone = str(target_record.get('phone', '')).replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    exp_phone_clean = expected_phone.replace("-", "")
    
    if exp_phone_clean in phone:
        score += 20
        feedback.append("Phone updated correctly.")
    else:
        feedback.append(f"Phone mismatch. Expected '{expected_phone}', got '{target_record.get('phone', '')}'.")

    # 3. Verify Fax (30 pts)
    fax = str(target_record.get('fax', '')).replace(" ", "").replace("-", "").replace("(", "").replace(")", "")
    exp_fax_clean = expected_fax.replace("-", "")
    
    if exp_fax_clean in fax:
        score += 30
        feedback.append("Fax updated correctly.")
    else:
        feedback.append(f"Fax mismatch. Expected '{expected_fax}', got '{target_record.get('fax', '')}'.")

    # 4. Anti-Gaming / Correct Method (10 pts)
    # Check if they updated the existing record (ID 1) or created a new one
    is_id_1 = (str(target_record.get('id')) == '1')
    count_increased = (final_count > initial_count)
    
    if is_id_1 and not count_increased:
        score += 10
        feedback.append("Correctly updated existing facility record.")
    elif is_id_1 and count_increased:
        # They updated ID 1 but also added something else? Weird but acceptable-ish
        score += 5
        feedback.append("Updated ID 1 but facility count increased (duplicate created?).")
    elif not is_id_1:
        feedback.append("Incorrectly created a new facility instead of updating the existing one.")
        # If they created a new one perfectly, they lose these 10 pts but keep the others
    
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }