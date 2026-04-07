#!/usr/bin/env python3
"""
Verifier for Sakila Customer Email Recovery Task

Verifies that:
1. All NULL emails in `customer` table are gone.
2. Store 2 emails match the expected format (First.Last@sakilacustomer.org).
3. Store 1 emails were untouched (integrity check).
4. An output CSV was created with the recovered data.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_customer_email_recovery(traj, env_info, task_info):
    """
    Verify the database recovery task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/recovery_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Zero NULLs (30 pts)
    nulls_remaining = result.get("null_emails_remaining", 999)
    if nulls_remaining == 0:
        score += 30
        feedback_parts.append("All missing emails restored (30/30)")
    else:
        feedback_parts.append(f"Failed: {nulls_remaining} customers still have NULL emails (0/30)")

    # 2. Data Accuracy (30 pts)
    # Checked by verifying email matches 'First.Last@sakilacustomer.org'
    accuracy_failures = result.get("store2_accuracy_failures", 999)
    if accuracy_failures == 0:
        score += 30
        feedback_parts.append("Restored data is accurate (30/30)")
    elif accuracy_failures < 20:
        score += 15
        feedback_parts.append(f"Partial accuracy: {accuracy_failures} incorrect records (15/30)")
    else:
        feedback_parts.append(f"Data incorrect: {accuracy_failures} records mismatch expected values (0/30)")

    # 3. Store 1 Integrity (10 pts)
    # Ensure the user didn't accidentally update Store 1 or break it
    s1_nulls = result.get("store1_nulls", 0)
    s1_invalid = result.get("store1_invalid_format", 0)
    if s1_nulls == 0 and s1_invalid == 0:
        score += 10
        feedback_parts.append("Store #1 data integrity preserved (10/10)")
    else:
        feedback_parts.append("Store #1 data was damaged (0/10)")

    # 4. Export File (20 pts total)
    csv_exists = result.get("csv_exists", False)
    csv_fresh = result.get("csv_created_during_task", False)
    csv_rows = result.get("csv_rows", 0)

    if csv_exists and csv_fresh:
        score += 10
        feedback_parts.append("Export file created (10/10)")
        
        # Check row count (Store 2 has ~273 customers)
        if 250 <= csv_rows <= 300:
            score += 10
            feedback_parts.append(f"Export row count correct: {csv_rows} (10/10)")
        else:
            feedback_parts.append(f"Export row count suspicious: {csv_rows} (0/10)")
    else:
        feedback_parts.append("Export file missing or not created during task (0/20)")

    # 5. Process Evidence (10 pts)
    # Did they create a staging table?
    if result.get("staging_table_detected", False):
        score += 10
        feedback_parts.append("Staging table detected (10/10)")
    else:
        # If they did it purely via SQL without a staging table (e.g. LOAD DATA LOCAL INFILE to var), 
        # it's harder to detect, but less likely given the difficulty.
        # We'll grant points if score is already high (implicit success)
        if score >= 70:
            score += 10
            feedback_parts.append("Implicit process success (10/10)")
        else:
            feedback_parts.append("No staging table detected (0/10)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }