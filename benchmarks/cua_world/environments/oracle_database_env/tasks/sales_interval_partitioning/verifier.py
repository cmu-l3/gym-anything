#!/usr/bin/env python3
"""
Verifier for Sales Interval Partitioning task.

Criteria:
1. Table GLOBAL_SALES exists.
2. Partitioning is RANGE with non-null INTERVAL (Interval Partitioning).
3. Subpartitioning is LIST.
4. Local Index exists.
5. Data loaded (~2000 rows).
6. Automation proved (2028 record exists).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_partitioning(traj, env_info, task_info):
    """
    Verifies that the Oracle table is correctly partitioned with Interval-List strategy
    and data is loaded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        score = 0
        feedback_parts = []
        
        # 1. Table Exists (10 pts)
        if result.get("table_exists"):
            score += 10
            feedback_parts.append("Table GLOBAL_SALES exists (+10)")
        else:
            return {"passed": False, "score": 0, "feedback": "Table GLOBAL_SALES not found"}

        # 2. Interval Partitioning (20 pts)
        # Oracle represents Interval partitioning as TYPE='RANGE' with an INTERVAL clause
        part_type = result.get("partitioning_type", "UNKNOWN")
        interval_clause = result.get("interval_clause")
        
        if part_type == "RANGE" and interval_clause is not None and interval_clause != "None":
            score += 20
            feedback_parts.append("Interval Partitioning Configured (+20)")
        else:
            feedback_parts.append(f"Incorrect partitioning: Type={part_type}, Interval={interval_clause}")

        # 3. List Subpartitioning (20 pts)
        sub_type = result.get("subpartitioning_type", "UNKNOWN")
        if sub_type == "LIST":
            score += 20
            feedback_parts.append("List Subpartitioning Configured (+20)")
        else:
            feedback_parts.append(f"Incorrect subpartitioning: {sub_type}")

        # 4. Data Loading (20 pts)
        # We generated 2000 rows + 1 manually inserted = 2001 expected
        row_count = result.get("row_count", 0)
        if row_count >= 2000:
            score += 20
            feedback_parts.append(f"Data loaded successfully ({row_count} rows) (+20)")
        elif row_count > 0:
            score += 10
            feedback_parts.append(f"Partial data loaded ({row_count} rows) (+10)")
        else:
            feedback_parts.append("Table is empty (0 pts)")

        # 5. Automation Check (Future Record) (10 pts)
        if result.get("future_record_found"):
            score += 10
            feedback_parts.append("Future record (2028) found - Interval automation working (+10)")
        else:
            feedback_parts.append("Future record not found")

        # 6. Local Index (10 pts)
        indexes = result.get("local_indexes", [])
        has_local = any(idx.get("locality") == "LOCAL" for idx in indexes)
        if has_local:
            score += 10
            feedback_parts.append("Local Partitioned Index exists (+10)")
        else:
            feedback_parts.append("No LOCAL index found")
        
        # 7. Subpartition definitions (10 pts implicit via check)
        # We check high values or names if strictly needed, but getting LIST type is usually sufficient
        # combined with row distribution. Here we trust the type check + data.
        sub_vals = str(result.get("subpartition_high_values", []))
        if "NA" in sub_vals or "EU" in sub_vals:
            score += 10
            feedback_parts.append("Subpartition keys detected (+10)")
        else:
            feedback_parts.append("Could not verify subpartition keys")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}