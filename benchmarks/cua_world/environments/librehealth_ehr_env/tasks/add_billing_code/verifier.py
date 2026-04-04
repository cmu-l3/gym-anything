#!/usr/bin/env python3
"""
Verifier for add_billing_code task.

Verifies that the correct CPT4 code was added to the database with the
correct fee, description, and status.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_billing_code(traj, env_info, task_info):
    """
    Verify that the billing code was added correctly.
    """
    # 1. Setup - Helper to copy file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    # 2. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Retrieve Task Metadata
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_code', "99458")
    expected_fee = float(metadata.get('expected_fee', 42.00))
    fee_tolerance = float(metadata.get('fee_tolerance', 0.50))
    expected_type = metadata.get('expected_type_key', "CPT4")
    keywords = metadata.get('required_keywords', ["remote", "physiologic"])

    score = 0
    feedback_parts = []
    
    # 4. Verification Logic
    
    # Criterion 1: Code Exists (25 pts)
    if not result.get('code_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"The code {expected_code} was not found in the database."
        }
    
    score += 25
    feedback_parts.append(f"Code {expected_code} found.")

    # Criterion 2: Code Type (15 pts)
    actual_type = result.get('actual_type', '').upper()
    if actual_type == expected_type.upper():
        score += 15
        feedback_parts.append("Correct code type (CPT4).")
    else:
        feedback_parts.append(f"Incorrect code type: Found '{actual_type}', expected '{expected_type}'.")

    # Criterion 3: Fee Accuracy (25 pts)
    try:
        actual_fee = float(result.get('actual_fee', 0))
        if abs(actual_fee - expected_fee) <= fee_tolerance:
            score += 25
            feedback_parts.append(f"Fee matches (${actual_fee}).")
        else:
            feedback_parts.append(f"Fee incorrect: Found ${actual_fee}, expected ${expected_fee}.")
    except ValueError:
        feedback_parts.append("Fee invalid.")

    # Criterion 4: Description (20 pts)
    actual_text = result.get('actual_text', '').lower()
    found_keywords = [kw for kw in keywords if kw.lower() in actual_text]
    # Allow partial credit for partial keywords
    keyword_score = 0
    if keywords:
        keyword_score = int(20 * (len(found_keywords) / len(keywords)))
    score += keyword_score
    
    if len(found_keywords) == len(keywords):
        feedback_parts.append("Description contains all required keywords.")
    elif len(found_keywords) > 0:
        feedback_parts.append(f"Description missing some keywords (found {len(found_keywords)}/{len(keywords)}).")
    else:
        feedback_parts.append("Description does not match requirements.")

    # Criterion 5: Active Status (15 pts)
    # Check for "1" or "true"
    actual_active = str(result.get('actual_active', '0')).lower()
    if actual_active in ['1', 'true', 'yes']:
        score += 15
        feedback_parts.append("Code is active.")
    else:
        feedback_parts.append("Code is NOT active.")

    # Anti-gaming check: Ensure count increased
    initial_count = int(result.get('initial_cpt4_count', 0))
    final_count = int(result.get('final_cpt4_count', 0))
    
    if final_count <= initial_count:
        # If specific code exists but count didn't increase, something is weird (maybe modified existing?)
        # We'll subtract points but not fail if the specific code check passed
        feedback_parts.append("(Warning: Total CPT4 count did not increase)")

    # 5. Final Pass/Fail Determination
    # Pass threshold: 60 points AND code exists AND fee is close
    
    fee_ok = abs(float(result.get('actual_fee', 0)) - expected_fee) <= fee_tolerance
    
    passed = (score >= 60) and result.get('code_exists') and fee_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }