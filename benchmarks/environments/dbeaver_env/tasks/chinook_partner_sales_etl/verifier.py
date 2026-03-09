#!/usr/bin/env python3
"""
Verifier for Chinook Partner Sales ETL task.

Scoring Breakdown:
- Staging Table Import (20 pts): Table exists and has 9 rows.
- Destination Schema (10 pts): valid_festival_sales has correct columns.
- Data Cleaning (30 pts): valid_festival_sales has exactly the 5 valid rows.
- FK Resolution (10 pts): IDs match real DB records (Integrity Check).
- Exception File Exists (10 pts): File found at correct path.
- Exception Content (20 pts): File has exactly the 4 invalid rows.
"""

import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_partner_sales_etl(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_valid = metadata.get('expected_valid_count', 5)
    expected_exceptions = metadata.get('expected_exception_count', 4)
    expected_total = expected_valid + expected_exceptions
    
    # 1. Load JSON result from export script
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # --- Criterion 1: Staging Table (20 pts) ---
    staging_count = result_data.get("staging_table_count", -1)
    if staging_count == expected_total:
        score += 20
        feedback.append(f"Staging table imported correctly ({staging_count} rows).")
    elif staging_count >= 0:
        score += 10
        feedback.append(f"Staging table exists but has {staging_count} rows (expected {expected_total}).")
    else:
        feedback.append("Staging table 'festival_sales_import' not found.")

    # --- Criterion 2: Destination Schema (10 pts) ---
    schema_dump = result_data.get("valid_schema_dump", "")
    # Check for required column names in the schema dump
    req_cols = ["CustomerId", "TrackId", "Price", "SaleDate"]
    cols_found = 0
    for col in req_cols:
        if col.lower() in schema_dump.lower():
            cols_found += 1
    
    if cols_found == len(req_cols):
        score += 10
        feedback.append("Destination table schema looks correct.")
    elif cols_found > 0:
        score += 5
        feedback.append(f"Destination table missing some required columns (found {cols_found}/{len(req_cols)}).")
    else:
        feedback.append("Destination table schema check failed or table missing.")

    # --- Criterion 3 & 4: Data Cleaning & Integrity (40 pts total) ---
    valid_count = result_data.get("valid_table_count", -1)
    integrity_count = result_data.get("integrity_check_count", 0)

    # Logic: 
    # If valid_count == expected_valid (5), we give pts.
    # If integrity_count == valid_count, it means all rows in the valid table 
    # actually link to real customers/tracks (Foreign Keys are valid).
    
    if valid_count == expected_valid:
        score += 30
        feedback.append(f"Valid table has correct row count ({valid_count}).")
    elif valid_count > 0:
        # Partial credit if they filtered some but not exact
        score += 10
        feedback.append(f"Valid table has {valid_count} rows (expected {expected_valid}).")
    else:
        feedback.append("Valid table 'valid_festival_sales' empty or missing.")

    if valid_count > 0 and integrity_count == valid_count:
        score += 10
        feedback.append("Referential integrity check passed (IDs match real DB records).")
    elif valid_count > 0:
        feedback.append(f"Integrity check failed: {integrity_count}/{valid_count} rows have valid FKs.")

    # --- Criterion 5 & 6: Exception File (30 pts total) ---
    file_exists = result_data.get("exception_file_exists", False)
    exception_rows = result_data.get("exception_row_count", 0)
    created_during = result_data.get("file_created_during_task", False)

    if file_exists and created_during:
        score += 10
        feedback.append("Exception CSV file created.")
        
        # Verify Content Count
        if exception_rows == expected_exceptions:
            score += 20
            feedback.append(f"Exception file has correct row count ({exception_rows}).")
        elif abs(exception_rows - expected_exceptions) <= 1:
            score += 10
            feedback.append(f"Exception file row count is close ({exception_rows}, expected {expected_exceptions}).")
        else:
            feedback.append(f"Exception file row count mismatch ({exception_rows}, expected {expected_exceptions}).")
    else:
        if file_exists:
            feedback.append("Exception file exists but was not created during this task (stale?).")
        else:
            feedback.append("Exception CSV file not found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }