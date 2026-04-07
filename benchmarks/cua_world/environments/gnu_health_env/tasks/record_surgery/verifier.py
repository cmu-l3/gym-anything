#!/usr/bin/env python3
"""
Verifier for record_surgery task.

This task assesses the agent's ability to create a surgical record in GNU Health.
Scoring breakdown (100 points total):
  - 25 pts: A new surgery record was created (count increased)
  - 25 pts: The record is correctly linked to patient Ana Betz
  - 15 pts: Surgery date matches 2025-01-15
  - 15 pts: Description contains "appendectomy"
  - 10 pts: Classification is set to Urgent ('u')
  - 10 pts: Notes contain relevant operative details

Pass threshold: score >= 50
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_record_surgery(traj, env_info, task_info):
    """Verify surgery recording for patient Ana Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    
    score = 0
    feedback_parts = []
    subscores = {}

    expected_date = metadata.get('expected_date', '2025-01-15')
    expected_desc_keyword = metadata.get('expected_description_keyword', 'appendectomy').lower()
    expected_classes = [c.lower() for c in metadata.get('expected_classification', ['u', 'urgent'])]
    expected_notes_keywords = [k.lower() for k in metadata.get('expected_notes_keywords', ['appendicitis', 'laparoscopic'])]

    # --- Copy result JSON from VM ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/record_surgery_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    # Extract info
    surgery_found = result.get('surgery_found', False)
    any_new_surgery_count = result.get('any_new_surgery_count', 0)
    
    try:
        any_new_surgery_count = int(any_new_surgery_count)
    except (ValueError, TypeError):
        any_new_surgery_count = 0

    surg_data = result.get('surgery', {})
    surg_desc = surg_data.get('description', '').lower()
    surg_date = surg_data.get('date', '')
    surg_class = surg_data.get('classification', '').lower()
    surg_notes = surg_data.get('notes', '').lower()

    # --- Criterion 1: Record Created (25 pts) ---
    if surgery_found or any_new_surgery_count > 0:
        score += 25
        subscores['record_created'] = 25
        feedback_parts.append("Surgery record successfully created")
    else:
        subscores['record_created'] = 0
        feedback_parts.append("MISSING: No new surgery record was created")
        
        # Fast fail if nothing was created
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # --- Criterion 2: Correct Patient (25 pts) ---
    if surgery_found:
        score += 25
        subscores['correct_patient'] = 25
        feedback_parts.append("Record correctly linked to Ana Betz")
    else:
        subscores['correct_patient'] = 0
        feedback_parts.append("Surgery record created but NOT linked to Ana Betz")
        
        # No point continuing specific checks if it's the wrong patient
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # --- Criterion 3: Correct Date (15 pts) ---
    if surg_date == expected_date:
        score += 15
        subscores['correct_date'] = 15
        feedback_parts.append(f"Surgery date correct ({expected_date})")
    elif surg_date:
        subscores['correct_date'] = 0
        feedback_parts.append(f"Incorrect surgery date: {surg_date}")
    else:
        subscores['correct_date'] = 0
        feedback_parts.append("Surgery date was not set")

    # --- Criterion 4: Description (15 pts) ---
    if expected_desc_keyword in surg_desc:
        score += 15
        subscores['correct_description'] = 15
        feedback_parts.append("Description contains 'appendectomy'")
    elif surg_desc:
        score += 7  # Partial credit for putting *something*
        subscores['correct_description'] = 7
        feedback_parts.append("Description filled but missing expected keyword")
    else:
        subscores['correct_description'] = 0
        feedback_parts.append("Description is empty")

    # --- Criterion 5: Classification (10 pts) ---
    if surg_class in expected_classes:
        score += 10
        subscores['correct_classification'] = 10
        feedback_parts.append("Classification correctly set to Urgent")
    else:
        subscores['correct_classification'] = 0
        feedback_parts.append(f"Classification incorrect or missing (got: '{surg_class}')")

    # --- Criterion 6: Operative Notes (10 pts) ---
    found_keywords = [k for k in expected_notes_keywords if k in surg_notes]
    if len(found_keywords) == len(expected_notes_keywords):
        score += 10
        subscores['correct_notes'] = 10
        feedback_parts.append("Operative notes contain all expected keywords")
    elif len(found_keywords) > 0:
        score += 5
        subscores['correct_notes'] = 5
        feedback_parts.append(f"Operative notes partially complete (found: {', '.join(found_keywords)})")
    elif surg_notes:
        score += 2
        subscores['correct_notes'] = 2
        feedback_parts.append("Notes filled but missing key operative details")
    else:
        subscores['correct_notes'] = 0
        feedback_parts.append("Extra info / notes are empty")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }