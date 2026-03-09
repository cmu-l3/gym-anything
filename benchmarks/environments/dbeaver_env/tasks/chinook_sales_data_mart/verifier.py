#!/usr/bin/env python3
"""
Verifier for chinook_sales_data_mart task.

Scoring Breakdown (100 pts):
- Database created & modified during task: 10 pts
- 'fact_sales' table exists: 10 pts
- Column structure matches requirements (10 columns): 20 pts
- Row count matches source (2240): 15 pts
- Artist Join logic (Sample check): 15 pts
- Quarter calculation logic: 10 pts
- CrossBorder logic (Checksum): 10 pts
- SQL Script saved: 10 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_sales_data_mart(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    required_cols = set(metadata.get('required_columns', []))
    expected_rows = metadata.get('expected_rows', 2240)

    # Load Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. DB Exists & Created During Task (10 pts)
    if result.get('db_exists') and result.get('created_during_task'):
        score += 10
        feedback.append("Database created successfully.")
    elif result.get('db_exists'):
        score += 5
        feedback.append("Database exists but timestamp check failed (pre-existing?).")
    else:
        feedback.append("Target database chinook_dw.db not found.")

    # 2. Table Exists (10 pts)
    if result.get('table_exists'):
        score += 10
    else:
        feedback.append("Table 'fact_sales' not found in database.")

    # 3. Column Structure (20 pts)
    actual_cols = set(result.get('columns', []))
    missing_cols = required_cols - actual_cols
    
    if not missing_cols and result.get('table_exists'):
        score += 20
        feedback.append("Schema structure is correct.")
    elif result.get('table_exists'):
        # Partial credit if table exists but cols missing
        score += 5
        feedback.append(f"Missing columns: {', '.join(missing_cols)}")

    # 4. Row Count (15 pts)
    rows = result.get('row_count', 0)
    if rows == expected_rows:
        score += 15
        feedback.append(f"Row count correct ({rows}).")
    elif rows > 0:
        score += 5
        feedback.append(f"Row count incorrect. Expected {expected_rows}, got {rows}.")
    
    # 5. Artist Join Logic (15 pts)
    if result.get('artist_check') == 'pass':
        score += 15
        feedback.append("Artist/Album/Track join logic verified.")
    else:
        feedback.append("Artist name lookup failed (Check joins).")

    # 6. Quarter Calculation (10 pts)
    if result.get('quarter_check') == 'pass':
        score += 10
        feedback.append("SalesQuarter format verified.")
    else:
        feedback.append("SalesQuarter format incorrect (Expected YYYY-Q#).")

    # 7. CrossBorder Logic (10 pts)
    # Ground truth for standard Chinook: 
    # There are exactly 2240 items.
    # Cross border calc: Customer Country vs Rep Country (Employee).
    # Based on standard data, checksum is roughly known, but >0 is a basic check.
    # A precise checksum calculation would be better, but verifying >0 and <2240 is a sanity check.
    # In Chinook, Reps are in Canada (Calgary). Customers are global. Most are cross-border.
    cb_sum = result.get('cross_border_sum', 0)
    if 500 < cb_sum < 2240: 
        score += 10
        feedback.append("Cross-border calculation looks reasonable.")
    else:
        feedback.append(f"Cross-border logic suspicious (Sum: {cb_sum}).")

    # 8. Script Exists (10 pts)
    if result.get('script_exists'):
        score += 10
        feedback.append("ETL script saved.")
    else:
        feedback.append("ETL script not found.")

    # Final Pass Determination
    # Threshold 65
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }