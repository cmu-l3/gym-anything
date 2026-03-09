#!/usr/bin/env python3
"""
Verifier for chinook_inactive_purge task.

Scoring Breakdown (100 pts total):
1. Connection (10 pts): DBeaver connection 'Chinook' exists.
2. Report Generation (35 pts):
   - CSV exists (10)
   - Columns correct (10)
   - Row count matches expected inactive count (15)
3. Database Purge (50 pts):
   - Inactive customers removed (15)
   - Active customers preserved (15)
   - Referential Integrity: No orphan invoices (10)
   - Referential Integrity: No orphan items (10)
4. Artifacts (5 pts):
   - SQL script saved (5)

Pass Threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_inactive_purge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/purge_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Connection (10 pts)
    if result.get("connection_exists", False):
        score += 10
        feedback.append("DBeaver connection 'Chinook' detected.")
    else:
        feedback.append("DBeaver connection 'Chinook' NOT found.")

    # 2. Report Generation (35 pts)
    expected_inactive = result.get("expected_inactive_count", 0)
    csv_rows = result.get("csv_row_count", 0)
    
    if result.get("csv_exists", False):
        score += 10
        feedback.append("Export file found.")
        
        if result.get("csv_columns_valid", False):
            score += 10
            feedback.append("CSV columns validated.")
        else:
            feedback.append(f"CSV missing required columns. Headers found: {result.get('csv_headers')}")

        # Row count tolerance +/- 1 (header issues usually cause off-by-one)
        if abs(csv_rows - expected_inactive) <= 1:
            score += 15
            feedback.append(f"CSV row count matches expected inactive users ({csv_rows}).")
        else:
            feedback.append(f"CSV row count mismatch. Expected ~{expected_inactive}, got {csv_rows}.")
    else:
        feedback.append("Export file NOT found.")

    # 3. Database Purge (50 pts)
    # Check Inactive Removal (False Negatives)
    if result.get("sample_inactive_still_exists", 1) == 0:
        score += 15
        feedback.append("Inactive customers successfully deleted.")
    else:
        feedback.append("Inactive customers still exist in database.")

    # Check Active Preservation (False Positives)
    if result.get("sample_active_still_exists", 0) == 1:
        score += 15
        feedback.append("Active customers preserved.")
    else:
        feedback.append("CRITICAL: Active customers were incorrectly deleted.")

    # Check Integrity (Orphans)
    orphan_invoices = result.get("orphan_invoices", -1)
    orphan_items = result.get("orphan_items", -1)

    if orphan_invoices == 0:
        score += 10
        feedback.append("Referential Integrity maintained: No orphan invoices.")
    elif orphan_invoices > 0:
        feedback.append(f"Integrity Violated: {orphan_invoices} orphan invoices found.")

    if orphan_items == 0:
        score += 10
        feedback.append("Referential Integrity maintained: No orphan invoice items.")
    elif orphan_items > 0:
        feedback.append(f"Integrity Violated: {orphan_items} orphan invoice items found.")

    # 4. Artifacts (5 pts)
    if result.get("script_exists", False):
        score += 5
        feedback.append("SQL script file saved.")
    else:
        feedback.append("SQL script file NOT found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }