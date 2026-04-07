#!/usr/bin/env python3
"""
Verifier for create_conversion_rate task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_conversion_rate(traj, env_info, task_info):
    """
    Verify the currency conversion rate was created correctly.
    """
    # 1. Setup: Load data using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_multiply = metadata.get('expected_multiply_rate', 1.085)
    tolerance = metadata.get('rate_tolerance', 0.001)
    expected_from = metadata.get('expected_currency_from', 'EUR')
    expected_to = metadata.get('expected_currency_to', 'USD')
    expected_type = metadata.get('expected_type', 'Spot')
    expected_valid_from = metadata.get('expected_valid_from', '2025-01-01')
    expected_valid_to = metadata.get('expected_valid_to', '2025-12-31')

    # Read result file
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

    # 2. Extract Data
    record_found = result.get('record_found', False)
    details = result.get('record_details', {})
    meta = result.get('meta', {})
    
    score = 0
    feedback_parts = []
    
    # CRITERION 1: Record Existence (20 pts) - MANDATORY
    if not record_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No conversion rate record found for EUR->USD."
        }
    score += 20
    feedback_parts.append("Record found")

    # CRITERION 2: Rate Accuracy (20 pts)
    actual_rate = details.get('multiply_rate', 0)
    if abs(actual_rate - expected_multiply) <= tolerance:
        score += 20
        feedback_parts.append(f"Rate correct ({actual_rate})")
    else:
        feedback_parts.append(f"Rate incorrect (expected {expected_multiply}, got {actual_rate})")

    # CRITERION 3: Date Range (20 pts)
    # Check if dates match exactly or cover the range
    act_valid_from = details.get('valid_from', '')
    act_valid_to = details.get('valid_to', '')
    
    # Simple string comparison for ISO dates YYYY-MM-DD
    if act_valid_from <= expected_valid_from and act_valid_to >= expected_valid_to:
        score += 20
        feedback_parts.append(f"Date range correct ({act_valid_from} to {act_valid_to})")
    else:
        feedback_parts.append(f"Date range incorrect (expected full 2025, got {act_valid_from} to {act_valid_to})")

    # CRITERION 4: Conversion Type (15 pts)
    act_type = details.get('conversion_type', '')
    if expected_type.lower() in act_type.lower():
        score += 15
        feedback_parts.append(f"Type correct ({act_type})")
    else:
        feedback_parts.append(f"Type incorrect (expected {expected_type}, got {act_type})")

    # CRITERION 5: Anti-Gaming / Freshness (15 pts)
    is_new = meta.get('is_newly_created', False)
    if is_new:
        score += 15
        feedback_parts.append("Record created during task")
    else:
        feedback_parts.append("Record creation timestamp predates task start (stale data)")

    # CRITERION 6: Divide Rate sanity check (10 pts)
    # Divide rate should be inverse of multiply rate
    div_rate = details.get('divide_rate', 0)
    if actual_rate > 0 and abs(div_rate - (1/actual_rate)) < 0.01:
        score += 10
        feedback_parts.append("Divide rate auto-calculated correctly")
    else:
        feedback_parts.append("Divide rate calculation inconsistent")

    passed = score >= 70 and record_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }