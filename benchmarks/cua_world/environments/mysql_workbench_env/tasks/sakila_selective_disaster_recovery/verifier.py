#!/usr/bin/env python3
"""
Verifier for sakila_selective_disaster_recovery

Scoring Logic:
1. Schema Integrity (20pts): `audit_tag` column exists.
2. Data Safety (20pts): Existing rows outside the gap were not deleted/overwritten (count check).
3. Restore Volume (30pts): The ~203 missing rows are present.
4. Restore Quality (20pts): The restored rows have `audit_tag` = 'RESTORED'.
5. Export/Process (10pts): CSV exists and is valid.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_selective_disaster_recovery(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/disaster_recovery_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Expected constants (Sakila standard)
    # Total rows ~16049. Gap is ~203 rows. Initial rows ~15846.
    # Existing data preserved should be ~15846.
    
    # 1. Schema Preservation (20 pts)
    if result.get("has_audit_column", False):
        score += 20
        feedback_parts.append("Schema preserved (audit_tag exists).")
    else:
        feedback_parts.append("CRITICAL: Schema destroyed (audit_tag column missing). Did you drop the table?")
        # If schema is destroyed, likely everything is wrong, but we continue checks.

    # 2. Data Safety (20 pts)
    # We check if non-restored data count is roughly what we started with
    initial = result.get("initial_row_count", 0)
    preserved = result.get("existing_data_preserved_count", 0)
    
    # Allow small flux, but generally should match
    if abs(preserved - initial) < 50:
        score += 20
        feedback_parts.append("Existing data safely preserved.")
    elif preserved < initial:
        # Penalize for data loss
        loss = initial - preserved
        score += max(0, 10 - int(loss/10))
        feedback_parts.append(f"DATA LOSS DETECTED: {loss} existing rows missing.")
    else:
        # Weird case, maybe duplicates?
        score += 10
        feedback_parts.append("Existing data count mismatch.")

    # 3. Restore Volume (30 pts)
    # We want ~203 rows restored (either correctly tagged or not)
    restored_correct = result.get("restored_correctly_count", 0)
    restored_wrong = result.get("restored_wrong_tag_count", 0)
    total_restored = restored_correct + restored_wrong
    
    expected_restored = 203
    
    if total_restored >= (expected_restored * 0.9):
        score += 30
        feedback_parts.append(f"Restored {total_restored} missing records.")
    elif total_restored > 0:
        partial = int(30 * (total_restored / expected_restored))
        score += partial
        feedback_parts.append(f"Partially restored {total_restored}/{expected_restored} records.")
    else:
        feedback_parts.append("No missing records were restored.")

    # 4. Restore Quality (20 pts)
    # Strict check on the tag
    if total_restored > 0:
        quality_ratio = restored_correct / total_restored
        quality_pts = int(20 * quality_ratio)
        score += quality_pts
        if quality_ratio < 1.0:
            feedback_parts.append(f"Tagging issues: {restored_wrong} rows have wrong audit_tag.")
        else:
            feedback_parts.append("All restored rows correctly tagged 'RESTORED'.")
    
    # 5. Export (10 pts)
    if result.get("csv_exists", False) and result.get("csv_rows", 0) > 10:
        score += 10
        feedback_parts.append("CSV export verified.")
    else:
        feedback_parts.append("CSV export missing or empty.")

    # Bonus: Staging DB check (not scored, but good for logs)
    if result.get("staging_db_detected", False):
        feedback_parts.append("(Staging DB usage detected).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }