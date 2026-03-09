#!/usr/bin/env python3
"""
Verifier for bulk_lead_correction_via_loader task.
Checks if leads were updated correctly without being deleted/replaced.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_lead_correction(traj, env_info, task_info):
    """
    Verifies that the agent corrected the typos in the city field
    while preserving the original entry_date (proving an update was used).
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

    # Task Metadata
    metadata = task_info.get('metadata', {})
    target_phones = set(metadata.get('target_phones', [
        "2025550101", "2025550102", "2025550103", "2025550104", "2025550105"
    ]))
    correct_city = metadata.get('correct_city', "Washington")
    incorrect_city = metadata.get('incorrect_city', "Washingtun")
    
    # Preservation threshold: Entry date should be older than this task
    # The setup script sets entry_date to 2020-01-01.
    # If the agent re-imports (deletes and adds), entry_date will be today (e.g., 2024/2025).
    # So we check if entry_date < 2021-01-01.
    preservation_threshold = "2021-01-01"

    leads = result.get('leads', [])
    total_count = result.get('total_count', 0)

    score = 0
    feedback = []

    # 1. Check if records exist
    if not leads:
        return {"passed": False, "score": 0, "feedback": "No leads found in List 9999. Did you delete them?"}

    # Analyze specific target leads
    updated_correctly_count = 0
    preserved_history_count = 0
    typo_remaining_count = 0

    target_leads_found = [l for l in leads if l['phone_number'] in target_phones]

    for lead in target_leads_found:
        phone = lead['phone_number']
        city = lead['city']
        entry_date = lead['entry_date']

        # Check City
        if city.lower() == correct_city.lower():
            updated_correctly_count += 1
        elif city.lower() == incorrect_city.lower():
            typo_remaining_count += 1
        
        # Check History Preservation
        # Entry date format from MySQL usually "YYYY-MM-DD HH:MM:SS"
        try:
            e_date = str(entry_date).split(' ')[0] # Just get YYYY-MM-DD
            if e_date < preservation_threshold:
                preserved_history_count += 1
            else:
                feedback.append(f"Phone {phone}: Entry date changed to {e_date} (History lost)")
        except Exception:
             feedback.append(f"Phone {phone}: Could not parse date {entry_date}")

    # Scoring Calculation

    # Criterion 1: Typos Eliminated (40 pts)
    # If 0 typos remain among target leads
    if typo_remaining_count == 0:
        score += 40
    else:
        feedback.append(f"{typo_remaining_count} leads still have typos.")

    # Criterion 2: Correct Values Applied (30 pts)
    # Proportional score for setting "Washington"
    if len(target_phones) > 0:
        score += int(30 * (updated_correctly_count / len(target_phones)))

    # Criterion 3: History Preserved (20 pts)
    # Proportional score
    if len(target_phones) > 0:
        score += int(20 * (preserved_history_count / len(target_phones)))

    # Criterion 4: No Duplicates (10 pts)
    # We expect exactly 10 leads in the list (5 targets + 5 controls)
    # Or at least, no duplicates of the targets.
    # Simple check: Total count should be 10.
    if total_count == 10:
        score += 10
    else:
        feedback.append(f"Duplicate/Unexpected record count: {total_count} (Expected 10).")
        # If duplicates exist for targets, penalize heavily
        phones_in_db = [l['phone_number'] for l in leads]
        if len(phones_in_db) != len(set(phones_in_db)):
             feedback.append("Duplicate phone numbers detected in list.")

    # Final Pass/Fail
    passed = score >= 90
    
    if passed:
        feedback.append("Success: All leads updated correctly and history preserved.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }