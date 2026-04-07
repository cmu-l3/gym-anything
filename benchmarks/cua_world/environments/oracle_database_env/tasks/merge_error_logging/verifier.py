#!/usr/bin/env python3
"""
Verifier for merge_error_logging task.

Scoring:
- Error log table created (10 pts)
- Valid inserts/updates applied (40 pts)
- Invalid rows rejected (20 pts)
- Errors logged correctly in DB (20 pts)
- CSV Report created (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_error_logging(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result
    with tempfile.TemporaryDirectory() as tmpdir:
        dest = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/merge_result.json", dest)
            with open(dest) as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}

    score = 0
    feedback = []

    # 1. Error Table (10 pts)
    if result.get("error_table_exists"):
        score += 10
        feedback.append("Error logging table exists.")
    else:
        feedback.append("Error logging table (ERR_EMPLOYEES_LOG) not found.")

    # 2. Valid Ops (40 pts)
    # 2 valid inserts expected. 3 valid updates expected.
    # We check sample points.
    ops_score = 0
    if result.get("valid_insert_301_exists"):
        ops_score += 10
    if result.get("valid_update_100_check"):
        ops_score += 15
    if result.get("valid_update_103_check"):
        ops_score += 15
    
    score += ops_score
    feedback.append(f"Data merge accuracy: {ops_score}/40 pts.")

    # 3. Rejection (20 pts)
    # Emp 303 should NOT be in the table
    if not result.get("invalid_insert_303_exists"):
        score += 20
        feedback.append("Invalid rows correctly rejected from target.")
    else:
        feedback.append("Failed: Invalid row (ID 303) was inserted into target table.")

    # 4. Error Logging (20 pts)
    # Expected 5 errors
    log_count = result.get("error_log_count", 0)
    if log_count == 5:
        score += 20
        feedback.append("Exact number of errors logged (5).")
    elif log_count > 0:
        score += 10
        feedback.append(f"Partial error logging: found {log_count} errors (expected 5).")
    else:
        feedback.append("No errors found in log table.")

    # 5. CSV Report (10 pts)
    if result.get("report_file_exists"):
        lines = result.get("report_file_lines", 0)
        if lines >= 5: # Header + some errors
            score += 10
            feedback.append("Error report file created.")
        else:
            score += 5
            feedback.append("Error report file exists but seems empty.")
    else:
        feedback.append("Error report file not found on Desktop.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }