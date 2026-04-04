#!/usr/bin/env python3
"""
Verifier for chinook_genre_target_import task.

Criteria:
1. DBeaver connection 'ChinookImport' exists (10 pts)
2. Table 'genre_sales_targets' created in DB (15 pts)
3. Table loaded with data (row count matches CSV) (15 pts)
4. SQL Analysis script exists (10 pts)
5. Export CSV exists (10 pts)
6. Export CSV has correct columns (10 pts)
7. Export CSV data accuracy (Variance calculation matches Ground Truth) (30 pts)

Pass Threshold: 60/100
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_genre_target_import(traj, env_info, task_info):
    """
    Verify the Chinook Genre Target Import task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    validation = result.get('validation', {})

    # 1. Connection Exists (10 pts)
    if result.get('connection_exists', False):
        score += 10
        feedback.append("DBeaver connection 'ChinookImport' found.")
    else:
        feedback.append("Missing DBeaver connection 'ChinookImport'.")

    # 2. Table Exists (15 pts)
    if result.get('table_exists', False):
        score += 15
        feedback.append("Table 'genre_sales_targets' exists in database.")
    else:
        feedback.append("Table 'genre_sales_targets' NOT found in database.")

    # 3. Data Loaded (15 pts)
    db_rows = result.get('db_row_count', 0)
    csv_rows = result.get('target_csv_rows', 0)
    # Allow small discrepancy (header issues etc)
    if db_rows > 0 and abs(db_rows - csv_rows) <= 2:
        score += 15
        feedback.append(f"Table data loaded correctly ({db_rows} rows).")
    elif db_rows > 0:
        score += 5
        feedback.append(f"Table has data, but row count mismatch (DB: {db_rows}, CSV: {csv_rows}).")
    else:
        feedback.append("Table is empty.")

    # 4. SQL Script Exists (10 pts)
    if result.get('sql_script_exists', False):
        score += 10
        feedback.append("SQL analysis script found.")
    else:
        feedback.append("SQL analysis script missing.")

    # 5. Export CSV Exists (10 pts)
    if validation.get('export_exists', False):
        score += 10
        feedback.append("Export variance report found.")
    else:
        feedback.append("Export variance report missing.")

    # 6. Columns Valid (10 pts)
    if validation.get('columns_valid', False):
        score += 10
        feedback.append("Export has all required columns.")
    else:
        cols = validation.get('columns_found', [])
        feedback.append(f"Export missing required columns. Found: {cols}")

    # 7. Data Accuracy (30 pts)
    accuracy = validation.get('data_accuracy', 0.0)
    if accuracy > 0.9:
        score += 30
        feedback.append("Variance calculations match ground truth (>90%).")
    elif accuracy > 0.5:
        score += 15
        feedback.append(f"Variance calculations partially match ground truth ({accuracy*100:.1f}%).")
    else:
        feedback.append(f"Variance calculations incorrect or rows missing ({accuracy*100:.1f}% match).")

    # Anti-gaming check: File creation time
    task_start = int(result.get('task_start_time', 0))
    export_time = int(result.get('export_timestamp', 0))
    if export_time <= task_start and validation.get('export_exists', False):
        score = 0
        feedback = ["Anti-gaming violation: Export file timestamp precedes task start."]

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }