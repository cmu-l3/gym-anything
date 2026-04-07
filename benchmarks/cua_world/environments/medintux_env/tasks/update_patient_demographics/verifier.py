#!/usr/bin/env python3
"""
Verifier for update_patient_demographics task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_phone(phone):
    """Normalize phone number by removing spaces, dots, dashes."""
    if not phone:
        return ""
    return re.sub(r'[ .-]', '', str(phone))

def verify_update_patient_demographics(traj, env_info, task_info):
    """
    Verify that patient Hélène MARTINEAU's address and phone were updated.
    
    Expected updates:
    - Address: 8 Avenue des Champs
    - CP: 69003
    - City: Lyon
    - Phone: 04 72 33 45 67
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_address_part = "Avenue des Champs" # Partial match is safer for addresses
    expected_cp = metadata.get('expected_cp', "69003")
    expected_ville = metadata.get('expected_ville', "Lyon")
    expected_phone = metadata.get('expected_phone', "04 72 33 45 67")
    
    # Read result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if patient data exists (10 pts)
    if not result.get('patient_found', False):
        return {"passed": False, "score": 0, "feedback": "Patient record deleted or not found in database"}
    
    score += 10
    
    # 2. Verify Address Update (25 pts)
    final_addr = result.get('final_address', '')
    if expected_address_part.lower() in final_addr.lower():
        score += 25
        feedback_parts.append("Address updated")
    else:
        feedback_parts.append(f"Address incorrect (got: '{final_addr}')")

    # 3. Verify Postal Code (15 pts)
    final_cp = str(result.get('final_cp', '')).strip()
    if final_cp == expected_cp:
        score += 15
        feedback_parts.append("Postal code updated")
    else:
        feedback_parts.append(f"Postal code incorrect (got: '{final_cp}')")

    # 4. Verify City (15 pts)
    final_city = result.get('final_city', '')
    if expected_ville.lower() in final_city.lower():
        score += 15
        feedback_parts.append("City updated")
    else:
        feedback_parts.append(f"City incorrect (got: '{final_city}')")

    # 5. Verify Phone (25 pts)
    final_phone = result.get('final_phone', '')
    norm_final = normalize_phone(final_phone)
    norm_expected = normalize_phone(expected_phone)
    
    if norm_expected in norm_final:
        score += 25
        feedback_parts.append("Phone updated")
    else:
        feedback_parts.append(f"Phone incorrect (got: '{final_phone}')")

    # 6. Verify App State (10 pts)
    if result.get('app_was_running', False):
        score += 10
    else:
        feedback_parts.append("Warning: MedinTux was closed")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }