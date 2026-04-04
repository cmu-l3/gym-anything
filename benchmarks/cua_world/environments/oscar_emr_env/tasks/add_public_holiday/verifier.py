#!/usr/bin/env python3
"""
Verifier for Add Public Holiday task in OSCAR EMR.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_public_holiday(traj, env_info, task_info):
    """
    Verify that the 'Victoria Day' holiday was added for 2026-05-18.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('holiday_name', 'Victoria Day')
    expected_date = metadata.get('holiday_date', '2026-05-18')

    # Copy result JSON
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

    score = 0
    feedback_parts = []
    
    # Check 1: Record Found (50 pts)
    record_found = result.get('record_found', False)
    if record_found:
        score += 50
        feedback_parts.append("Holiday record found in database")
    else:
        feedback_parts.append("No holiday record found for the specified date")

    # Check 2: Name Correctness (30 pts)
    found_name = result.get('found_name', '')
    if record_found:
        if expected_name.lower() in found_name.lower():
            score += 30
            feedback_parts.append(f"Holiday name correct: '{found_name}'")
        else:
            score += 10 # Partial credit if date is right but name is weird
            feedback_parts.append(f"Holiday name mismatch: expected '{expected_name}', got '{found_name}'")

    # Check 3: Date Correctness (20 pts)
    # Implicitly checked by the query in export_result selecting by date, 
    # but we double check the returned value matches exactly.
    found_date = result.get('found_date', '')
    if record_found and found_date == expected_date:
        score += 20
        feedback_parts.append(f"Date confirmed: {found_date}")
    elif record_found:
        feedback_parts.append(f"Date format issue? Got {found_date}")

    # Pass logic
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }