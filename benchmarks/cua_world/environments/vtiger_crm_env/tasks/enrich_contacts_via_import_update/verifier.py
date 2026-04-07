#!/usr/bin/env python3
"""
Verifier for enrich_contacts_via_import_update task.

Checks:
1. Contact Count Check (CRITICAL): Asserts that no duplicates were created. (current_count == initial_count)
2. Value Checks: For the 10 target emails, validates that Title and Phone match expected enriched data.
3. Timestamp Check: Validates that modifiedtime > task_start_time to ensure work was actually done.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enrich_contacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_updates = metadata.get('expected_updates', {})

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/enrich_contacts_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start_time = result.get('task_start_time', 0)
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    contacts_data = result.get('contacts_data', [])

    # Group the returned data by email to easily check for duplicates and map values
    extracted_records = {}
    duplicates_detected_in_query = False
    for row in contacts_data:
        email = row.get('email')
        if email in extracted_records:
            duplicates_detected_in_query = True
        extracted_records.setdefault(email, []).append(row)

    # -------------------------------------------------------------------------
    # CRITERION 1: Duplicate Prevention (25 points)
    # -------------------------------------------------------------------------
    no_duplicates = (current_count == initial_count) and not duplicates_detected_in_query
    
    if current_count > initial_count or duplicates_detected_in_query:
        feedback_parts.append(f"❌ FAILED Duplicate Check: Contact count increased from {initial_count} to {current_count}. You performed an Insert instead of an Update.")
        duplicate_penalty = True
    else:
        score += 25
        feedback_parts.append(f"✅ Duplicate Prevention Passed (Count remained {initial_count})")
        duplicate_penalty = False

    # -------------------------------------------------------------------------
    # CRITERIA 2-4: Title Updates, Phone Updates, Modification Timestamps
    # -------------------------------------------------------------------------
    titles_correct = 0
    phones_correct = 0
    timestamps_correct = 0
    total_expected = len(expected_updates)

    for email, expected in expected_updates.items():
        records = extracted_records.get(email, [])
        if not records:
            continue
            
        # If duplicates exist, evaluate the most recently modified one
        record = sorted(records, key=lambda x: x.get('modifiedtime', 0), reverse=True)[0]
        
        # Check Title (3 pts per record)
        if record.get('title') == expected.get('title'):
            titles_correct += 1
            score += 3
            
        # Check Phone (3 pts per record)
        if record.get('phone') == expected.get('phone'):
            phones_correct += 1
            score += 3
            
        # Check Timestamp (1.5 pts per record)
        if record.get('modifiedtime', 0) >= task_start_time:
            timestamps_correct += 1
            score += 1.5

    feedback_parts.append(f"Titles Updated: {titles_correct}/{total_expected}")
    feedback_parts.append(f"Phones Updated: {phones_correct}/{total_expected}")
    feedback_parts.append(f"Records Touched: {timestamps_correct}/{total_expected}")

    # Deduct heavy penalty if they failed the core premise (duplicate check)
    # Even if they mapped perfectly, inserting defeats the goal of a data enrichment task.
    if duplicate_penalty:
        score = min(score, 50) # Cap maximum score at 50 if they created duplicates
        feedback_parts.append("Score capped at 50 due to duplicate record creation.")

    passed = (score >= 70) and no_duplicates

    return {
        "passed": passed,
        "score": min(int(score), 100),
        "feedback": " | ".join(feedback_parts),
        "details": {
            "initial_count": initial_count,
            "current_count": current_count,
            "titles_correct": titles_correct,
            "phones_correct": phones_correct,
            "timestamps_correct": timestamps_correct,
            "duplicates_created": not no_duplicates
        }
    }