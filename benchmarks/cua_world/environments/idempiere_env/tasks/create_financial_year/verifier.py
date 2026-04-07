#!/usr/bin/env python3
"""
Verifier for create_financial_year task.

Scoring Criteria:
1. Year Record Exists (30 pts)
2. Linked to 'Standard' Calendar (20 pts)
3. Correct Number of Periods (12) (40 pts)
4. Anti-Gaming (Created after start) (10 pts)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_financial_year(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
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

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    # Extract data
    year_exists = result.get('year_exists', False)
    calendar_name = result.get('calendar_name', '')
    period_count = int(result.get('period_count', 0))
    created_ts = float(result.get('created_timestamp', 0))
    task_start = float(result.get('task_start_time', 0))

    # Criterion 1: Year Exists
    if year_exists:
        score += 30
        feedback_parts.append("Year 2030 record created")
    else:
        feedback_parts.append("Year 2030 record NOT found")
        return {"passed": False, "score": 0, "feedback": "Year record not created"}

    # Criterion 2: Correct Calendar
    if calendar_name == 'Standard':
        score += 20
        feedback_parts.append("Linked to 'Standard' calendar")
    else:
        feedback_parts.append(f"Wrong calendar: {calendar_name} (expected 'Standard')")

    # Criterion 3: Period Count (Process Execution)
    if period_count == 12:
        score += 40
        feedback_parts.append("All 12 periods generated successfully")
    elif period_count > 0:
        # Partial credit if some periods exist but not 12
        score += 20
        feedback_parts.append(f"Incomplete periods generated: {period_count}/12")
    else:
        feedback_parts.append("No periods generated (Process not run?)")

    # Criterion 4: Anti-Gaming (Creation Time)
    if created_ts > task_start:
        score += 10
        feedback_parts.append("Record created during task session")
    else:
        feedback_parts.append("Record appears to differ from session time (pre-existing?)")

    # Final result
    passed = score >= 90  # Strict pass: Must have year + standard cal + 12 periods
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }