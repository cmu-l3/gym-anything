#!/usr/bin/env python3
"""
Verifier for comp_reconciliation_merge@1

Checks:
1. Audit table creation and structure.
2. Correct execution of MERGE logic:
   - Updates applied only where deviation > 10%.
   - Inserts applied for new records.
   - Non-qualifying records left untouched.
3. Report file generation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_comp_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    feedback = []

    # 1. Audit Table (20 pts)
    if result.get("audit_table_exists"):
        score += 8
        feedback.append("Audit table created.")
        if result.get("audit_columns_valid"):
            score += 7
            feedback.append("Audit columns correct.")
        if result.get("audit_row_count", 0) >= 10:
            score += 5
            feedback.append(f"Audit table populated ({result['audit_row_count']} rows).")
    else:
        feedback.append("Audit table missing.")

    # 2. Updates (25 pts)
    # 15 updates expected
    updates = result.get("group_a_updates_correct", 0)
    score += int((updates / 15) * 25)
    feedback.append(f"Salary updates: {updates}/15 correct.")

    # 3. Non-updates (15 pts)
    # 7 specific checks in export script, representing the 'unchanged' group
    unchanged = result.get("group_b_unchanged_correct", 0)
    # Export script checks 7 specific IDs, but logic applies to 17 total in that group. 
    # Logic in export checks a sample subset or all? Export checks 7 explicit IDs.
    # We'll score based on those 7.
    score += int((unchanged / 7) * 15)
    feedback.append(f"Unchanged records verified: {unchanged}/7.")

    # 4. Inserts (15 pts)
    # 8 inserts expected
    inserts = result.get("group_c_inserts_correct", 0)
    score += int((inserts / 8) * 15)
    feedback.append(f"New employee inserts: {inserts}/8 correct.")

    # 5. Total Count Integrity (5 pts)
    # Initial 107 - 0 deletes + 8 inserts = 115
    total = result.get("total_employee_count", 0)
    if 113 <= total <= 117:
        score += 5
        feedback.append("Total employee count valid.")

    # 6. Report File (20 pts)
    if result.get("report_exists"):
        score += 10
        feedback.append("Report file exists.")
        if result.get("report_size", 0) > 100:
            score += 10
            feedback.append("Report file has content.")
        else:
            feedback.append("Report file is empty/too small.")
    else:
        feedback.append("Report file missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }