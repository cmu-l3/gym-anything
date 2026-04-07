#!/usr/bin/env python3
"""
Verifier for Partition Audit Log task.

Scores based on:
1. Table structure (Partitioned? Correct ranges?)
2. Data integrity (Rows preserved?)
3. Indexing strategy (Local indexes created?)
4. Reporting (Summary file created?)

Pass threshold: 60/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_partition_audit_log(traj, env_info, task_info):
    """
    Verifies that EMPLOYEE_AUDIT_LOG was correctly partitioned and data preserved.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result
    with tempfile.TemporaryDirectory() as tmpdir:
        local_path = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/partition_audit_result.json", local_path)
            with open(local_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Verification failed: Could not load result file. {str(e)}"
            }

    score = 0
    feedback = []

    # 1. Table Partitioning (30 pts)
    if result.get("is_partitioned"):
        score += 15
        feedback.append("Table is partitioned (+15)")
        
        p_count = result.get("partition_count", 0)
        if p_count >= 5:
            score += 10
            feedback.append(f"Partition count sufficient ({p_count} >= 5) (+10)")
        elif p_count > 1:
            score += 5
            feedback.append(f"Partition count low ({p_count}), expected 5+ (+5)")
        else:
            feedback.append("Partition count insufficient")

        # Check for FUTURE/MAXVALUE partition (heuristic: usually named P_FUTURE or similar, or just count)
        p_names = result.get("partition_names", [])
        if any("FUTURE" in p.upper() or "MAX" in p.upper() for p in p_names) or p_count >= 5:
             score += 5
             feedback.append("Catch-all/Future partition appears to exist (+5)")
    else:
        feedback.append("CRITICAL: Table is NOT partitioned (0 pts for structure)")

    # 2. Data Integrity (30 pts)
    initial = result.get("initial_count", 0)
    current = result.get("current_count", 0)
    
    # Allow very small discrepancy if something weird happened, but ideally 0
    if initial > 0 and current == initial:
        score += 30
        feedback.append(f"Data integrity verified: {current} rows preserved (+30)")
    elif initial > 0 and abs(current - initial) < 100:
        score += 15
        feedback.append(f"Data integrity warning: Row count changed slightly ({initial} -> {current}) (+15)")
    else:
        feedback.append(f"CRITICAL: Significant data loss! {initial} -> {current}")

    # Check partition distribution (ensure not all rows in one partition)
    p_counts = result.get("partition_row_counts", {})
    non_empty_partitions = sum(1 for c in p_counts.values() if c > 0)
    if non_empty_partitions >= 4: # 2021, 22, 23, 24 should have data
        score += 5 # Bonus
        feedback.append("Data correctly distributed across partitions (+5)")
    elif non_empty_partitions <= 1 and result.get("is_partitioned"):
        feedback.append("WARNING: All data is in a single partition. Partition ranges might be wrong.")
        score -= 5

    # 3. Indexing (20 pts)
    local_idxs = result.get("local_index_count", 0)
    if local_idxs >= 2:
        score += 20
        feedback.append(f"Local indexes created: {local_idxs} (+20)")
    elif local_idxs == 1:
        score += 10
        feedback.append("Only 1 local index found, expected 2 (+10)")
    else:
        # Check if they created global indexes instead
        total_idxs = len(result.get("indexes", []))
        if total_idxs >= 2:
            score += 5
            feedback.append("Indexes found but not LOCAL partitioned (+5)")
        else:
            feedback.append("No indexes found")

    # 4. Summary Report (15 pts)
    if result.get("summary_file_exists"):
        score += 10
        content = result.get("summary_file_content", "")
        if len(content) > 20 and any(char.isdigit() for char in content):
             score += 5
             feedback.append("Summary file content looks valid (+15)")
        else:
             feedback.append("Summary file exists but content is empty/sparse (+10)")
    else:
        feedback.append("Summary report file not found at /home/ga/Desktop/partition_summary.txt")

    # Final tally
    passed = score >= 60 and result.get("is_partitioned") and (abs(current - initial) < 1000)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }