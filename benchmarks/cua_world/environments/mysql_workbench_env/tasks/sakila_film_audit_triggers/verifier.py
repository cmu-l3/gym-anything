#!/usr/bin/env python3
"""
Verifier for sakila_film_audit_triggers task.

Verifies:
1. Audit table schema creation
2. Insert/Update/Delete trigger creation
3. Correct execution of test operations (via audit log content)
4. CSV export of the audit log
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sakila_film_audit_triggers(traj, env_info, task_info):
    """
    Verify the creation of audit triggers and the resulting log data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Table Creation (15 pts)
    if result.get("table_exists", 0) == 1 and result.get("columns_check", 0) == 1:
        score += 15
        feedback_parts.append("Audit table created correctly (15/15)")
    elif result.get("table_exists", 0) == 1:
        score += 10
        feedback_parts.append("Audit table created but missing required columns (10/15)")
    else:
        feedback_parts.append("Audit table missing (0/15)")

    # 2. Trigger Creation (15 pts each = 45 pts total)
    # Insert Trigger
    if result.get("trg_insert_exists", 0) == 1:
        score += 15
        feedback_parts.append("Insert trigger created (15/15)")
    else:
        feedback_parts.append("Insert trigger missing (0/15)")
    
    # Update Trigger
    if result.get("trg_update_exists", 0) == 1:
        score += 15
        feedback_parts.append("Update trigger created (15/15)")
    else:
        feedback_parts.append("Update trigger missing (0/15)")

    # Delete Trigger
    if result.get("trg_delete_exists", 0) == 1:
        score += 15
        feedback_parts.append("Delete trigger created (15/15)")
    else:
        feedback_parts.append("Delete trigger missing (0/15)")

    # 3. Validation of Audit Logic via Log Content (10 pts each = 30 pts total)
    # Logic: If the log contains the correct row, the trigger fired AND the user ran the test command.
    
    # Insert Audit
    if result.get("log_insert_found", 0) >= 1:
        score += 10
        feedback_parts.append("Insert audit logged (10/10)")
    else:
        feedback_parts.append("Insert action not found in log (0/10)")

    # Update Audit
    # Also verify the side effect (film 1 rate changed)
    film_rate = str(result.get("film_1_rate", "0"))
    if result.get("log_update_found", 0) >= 1 and ("1.99" in film_rate):
        score += 10
        feedback_parts.append("Update audit logged (10/10)")
    elif result.get("log_update_found", 0) >= 1:
         score += 5
         feedback_parts.append("Update logged but value mismatch in table (5/10)")
    else:
        feedback_parts.append("Update action not found in log (0/10)")

    # Delete Audit
    if result.get("log_delete_found", 0) >= 1 and result.get("test_film_exists", 1) == 0:
        score += 10
        feedback_parts.append("Delete audit logged (10/10)")
    else:
        feedback_parts.append("Delete action not found in log (0/10)")

    # 4. CSV Export (10 pts)
    # Must exist, be created during task, and have content (header + at least 1 row)
    task_start = result.get("task_start", 0)
    csv_mtime = result.get("csv_mtime", 0)
    csv_rows = result.get("csv_rows", 0)
    csv_exists = result.get("csv_exists", False)

    if csv_exists and csv_rows >= 2 and csv_mtime > task_start:
        score += 10
        feedback_parts.append(f"CSV exported successfully with {csv_rows} rows (10/10)")
    elif csv_exists and csv_rows >= 2:
        score += 5
        feedback_parts.append("CSV exists but timestamp check inconclusive (5/10)")
    else:
        feedback_parts.append("CSV export missing or empty (0/10)")

    # Final check
    passed = score >= 60 and result.get("table_exists", 0) == 1

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }