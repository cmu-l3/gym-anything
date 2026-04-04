#!/usr/bin/env python3
"""
Verifier for Northwind Schema Reconstruction Task.

Criteria:
1. Database Created & Connection Exists (20 pts)
2. Schema Structure (4 Tables) (20 pts)
3. Data Counts (Normalization) (30 pts)
4. Foreign Key Integrity (10 pts)
5. Report Accuracy (20 pts)

Pass Threshold: 65/100
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_schema_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    approx_counts = metadata.get('approx_counts', {
        "Customers": 89,
        "Products": 77,
        "Orders": 830,
        "OrderItems": 2155
    })
    tolerance = metadata.get('tolerance_percent', 5) / 100.0

    # Retrieve result JSON
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

    # 1. Database & Connection (20 pts)
    if result.get('db_exists', False):
        score += 10
        feedback.append("Database file created.")
    else:
        feedback.append("Database file missing.")

    if result.get('connection_created', False):
        score += 10
        feedback.append("DBeaver connection found.")
    else:
        feedback.append("DBeaver connection 'NorthwindRestored' not found.")

    # 2. Schema Structure (20 pts)
    tables_found = result.get('tables_found', [])
    required_tables = ["Customers", "Products", "Orders", "OrderItems"]
    missing_tables = [t for t in required_tables if not any(ft.lower() == t.lower() for ft in tables_found)]
    
    if not missing_tables:
        score += 20
        feedback.append("All required tables found.")
    else:
        # Partial credit: 5 pts per table
        found_count = 4 - len(missing_tables)
        score += (found_count * 5)
        feedback.append(f"Missing tables: {', '.join(missing_tables)}.")

    # 3. Data Counts (30 pts)
    # Check row counts against approximate expected values
    counts = result.get('table_counts', {})
    data_score = 0
    
    for table, expected in approx_counts.items():
        # Case insensitive lookup
        actual = -1
        for k, v in counts.items():
            if k.lower() == table.lower():
                actual = v
                break
        
        if actual == -1:
            feedback.append(f"Table {table} not found or empty.")
            continue
            
        lower_bound = expected * (1 - tolerance)
        upper_bound = expected * (1 + tolerance)
        
        if lower_bound <= actual <= upper_bound:
            data_score += 7.5
            feedback.append(f"{table} count ({actual}) OK.")
        else:
            feedback.append(f"{table} count ({actual}) out of range (expected ~{expected}).")
            
    score += int(data_score)

    # 4. Foreign Key Integrity (10 pts)
    if result.get('fk_integrity_check', False):
        score += 10
        feedback.append("Foreign keys detected on OrderItems.")
    else:
        feedback.append("No foreign keys detected on OrderItems.")

    # 5. Report Accuracy (20 pts)
    if result.get('report_exists', False):
        row_count = result.get('report_row_count', 0)
        # Expect ~89 rows (one per customer)
        if 80 <= row_count <= 100:
            score += 10
            feedback.append("Report row count reasonable.")
        else:
            score += 5
            feedback.append(f"Report row count {row_count} suspicious.")
            
        # Optional: Check content if top customer is known (e.g., 'QUICK-Stop' or 'Save-a-lot')
        # We give remaining points just for existence to be safe, or check non-empty top customer
        if result.get('top_customer'):
            score += 10
            feedback.append(f"Report data visible (Top: {result['top_customer']}).")
    else:
        feedback.append("Verification report missing.")

    return {
        "passed": score >= 65,
        "score": score,
        "feedback": " ".join(feedback)
    }