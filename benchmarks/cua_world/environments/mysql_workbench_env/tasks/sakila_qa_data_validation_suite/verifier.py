#!/usr/bin/env python3
"""Verifier for sakila_qa_data_validation_suite task.

Task: Create a data quality validation suite (table + stored procedure)
to detect 5 specific types of data issues in Sakila, and export results.
"""

import json
import tempfile
import os
import logging
import time

logger = logging.getLogger(__name__)

def verify_sakila_qa_data_validation_suite(traj, env_info, task_info):
    """
    Verify the Sakila QA suite task.

    Scoring (100 points):
    - qa_test_results table exists with correct structure: 15 pts
    - sp_run_qa_suite procedure exists: 15 pts
    - Temporal violations detected (>= 5): 15 pts
    - Negative payments detected (>= 4): 15 pts
    - Invalid emails detected (>= 3): 10 pts
    - Zero rental duration detected (>= 3): 10 pts
    - Zero replacement cost detected (>= 2): 10 pts
    - CSV export created successfully: 10 pts

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/qa_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Get expected counts from metadata or defaults
    metadata = task_info.get('metadata', {}).get('checks', {})
    exp_temporal = metadata.get('temporal_violation_check', 5)
    exp_negative = metadata.get('negative_payment_check', 4)
    exp_email = metadata.get('invalid_email_check', 3)
    exp_duration = metadata.get('zero_rental_duration_check', 3)
    exp_cost = metadata.get('zero_replacement_cost_check', 2)

    # 1. Verify Table Structure (15 pts)
    table_exists = result.get('table_exists', 0)
    columns_match = result.get('columns_match_count', 0)
    # Expecting at least 6 specific columns
    if table_exists == 1 and columns_match >= 6:
        score += 15
        feedback_parts.append("Table 'qa_test_results' created correctly (15/15)")
    elif table_exists == 1:
        score += 5
        feedback_parts.append("Table 'qa_test_results' exists but missing columns (5/15)")
    else:
        feedback_parts.append("Table 'qa_test_results' NOT found (0/15)")

    # 2. Verify Procedure Existence (15 pts)
    if result.get('procedure_exists', 0) == 1:
        score += 15
        feedback_parts.append("Procedure 'sp_run_qa_suite' created (15/15)")
    else:
        feedback_parts.append("Procedure 'sp_run_qa_suite' NOT found (0/15)")

    # 3. Verify Check Results (10-15 pts each)
    # Parse the rows from the table data
    table_data = result.get('table_data', [])
    
    # Helper to find result for a check
    def find_check_result(name_keyword):
        for row in table_data:
            if name_keyword.lower() in row.get('test_name', '').lower():
                return row.get('records_found', 0), row.get('status', '').upper()
        return 0, 'NOT_FOUND'

    # Check 1: Temporal
    count, status = find_check_result('temporal')
    if count >= exp_temporal:
        score += 15
        feedback_parts.append(f"Temporal check passed ({count} records) (15/15)")
    else:
        feedback_parts.append(f"Temporal check failed (found {count}, expected {exp_temporal}) (0/15)")

    # Check 2: Negative Payment
    count, status = find_check_result('negative')
    if count >= exp_negative:
        score += 15
        feedback_parts.append(f"Negative payment check passed ({count} records) (15/15)")
    else:
        feedback_parts.append(f"Negative payment check failed (found {count}, expected {exp_negative}) (0/15)")
        
    # Check 3: Invalid Email
    count, status = find_check_result('email')
    if count >= exp_email:
        score += 10
        feedback_parts.append(f"Email check passed ({count} records) (10/10)")
    else:
        feedback_parts.append(f"Email check failed (found {count}, expected {exp_email}) (0/10)")

    # Check 4: Zero Duration
    count, status = find_check_result('duration')
    if count >= exp_duration:
        score += 10
        feedback_parts.append(f"Duration check passed ({count} records) (10/10)")
    else:
        feedback_parts.append(f"Duration check failed (found {count}, expected {exp_duration}) (0/10)")

    # Check 5: Zero Cost
    count, status = find_check_result('cost')
    if count >= exp_cost:
        score += 10
        feedback_parts.append(f"Cost check passed ({count} records) (10/10)")
    else:
        feedback_parts.append(f"Cost check failed (found {count}, expected {exp_cost}) (0/10)")

    # 4. Verify CSV Export (10 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    csv_mtime = result.get('csv_mtime', 0)
    task_start = result.get('task_start', 0)

    if csv_exists and csv_rows >= 5 and int(csv_mtime) > task_start:
        score += 10
        feedback_parts.append("CSV exported successfully (10/10)")
    elif csv_exists:
        feedback_parts.append(f"CSV exists but stale or empty ({csv_rows} rows) (0/10)")
    else:
        feedback_parts.append("CSV export NOT found (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }