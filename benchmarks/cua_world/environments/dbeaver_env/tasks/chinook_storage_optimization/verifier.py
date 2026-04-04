#!/usr/bin/env python3
"""
Verifier for Chinook Storage Optimization task.

Scoring Criteria:
1. DBeaver connection created (10 pts)
2. Archive CSV exists and created during task (10 pts)
3. Archive CSV row count matches expected deleted rows (20 pts)
4. Old records effectively deleted from DB (20 pts)
5. New records preserved in DB (15 pts)
6. STORAGE OPTIMIZED: DB file size significantly reduced (VACUUM used) (25 pts)

Pass Threshold: 75 points (requires Optimization to pass)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_storage_optimization(traj, env_info, task_info):
    """Verify storage optimization task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}

    score = 0
    feedback = []
    
    # Extract data
    conn_found = result.get('connection_found', False)
    csv_exists = result.get('csv_exists', False)
    csv_fresh = result.get('csv_created_during_task', False)
    csv_count = result.get('csv_row_count', 0)
    
    rem_old = result.get('remaining_old_count', -1)
    rem_new = result.get('remaining_new_count', -1)
    init_old = result.get('initial_old_count', 0)
    init_new = result.get('initial_new_count', 0)
    
    final_size = result.get('final_db_size_bytes', 0)
    init_size = result.get('initial_db_size_bytes', 0)

    # 1. Connection (10 pts)
    if conn_found:
        score += 10
        feedback.append("DBeaver connection confirmed.")
    else:
        feedback.append("MISSING: DBeaver connection not found.")

    # 2. Archive CSV existence (10 pts)
    if csv_exists and csv_fresh:
        score += 10
        feedback.append("Archive CSV created.")
    elif csv_exists:
        score += 5
        feedback.append("Archive CSV exists but timestamp check failed.")
    else:
        feedback.append("MISSING: Archive CSV not found.")

    # 3. Archive Count Accuracy (20 pts)
    # Allow 1% tolerance
    expected_archive = init_old
    if expected_archive > 0:
        diff = abs(csv_count - expected_archive)
        if diff <= (expected_archive * 0.01):
            score += 20
            feedback.append(f"Archive CSV count correct ({csv_count}).")
        elif diff <= (expected_archive * 0.10):
            score += 10
            feedback.append(f"Archive CSV count roughly correct ({csv_count} vs {expected_archive}).")
        else:
            feedback.append(f"Archive CSV count mismatch: found {csv_count}, expected ~{expected_archive}.")

    # 4. Old Records Deleted (20 pts)
    if rem_old == 0:
        score += 20
        feedback.append("All old records deleted from database.")
    elif rem_old > 0:
        feedback.append(f"FAILED: {rem_old} old records still remain in database.")
    else:
        feedback.append("Could not verify database records.")

    # 5. New Records Preserved (15 pts)
    if rem_new > 0 and init_new > 0:
        diff_new = abs(rem_new - init_new)
        if diff_new <= (init_new * 0.01):
            score += 15
            feedback.append("Recent records preserved.")
        else:
            feedback.append(f"Warning: Some recent records missing or added (Found {rem_new}, expected {init_new}).")
    else:
        feedback.append("Recent records check failed.")

    # 6. Storage Optimization / VACUUM (25 pts)
    # Initial size ~50MB. If rows deleted but NO vacuum, size stays ~50MB.
    # If vacuumed, size should drop to ~15-20MB.
    # Threshold: Must be < 60% of original size.
    
    size_ratio = final_size / init_size if init_size > 0 else 1.0
    final_mb = final_size / (1024*1024)
    init_mb = init_size / (1024*1024)

    if size_ratio < 0.6:
        score += 25
        feedback.append(f"Storage optimized: Size reduced from {init_mb:.1f}MB to {final_mb:.1f}MB.")
    else:
        feedback.append(f"FAILED: Database file size not significantly reduced ({init_mb:.1f}MB -> {final_mb:.1f}MB). Did you run VACUUM?")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }