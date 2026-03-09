#!/usr/bin/env python3
"""
Verifier for create_provider_account task.

Verifies that the new provider user was created in the database with the
correct credentials, identification numbers, and authorization status.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_provider_account(traj, env_info, task_info):
    """
    Verify the creation of the provider account via database inspection.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('expected_fname', 'Sarah')
    expected_lname = metadata.get('expected_lname', 'Chen')
    expected_npi = metadata.get('expected_npi', '1538246790')
    expected_taxid = metadata.get('expected_taxid', '45-2837196')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Scoring Logic ---

    # 1. User Record Exists (15 pts)
    if result.get('user_exists'):
        score += 15
        feedback_parts.append("User record created")
    else:
        return {"passed": False, "score": 0, "feedback": "User 'schen' not found in database"}

    fields = result.get('fields', {})

    # 2. First Name (10 pts)
    if fields.get('fname') == expected_fname:
        score += 10
    else:
        feedback_parts.append(f"Incorrect First Name: {fields.get('fname')}")

    # 3. Last Name (10 pts)
    if fields.get('lname') == expected_lname:
        score += 10
    else:
        feedback_parts.append(f"Incorrect Last Name: {fields.get('lname')}")

    # 4. Middle Name (5 pts)
    if fields.get('mname') == 'L':
        score += 5
    else:
        feedback_parts.append(f"Incorrect Middle Name: {fields.get('mname')}")

    # 5. NPI (15 pts)
    if fields.get('npi') == expected_npi:
        score += 15
    else:
        feedback_parts.append(f"Incorrect NPI: {fields.get('npi')}")

    # 6. Tax ID (10 pts) - handle potential formatting differences
    actual_tax = fields.get('federaltaxid', '')
    if actual_tax == expected_taxid or actual_tax == expected_taxid.replace('-', ''):
        score += 10
    else:
        feedback_parts.append(f"Incorrect Tax ID: {actual_tax}")

    # 7. Authorized (15 pts) - Critical for providers
    # DB usually stores as 1 or '1'
    auth_val = str(fields.get('authorized', '0'))
    if auth_val == '1':
        score += 15
    else:
        feedback_parts.append("User not marked as Authorized provider")

    # 8. Specialty (5 pts)
    # Case insensitive partial match
    actual_specialty = fields.get('specialty', '').lower()
    if 'family' in actual_specialty:
        score += 5
    else:
        feedback_parts.append(f"Incorrect Specialty: {fields.get('specialty')}")

    # 9. Password Entry Exists (10 pts)
    if result.get('secure_entry_exists'):
        score += 10
    else:
        feedback_parts.append("Password not set (missing users_secure entry)")

    # 10. Anti-Gaming: Count Increased (5 pts)
    if result.get('counts', {}).get('increased'):
        score += 5
    else:
        feedback_parts.append("User count did not increase (overwrite?)")

    # Final Evaluation
    # Pass threshold: 70 points
    passed = score >= 70
    
    if not feedback_parts:
        feedback_parts.append("Perfect execution")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }