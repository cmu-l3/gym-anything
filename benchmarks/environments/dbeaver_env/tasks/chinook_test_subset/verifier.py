#!/usr/bin/env python3
"""
Verifier for chinook_test_subset task.

Verifies:
1. Database creation and DBeaver connection.
2. Table structure presence.
3. Data correctness (Brazil subset counts).
4. Referential Integrity (no orphans).
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_test_subset(traj, env_info, task_info):
    """
    Verify the creation of a consistent subset database.
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
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Creation (15 pts)
    if result.get('db_exists', False):
        if result.get('db_size', 0) > 1024: # > 1KB (empty sqlite header is small)
            score += 10
            feedback_parts.append("Database file created.")
        else:
            score += 5
            feedback_parts.append("Database file exists but is empty/small.")
    else:
        feedback_parts.append("Target database file not found.")

    if result.get('connection_exists', False):
        score += 5
        feedback_parts.append("DBeaver connection found.")
    else:
        feedback_parts.append("DBeaver connection missing.")

    # 2. Schema Structure (10 pts)
    if result.get('all_tables_exist', False):
        score += 10
        feedback_parts.append("All 9 required tables present.")
    else:
        feedback_parts.append("Some tables are missing.")

    # 3. Data Correctness (30 pts)
    counts = result.get('target_counts', {})
    gt = result.get('ground_truth', {})
    
    # Check Customers (Critical)
    if result.get('correct_customers', False):
        score += 10
        feedback_parts.append("Customer filter (Brazil only) is correct.")
        
        # Check counts if filter is correct
        if counts.get('customers') == gt.get('customers', -1):
            feedback_parts.append(f"Customer count correct ({counts.get('customers')}).")
        else:
            feedback_parts.append(f"Customer count mismatch (got {counts.get('customers')}, expected {gt.get('customers')}).")
    else:
        feedback_parts.append("Customer filter incorrect (found non-Brazil customers or 0 customers).")

    # Check dependent table counts
    # We allow some leeway? No, subset extraction should be exact for these queries.
    match_count = 0
    total_checks = 0
    for table in ['invoices', 'invoice_items', 'tracks']:
        if table in gt:
            total_checks += 1
            if counts.get(table) == gt.get(table):
                match_count += 1
    
    if total_checks > 0:
        points = int((match_count / total_checks) * 20)
        score += points
        feedback_parts.append(f"Dependent data counts: {match_count}/{total_checks} match ground truth.")

    # 4. Referential Integrity (30 pts)
    ri_errors = result.get('ri_errors', {})
    total_orphans = sum(ri_errors.values())
    
    if total_orphans == 0 and result.get('db_exists', False):
        score += 30
        feedback_parts.append("Referential integrity verified (0 orphans).")
    else:
        # Penalize for orphans
        # If DB doesn't exist, this is 0 anyway
        if result.get('db_exists', False):
            score += max(0, 30 - (total_orphans * 5))
            feedback_parts.append(f"Referential integrity issues found ({total_orphans} orphans).")

    # 5. Script (15 pts)
    if result.get('script_exists', False):
        if result.get('script_size', 0) > 100:
            score += 15
            feedback_parts.append("SQL extraction script saved.")
        else:
            score += 5
            feedback_parts.append("SQL script is empty/too small.")
    else:
        feedback_parts.append("SQL script not found.")

    passed = score >= 60 and result.get('correct_customers', False) and total_orphans == 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }