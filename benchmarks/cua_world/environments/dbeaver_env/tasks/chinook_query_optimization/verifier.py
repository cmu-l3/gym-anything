#!/usr/bin/env python3
"""
Verifier for chinook_query_optimization task.

Criteria:
1. DBeaver Connection 'ChinookPerf' exists (10 pts)
2. Index on invoices(InvoiceDate) created in DB (15 pts)
3. Index on customers(City) created in DB (15 pts)
4. Index on tracks(Composer) created in DB (15 pts)
5. Index on tracks(Milliseconds) created in DB (15 pts)
6. SQL script exists and contains CREATE INDEX (10 pts)
7. Report CSV exists, has header, and 4 data rows (20 pts)

Anti-gaming:
- Indexes checked directly in SQLite, not just by reading the SQL file (prevents fake files).
- File timestamps checked to ensure creation during task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_query_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []

    # 1. Connection (10 pts)
    if result.get("connection_exists", False):
        score += 10
        feedback.append("Connection 'ChinookPerf' verified.")
    else:
        feedback.append("Missing DBeaver connection 'ChinookPerf'.")

    # 2. Indexes (15 pts each = 60 pts)
    indexes = [
        ("InvoiceDate", result.get("index_invoice_date", False)),
        ("City", result.get("index_customer_city", False)),
        ("Composer", result.get("index_track_composer", False)),
        ("Milliseconds", result.get("index_track_milliseconds", False))
    ]
    
    idx_count = 0
    for name, exists in indexes:
        if exists:
            score += 15
            idx_count += 1
            feedback.append(f"Index on {name} created.")
        else:
            feedback.append(f"Missing index on {name}.")

    # 3. SQL File (10 pts)
    if result.get("sql_file_exists", False) and result.get("sql_content_valid", False):
        score += 10
        feedback.append("SQL script created.")
    elif result.get("sql_file_exists", False):
        score += 5
        feedback.append("SQL script exists but content invalid.")
    else:
        feedback.append("SQL script missing.")

    # 4. Report CSV (20 pts)
    # Full points if valid header + 4 rows
    # Partial points if exists but wrong rows
    report_exists = result.get("report_file_exists", False)
    report_valid = result.get("report_valid", False)
    report_rows = result.get("report_rows", 0)

    if report_exists and report_valid and report_rows >= 4:
        score += 20
        feedback.append("Optimization report valid.")
    elif report_exists:
        score += 5
        feedback.append(f"Report exists but incomplete (found {report_rows} rows).")
    else:
        feedback.append("Optimization report missing.")

    passed = (score >= 60) and (idx_count >= 3) # Pass if score >= 60 and at least 3/4 indexes created

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }