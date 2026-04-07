#!/usr/bin/env python3
"""
Verifier for legacy_shipment_sqlloader task.

Scoring Breakdown (100 pts):
- Table SHIPMENT_HISTORY exists (10 pts)
- Table has correct columns/types (Cost=NUMBER, Date=DATE) (10 pts)
- Control file artifact exists on Desktop (10 pts)
- Header lines skipped (inferred from counts) (10 pts)
- Void records filtered out (15 pts)
- Row count matches expected valid count (20 pts)
- Cost transformation correct (Implied decimal handled) (15 pts)
- Date transformation correct (implicitly checked by DATE type + data load success) (10 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_legacy_shipment_sqlloader(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Copy result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "sqlloader_result.json")
        try:
            copy_from_env("/tmp/sqlloader_result.json", result_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
        
        if not os.path.exists(result_path):
            return {"passed": False, "score": 0, "feedback": "Result file not found."}
            
        with open(result_path, "r") as f:
            result = json.load(f)

    score = 0
    feedback = []
    
    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database check failed: {result['db_error']}"}

    # 1. Table Exists (10)
    if result.get("table_exists"):
        score += 10
        feedback.append("Table SHIPMENT_HISTORY exists (+10)")
    else:
        feedback.append("Table SHIPMENT_HISTORY NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Columns/Types (10)
    cols = result.get("column_types", {})
    # Look for a date column and a number column for cost
    date_cols = [k for k, v in cols.items() if "DATE" in v]
    num_cols = [k for k, v in cols.items() if "NUMBER" in v or "FLOAT" in v]
    
    if len(date_cols) > 0 and len(num_cols) >= 2: # ID and Cost and Weight usually numbers
        score += 10
        feedback.append("Column data types appear correct (+10)")
    else:
        feedback.append(f"Column types issue. Found: {cols} (Expected DATE for Date, NUMBER for Cost) (+0)")

    # 3. Control File Artifact (10)
    if result.get("control_file_exists"):
        score += 10
        feedback.append("Control file found on Desktop (+10)")
        content = result.get("control_file_content", "").upper()
        if "SKIP" in content and "WHEN" in content:
             feedback.append("Control file contains SKIP and WHEN keywords")
    else:
        feedback.append("Control file NOT found on Desktop (+0)")

    # 4. Void Filter (15)
    # Check if '99' status records made it in
    voids_in_db = result.get("void_count_in_db", 0)
    if voids_in_db == 0:
        score += 15
        feedback.append("Void records successfully filtered out (+15)")
    else:
        feedback.append(f"Found {voids_in_db} Void records in DB (should be 0) (+0)")

    # 5. Row Count (20) + Header Skip (10)
    # If row count == expected, it implies header skip worked and filter worked
    row_count = result.get("row_count", 0)
    exp_count = result.get("expected_row_count", 45)
    
    if row_count == exp_count:
        score += 30 # 20 for count + 10 for header skip inference
        feedback.append(f"Row count matches expected ({row_count}) (+30)")
    elif row_count == exp_count + 2:
        # Likely forgot to skip header
        score += 20
        feedback.append("Row count matches expected + 2 headers (Headers not skipped?) (+20)")
    elif row_count > 0:
        # Partial credit if some data loaded
        score += 10
        feedback.append(f"Some data loaded ({row_count} rows), but not expected count ({exp_count}) (+10)")
    else:
        feedback.append("No rows loaded (+0)")

    # 6. Cost Transformation (15)
    # Check sum with tolerance
    db_sum = result.get("cost_sum", 0.0)
    exp_sum = result.get("expected_cost_sum", 0.0)
    
    # 1% tolerance
    if abs(db_sum - exp_sum) < (exp_sum * 0.01):
        score += 15
        feedback.append(f"Cost column sum correct ({db_sum}) (+15)")
    elif abs(db_sum - (exp_sum * 100)) < (exp_sum * 100 * 0.01):
        feedback.append(f"Cost sum is 100x expected. Did you divide by 100? ({db_sum}) (+0)")
    else:
        feedback.append(f"Cost sum incorrect. Exp: {exp_sum}, Got: {db_sum} (+0)")

    # 7. Date Transformation (10)
    # If we have rows and a DATE column, and the load succeeded, we assume this is mostly correct
    # The control file check supports this.
    if row_count > 0 and len(date_cols) > 0:
        score += 10
        feedback.append("Date loaded into DATE column (+10)")
    
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }