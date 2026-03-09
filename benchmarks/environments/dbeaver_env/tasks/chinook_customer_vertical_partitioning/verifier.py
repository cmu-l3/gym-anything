#!/usr/bin/env python3
"""
Verifier for chinook_customer_vertical_partitioning task.

Criteria:
1. Connection 'ChinookRefactor' exists (10 pts)
2. Table 'customer_contact' exists with correct schema (20 pts)
   - Must have CustomerId, Email, etc.
   - Must NOT be empty
3. Table 'customers' refactored (20 pts)
   - Must NOT have Email, Phone, Address, etc.
   - Must have 59 rows
4. Data Migration Integrity (20 pts)
   - customer_contact has 59 rows
   - Sample data check passed (Luís Gonçalves has correct email)
5. View 'v_customers_extended' exists and works (15 pts)
   - Returns 59 rows
   - Reconstructs original view
6. Artifacts (15 pts)
   - CSV export exists and has data
   - SQL script exists
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_partitioning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/partition_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Connection Check (10 pts)
    if result.get('connection_found', False):
        score += 10
        feedback.append("DBeaver connection 'ChinookRefactor' confirmed.")
    else:
        feedback.append("Connection 'ChinookRefactor' not found in DBeaver.")

    # 2. customer_contact Table (20 pts)
    contact_schema = result.get('contact_schema', '').lower()
    contact_rows = result.get('contact_rows', 0)
    
    # Check for required columns in schema
    req_contact_cols = ['customerid', 'email', 'phone', 'address', 'city']
    has_contact_cols = all(col in contact_schema for col in req_contact_cols)
    
    if has_contact_cols and contact_rows > 0:
        score += 20
        feedback.append("Table 'customer_contact' created with correct columns.")
    elif contact_rows > 0:
        score += 10
        feedback.append("Table 'customer_contact' exists but might miss some columns.")
    else:
        feedback.append("Table 'customer_contact' missing or empty.")

    # 3. customers Table Refactoring (20 pts)
    cust_schema = result.get('customers_schema', '').lower()
    cust_rows = result.get('customers_rows', 0)
    
    # These should be GONE
    dropped_cols = ['email', 'phone', 'address', 'postalcode']
    # These should be PRESENT
    kept_cols = ['customerid', 'firstname', 'lastname']
    
    cols_correctly_dropped = not any(col in cust_schema for col in dropped_cols)
    cols_kept = all(col in cust_schema for col in kept_cols)
    
    if cols_correctly_dropped and cols_kept and cust_rows == 59:
        score += 20
        feedback.append("Table 'customers' correctly refactored (columns dropped).")
    elif not cols_correctly_dropped:
        feedback.append("Table 'customers' still contains columns that should have been moved.")
    else:
        feedback.append("Table 'customers' structure or row count incorrect.")

    # 4. Data Migration Integrity (20 pts)
    # Check row counts and sample data
    orphan_count = result.get('orphan_count', 0)
    sample_valid = result.get('sample_data_valid', False)
    
    if contact_rows == 59 and cust_rows == 59 and orphan_count == 0 and sample_valid:
        score += 20
        feedback.append("Data migration successful (all rows moved, integrity verified).")
    else:
        score += 5 # Partial points for trying
        feedback.append(f"Data migration issues: ContactRows={contact_rows}, Orphans={orphan_count}, SampleValid={sample_valid}")

    # 5. View Creation (15 pts)
    view_rows = result.get('view_rows', 0)
    if view_rows == 59:
        score += 15
        feedback.append("View 'v_customers_extended' works and returns correct row count.")
    else:
        feedback.append(f"View 'v_customers_extended' returned {view_rows} rows (expected 59).")

    # 6. Artifacts (15 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    sql_exists = result.get('sql_exists', False)
    
    if csv_exists and csv_rows >= 59:
        score += 10
        feedback.append("CSV export verified.")
    else:
        feedback.append("CSV export missing or incomplete.")
        
    if sql_exists:
        score += 5
        feedback.append("SQL script saved.")

    # Final Verification
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }