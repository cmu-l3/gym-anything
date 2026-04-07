#!/usr/bin/env python3
"""
Verifier for Storage HWM Optimization task.

Scoring Criteria:
1. Data Integrity (30 pts): Row count is exactly 5000 AND specific sample IDs exist.
2. Space Reclaimed (40 pts): Table size < 30MB (Starting size ~200MB).
3. Index Health (20 pts): Index is VALID (agent handled invalidation if MOVE was used).
4. Index Optimization (10 pts): Index size < 10MB (Bonus for rebuilding index).

Pass Threshold: 70 points
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_storage_hwm_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_row_count = metadata.get('expected_row_count', 5000)
    max_acceptable_size_mb = metadata.get('max_acceptable_size_mb', 30)

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check for DB errors
    if result.get("db_error"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Database error prevented verification: {result['db_error']}"
        }

    # CRITERION 1: Data Integrity (30 pts)
    # Must match row count exactly and pass specific ID check
    row_count = result.get("row_count", 0)
    integrity_passed = result.get("data_integrity_passed", False)
    
    if row_count == expected_row_count and integrity_passed:
        score += 30
        feedback_parts.append("Data integrity preserved (5000 rows)")
    elif row_count != expected_row_count:
        feedback_parts.append(f"Data loss detected: Found {row_count} rows, expected {expected_row_count}")
    else:
        feedback_parts.append("Data corruption detected (missing specific IDs)")

    # CRITERION 2: Space Reclamation (40 pts)
    # Target < 30MB
    size_mb = result.get("current_size_mb", 999.0)
    if size_mb < max_acceptable_size_mb:
        score += 40
        feedback_parts.append(f"Storage optimized: {size_mb:.2f} MB")
    elif size_mb < 100:
        score += 20
        feedback_parts.append(f"Partial optimization: {size_mb:.2f} MB (Target < {max_acceptable_size_mb} MB)")
    else:
        feedback_parts.append(f"Storage NOT optimized: {size_mb:.2f} MB")

    # CRITERION 3: Index Health (20 pts)
    # Must be VALID
    idx_status = result.get("index_status", "UNKNOWN")
    if idx_status == "VALID":
        score += 20
        feedback_parts.append("Index is VALID")
    elif idx_status == "UNUSABLE":
        feedback_parts.append("FAIL: Index left in UNUSABLE state")
    elif idx_status == "MISSING":
        feedback_parts.append("FAIL: Index was dropped")
    else:
        feedback_parts.append(f"Index status: {idx_status}")

    # CRITERION 4: Index Optimization (10 pts)
    # Rebuilding the index should shrink it significantly
    idx_size_mb = result.get("index_size_bytes", 0) / (1024 * 1024)
    if idx_status == "VALID" and idx_size_mb < 10.0:
        score += 10
        feedback_parts.append(f"Index optimized ({idx_size_mb:.2f} MB)")
    
    # Final Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }