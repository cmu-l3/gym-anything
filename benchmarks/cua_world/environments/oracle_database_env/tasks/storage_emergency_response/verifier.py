#!/usr/bin/env python3
"""
Verifier for Storage Emergency Response task.

Scoring Breakdown (100 pts):
- TS_EMR_LOGS has significant free space (>20MB) (20 pts)
- TS_ARCHIVE created (10 pts)
- EMR_HISTORICAL_LOGS moved to TS_ARCHIVE (30 pts)
- Indexes on historical table are VALID (20 pts)
- Operational Check (Insert succeeds) (10 pts)
- Report file exists (10 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_storage_emergency(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/storage_emergency_result.json", result_path)
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Check TS_EMR_LOGS Capacity (20 pts)
    # The user should have added at least 50MB.
    # The table move frees up ~15MB.
    # So we expect > 20MB free space easily if they did both.
    free_mb = result.get("ts_emr_logs_free_mb", 0)
    if free_mb >= 20:
        score += 20
        feedback.append(f"TS_EMR_LOGS has healthy free space ({free_mb:.1f} MB). (+20)")
    elif free_mb > 1:
        score += 5
        feedback.append(f"TS_EMR_LOGS has some free space ({free_mb:.1f} MB), but less than expected. Did you extend it enough? (+5)")
    else:
        feedback.append("TS_EMR_LOGS is still full or near full. (0)")

    # 2. Check TS_ARCHIVE creation (10 pts)
    if result.get("ts_archive_exists"):
        score += 10
        feedback.append("TS_ARCHIVE tablespace exists. (+10)")
    else:
        feedback.append("TS_ARCHIVE tablespace not found. (0)")

    # 3. Check Table Move (30 pts)
    if result.get("historical_table_moved"):
        score += 30
        feedback.append("EMR_HISTORICAL_LOGS successfully moved to TS_ARCHIVE. (+30)")
    else:
        loc = result.get("historical_table_tablespace", "UNKNOWN")
        feedback.append(f"EMR_HISTORICAL_LOGS is in {loc}, expected TS_ARCHIVE. (0)")

    # 4. Check Index Validity (20 pts)
    # If the table wasn't moved, indexes likely remain valid, but the user gets 0 for the move.
    # If table moved but indexes UNUSABLE, they fail this.
    if result.get("indexes_valid"):
        score += 20
        feedback.append("Indexes on historical table are VALID. (+20)")
    else:
        inv_count = result.get("invalid_index_count", 0)
        feedback.append(f"Found {inv_count} UNUSABLE indexes. You must rebuild indexes after moving a table. (0)")

    # 5. Operational Check (10 pts)
    if result.get("operational_check_passed"):
        score += 10
        feedback.append("System is operational (insert succeeded). (+10)")
    else:
        err = result.get("operational_check_error", "Unknown error")
        feedback.append(f"Operational check failed: {err}. (0)")

    # 6. Report File (10 pts)
    if result.get("report_file_exists"):
        score += 10
        feedback.append("Report file created. (+10)")
    else:
        feedback.append("Report file not found. (0)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }