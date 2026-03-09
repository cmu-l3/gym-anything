#!/usr/bin/env python3
"""Verifier for enrich_customer_profile_from_signature task."""

import json
import tempfile
import os
import re

def normalize_phone(phone):
    """Remove all non-digit characters for robust comparison."""
    if not phone:
        return ""
    return re.sub(r'\D', '', str(phone))

def verify_enrich_customer_profile(traj, env_info, task_info):
    """
    Verify that the customer profile was updated correctly.
    
    Criteria:
    1. First Name Matches Signature (25 pts)
    2. Last Name Matches Signature (25 pts)
    3. Phone Number Captured (30 pts)
    4. Job Title Recorded (in Title or Notes) (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    
    # Extract data
    customer_found = result.get('customer_found', False)
    db_state = result.get('db_state', {})
    ground_truth = result.get('ground_truth', {})
    
    if not customer_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Fatal: Customer record not found in database for verification."
        }

    # 1. Check Name (First) - 25 pts
    expected_first = ground_truth.get('first_name', '').strip()
    actual_first = db_state.get('first_name', '').strip()
    
    if actual_first.lower() == expected_first.lower():
        score += 25
        feedback_parts.append(f"First Name correct ({actual_first})")
    else:
        feedback_parts.append(f"First Name mismatch (Expected: {expected_first}, Got: {actual_first})")

    # 2. Check Name (Last) - 25 pts
    expected_last = ground_truth.get('last_name', '').strip()
    actual_last = db_state.get('last_name', '').strip()
    
    if actual_last.lower() == expected_last.lower():
        score += 25
        feedback_parts.append(f"Last Name correct ({actual_last})")
    else:
        feedback_parts.append(f"Last Name mismatch (Expected: {expected_last}, Got: {actual_last})")

    # 3. Check Phone - 30 pts
    expected_phone_raw = ground_truth.get('phone', '')
    actual_phone_raw = db_state.get('phone', '')
    
    # Normalize
    expected_digits = normalize_phone(expected_phone_raw)
    actual_digits = normalize_phone(actual_phone_raw)
    
    # Fuzzy match: check if expected digits are contained in actual (to account for extensions or country codes)
    if expected_digits and actual_digits and expected_digits in actual_digits:
        score += 30
        feedback_parts.append(f"Phone correct ({actual_phone_raw})")
    elif actual_digits:
        feedback_parts.append(f"Phone incorrect (Expected digits: {expected_digits}, Got: {actual_digits})")
    else:
        feedback_parts.append("Phone not added")

    # 4. Check Job Title - 20 pts
    # Can be in job_title, notes, or background_info
    expected_title = ground_truth.get('title', '').strip().lower()
    
    search_text = (
        str(db_state.get('job_title', '')) + " " + 
        str(db_state.get('notes', '')) + " " + 
        str(db_state.get('background_info', ''))
    ).lower()
    
    if expected_title and expected_title in search_text:
        score += 20
        feedback_parts.append("Job Title found")
    else:
        feedback_parts.append(f"Job Title not found (Expected: {expected_title})")

    # Pass Threshold: 80 points (Must get Name and Phone correct)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }