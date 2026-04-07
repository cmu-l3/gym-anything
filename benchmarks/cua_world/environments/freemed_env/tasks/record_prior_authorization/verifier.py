#!/usr/bin/env python3
"""
Verifier for record_prior_authorization task.

Uses robust database-level checks reading from the post-task export payload.
Verifies multi-faceted dimensions: Record increment, exact value matching, 
and text-blob parsing for unstructured comment data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_prior_authorization(traj, env_info, task_info):
    # Enforce use of framework's copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely load the exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Pull baseline metadata expectations
    metadata = task_info.get('metadata', {})
    expected_authnum = metadata.get('expected_authnum', 'AUTH-2025-KMR-90412')
    expected_start = metadata.get('expected_start_date', '2025-01-15')
    expected_end = metadata.get('expected_end_date', '2025-07-15')

    score = 0
    feedback = []

    auth_found = result.get('auth_found', False)
    auth_record = result.get('auth_record', {})
    target_patient_id = result.get('target_patient_id', '0')
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)

    # 1. Anti-gaming check: Did the record count actually increase? (10 pts)
    if current_count > initial_count:
        score += 10
        feedback.append("Record count increased (+10)")
    else:
        feedback.append("Record count did not increase (Agent may have edited an existing unrelated record or done nothing)")

    # 2. Authorization Base Record Exists (20 points)
    if auth_found:
        score += 20
        feedback.append("Authorization record found (+20)")

        # 3. Linked to Target Patient (20 points)
        if str(auth_record.get('authpatient')) == str(target_patient_id):
            score += 20
            feedback.append("Correct patient linked (+20)")
        else:
            feedback.append(f"Incorrect patient ID: expected {target_patient_id}, got {auth_record.get('authpatient')}")

        # 4. Authorization Number Verification (20 points)
        if str(auth_record.get('authnum', '')).strip().lower() == expected_authnum.lower():
            score += 20
            feedback.append("Authorization number correct (+20)")
        else:
            feedback.append(f"Incorrect auth number: {auth_record.get('authnum')}")

        # 5. Start Date Parsing (10 points)
        # Using `in` keyword ensures that if time data is appended in FreeMED schema (e.g. 2025-01-15 00:00:00), we don't inappropriately fail
        if expected_start in str(auth_record.get('authdtbegin', '')):
            score += 10
            feedback.append("Start date correct (+10)")
        else:
            feedback.append(f"Incorrect start date: {auth_record.get('authdtbegin')}")

        # 6. End Date Parsing (10 points)
        if expected_end in str(auth_record.get('authdtend', '')):
            score += 10
            feedback.append("End date correct (+10)")
        else:
            feedback.append(f"Incorrect end date: {auth_record.get('authdtend')}")

        # 7. Unstructured Comment Evaluation (10 points)
        # Looks for presence of core elements in the unstructured text blob
        full_text = auth_record.get('full_text', '').lower()
        has_knee = 'knee' in full_text
        has_mri = 'mri' in full_text
        has_bluecross = 'bluecross' in full_text or 'blue cross' in full_text
        has_cpt = '73721' in full_text

        matches = sum([has_knee, has_mri, has_bluecross, has_cpt])
        if matches >= 2:
            score += 10
            feedback.append("Comment contains sufficient expected keywords (+10)")
        else:
            feedback.append("Comment missing expected keywords")
            
    else:
        feedback.append("Authorization record NOT found in database")

    # Hard Gates to Pass the Evaluation
    # Agent must have successfully created the record AND linked it to the correct patient to consider the task 'Passed'
    key_criteria_met = auth_found and (str(auth_record.get('authpatient')) == str(target_patient_id))
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }