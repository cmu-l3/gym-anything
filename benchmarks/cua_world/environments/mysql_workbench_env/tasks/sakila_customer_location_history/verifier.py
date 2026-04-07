#!/usr/bin/env python3
"""
Verifier for Sakila Customer Location History (SCD Type 2) task.

Verifies:
1. Schema changes (History table structure)
2. Data migration (Backfill of existing customers)
3. Business logic (Trigger creation and functionality)
4. Verification test (Manual test by agent + Automated test by verifier)
5. Evidence export (CSV file)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_customer_location_history(traj, env_info, task_info):
    """
    Verify the implementation of SCD2 history tracking.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load result from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/scd2_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Structure Verification (20 pts)
    # Table must exist and have valid_from/valid_to columns
    if result.get('table_exists', 0) == 1 and result.get('columns_check', 0) >= 3:
        score += 20
        feedback_parts.append("History table structure correct (20/20)")
    elif result.get('table_exists', 0) == 1:
        score += 10
        feedback_parts.append("History table exists but missing required columns (10/20)")
    else:
        feedback_parts.append("History table NOT found (0/20)")

    # 2. Initial Data Backfill (20 pts)
    # Should have ~599 rows (or more if they did updates)
    backfill_count = result.get('backfill_count', 0)
    if backfill_count >= 599:
        score += 20
        feedback_parts.append(f"Data backfill successful: {backfill_count} rows (20/20)")
    elif backfill_count > 0:
        score += 10
        feedback_parts.append(f"Partial backfill: {backfill_count} rows (10/20)")
    else:
        feedback_parts.append("Table is empty (0/20)")

    # 3. Trigger Creation (20 pts)
    if result.get('trigger_exists', 0) == 1:
        score += 20
        feedback_parts.append("Trigger created successfully (20/20)")
    else:
        feedback_parts.append("Trigger NOT found (0/20)")

    # 4. Trigger Logic Verification (30 pts total)
    # Part A: Agent's manual test (Mary Smith) - 15 pts
    # Part B: Automated verifier test (Customer 100) - 15 pts
    
    # Part A: Mary Smith (ID 1)
    mary_count = result.get('mary_history_count', 0)
    mary_addr = result.get('mary_current_address', 0)
    
    if mary_count >= 2 and mary_addr == 20:
        score += 15
        feedback_parts.append("Manual test (Mary Smith) verified (15/15)")
    elif mary_count >= 2:
        score += 10
        feedback_parts.append("Mary Smith has history but wrong current address (10/15)")
    else:
        feedback_parts.append(f"Manual test failed: Mary Smith has {mary_count} history records (0/15)")

    # Part B: Automated Verification
    if result.get('automated_verify_passed', False):
        score += 15
        feedback_parts.append("Automated trigger logic test passed (15/15)")
    else:
        feedback_parts.append("Automated trigger logic test FAILED - trigger logic may be incorrect (0/15)")

    # 5. Export Verification (10 pts)
    if result.get('csv_exists', False):
        rows = result.get('csv_rows', 0)
        if rows >= 2:
            score += 10
            feedback_parts.append("CSV export verified (10/10)")
        else:
            score += 5
            feedback_parts.append(f"CSV export exists but has few rows: {rows} (5/10)")
    else:
        feedback_parts.append("CSV export NOT found (0/10)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }