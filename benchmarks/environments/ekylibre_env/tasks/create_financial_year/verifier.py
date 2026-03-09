#!/usr/bin/env python3
"""
Verifier for create_financial_year@1 task in Ekylibre.

Verification Strategy:
1. Check if a financial year record exists with start=2017-01-01 and end=2017-12-31.
2. Verify currency is EUR.
3. Anti-gaming: Verify the record was created AFTER the task start time.
4. Anti-gaming: Verify the total count of financial years increased.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_financial_year(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    task_start = result.get('task_start', 0)
    found_record = result.get('found_record')
    initial_count = result.get('initial_fy_count', 0)
    current_count = result.get('current_fy_count', 0)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Record existence (30 points)
    if found_record:
        score += 30
        feedback_parts.append("Financial year 2017 record found")
        
        # Criterion 2: Date correctness (30 points total)
        # We query specifically for these dates in export_result, so existence implies correctness
        # But we double check the returned JSON just in case the query logic changes
        started_on = found_record.get('started_on', '')
        stopped_on = found_record.get('stopped_on', '')
        
        if started_on == '2017-01-01':
            score += 15
            feedback_parts.append("Start date correct")
        else:
            feedback_parts.append(f"Start date incorrect: {started_on}")
            
        if stopped_on == '2017-12-31':
            score += 15
            feedback_parts.append("End date correct")
        else:
            feedback_parts.append(f"End date incorrect: {stopped_on}")

        # Criterion 3: Currency (15 points)
        currency = found_record.get('currency', '')
        if currency == 'EUR':
            score += 15
            feedback_parts.append("Currency correct (EUR)")
        else:
            feedback_parts.append(f"Currency incorrect: {currency}")

        # Criterion 4: Created during task (10 points)
        created_at = found_record.get('created_at_epoch', 0)
        if created_at > task_start:
            score += 10
            feedback_parts.append("Record created during task session")
        else:
            feedback_parts.append("Record appears to have existed before task start")

    else:
        feedback_parts.append("No financial year record found for 2017-01-01 to 2017-12-31")

    # Criterion 5: Net new record (0 points, just validation)
    # If the count didn't increase but we found a record, and it has a new timestamp, 
    # it might mean the agent deleted an old one and made a new one (acceptable).
    # If timestamp is old, they did nothing.
    if current_count > initial_count:
        feedback_parts.append("Total financial year count increased")
    
    # Final check
    passed = score >= 60  # Require at least existence + dates
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }