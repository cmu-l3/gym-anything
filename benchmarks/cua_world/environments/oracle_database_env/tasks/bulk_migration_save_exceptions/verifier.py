#!/usr/bin/env python3
"""
Verifier for bulk_migration_save_exceptions task.

Scoring Breakdown (100 pts total):
1. DATA INTEGRITY (50 pts)
   - Valid rows in FACT_SALES_PROD matches (Total - Bad): 30 pts
   - Error rows in MIGRATION_ERRORS matches Bad: 20 pts

2. ERROR LOG QUALITY (10 pts)
   - Logged messages contain 'check constraint' or similar: 10 pts

3. CODE IMPLEMENTATION (40 pts)
   - Procedure exists and is VALID: 5 pts
   - Uses BULK COLLECT: 5 pts
   - Uses FORALL: 10 pts
   - Uses SAVE EXCEPTIONS: 10 pts
   - Uses %BULK_EXCEPTIONS (to read errors): 5 pts
   - Uses LIMIT (memory protection): 5 pts

Pass threshold: 60 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_migration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic setup check
    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database Error: {result['db_error']}"}

    score = 0
    feedback = []

    # --- 1. Data Integrity Checks ---
    ground_total = result.get("ground_truth_total", 50000)
    ground_bad = result.get("ground_truth_bad", 0)
    ground_valid = ground_total - ground_bad

    target_count = result.get("target_count", 0)
    error_count = result.get("error_log_count", 0)

    # Valid Rows (30 pts)
    # Allow tiny tolerance in case of weird randomness, but setup is deterministic
    if abs(target_count - ground_valid) < 5:
        score += 30
        feedback.append(f"Successfully migrated {target_count} valid rows (Target: {ground_valid}).")
    elif target_count > 0:
        score += 10 # Partial credit if they moved *something* but count is off
        feedback.append(f"Migrated {target_count} rows, but expected {ground_valid}.")
    else:
        feedback.append("No valid rows found in target table.")

    # Error Logging (20 pts)
    if abs(error_count - ground_bad) < 5 and ground_bad > 0:
        score += 20
        feedback.append(f"Successfully logged {error_count} errors (Target: {ground_bad}).")
    elif error_count > 0:
        score += 10
        feedback.append(f"Logged {error_count} errors, but expected {ground_bad}.")
    else:
        feedback.append("No errors logged in MIGRATION_ERRORS table.")

    # --- 2. Error Message Quality ---
    samples = result.get("error_samples", [])
    valid_msgs = [m for m in samples if "CHECK" in m.upper() or "CONSTRAINT" in m.upper() or "CHK_SALES_AMOUNT" in m.upper()]
    if valid_msgs:
        score += 10
        feedback.append("Error messages correctly identify constraint violations.")
    elif samples:
        feedback.append("Error messages logged, but didn't mention constraint details clearly.")

    # --- 3. Code Implementation Checks ---
    if result.get("procedure_exists") and result.get("procedure_status") == "VALID":
        score += 5
        feedback.append("Procedure MIGRATE_SALES_BULK exists and compiles.")
    else:
        feedback.append("Procedure missing or invalid.")

    keywords = result.get("keywords_found", {})
    
    if keywords.get("bulk_collect"):
        score += 5
        feedback.append("Code uses BULK COLLECT.")
    else:
        feedback.append("Code missing BULK COLLECT.")

    if keywords.get("forall"):
        score += 10
        feedback.append("Code uses FORALL.")
    else:
        feedback.append("Code missing FORALL.")

    if keywords.get("save_exceptions"):
        score += 10
        feedback.append("Code uses SAVE EXCEPTIONS.")
    else:
        feedback.append("Code missing SAVE EXCEPTIONS.")
        
    if keywords.get("bulk_exceptions"):
        score += 5
        feedback.append("Code uses %BULK_EXCEPTIONS.")
    
    if keywords.get("limit"):
        score += 5
        feedback.append("Code uses LIMIT clause.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }