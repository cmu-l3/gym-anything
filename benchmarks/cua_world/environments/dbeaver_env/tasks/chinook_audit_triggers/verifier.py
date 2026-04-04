#!/usr/bin/env python3
"""
Verifier for chinook_audit_triggers task.

Criteria:
1. DBeaver connection exists and is correct (10 pts)
2. 'audit_log' table exists in database (15 pts)
3. 3 triggers exist on 'customers' table (20 pts)
4. Trigger logic verified via data state (30 pts):
   - Customer 1 email updated
   - Customer 60 deleted (does not exist)
   - audit_log contains INSERT (60), UPDATE (1), DELETE (60)
5. Export CSV exists (15 pts)
6. SQL script exists (10 pts)
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_audit_triggers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    updated_email_target = metadata.get('updated_email', "luis.goncalves@updated.com")

    # Read result
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

    # 1. Connection (10 pts)
    if result.get('connection_found'):
        if result.get('connection_exact_name'):
            score += 10
            feedback.append("DBeaver connection 'ChinookTriggers' verified.")
        else:
            score += 5
            feedback.append("DBeaver connection found but name mismatch (expected 'ChinookTriggers').")
    else:
        feedback.append("No correct DBeaver connection found pointing to chinook_triggers.db.")

    # 2. Audit Table (15 pts)
    if result.get('audit_table_exists'):
        score += 15
        feedback.append("Table 'audit_log' exists.")
    else:
        feedback.append("Table 'audit_log' missing.")

    # 3. Triggers (20 pts)
    trigger_count = result.get('trigger_count', 0)
    if trigger_count >= 3:
        score += 20
        feedback.append(f"Found {trigger_count} triggers on customers table.")
    elif trigger_count > 0:
        score += 10
        feedback.append(f"Found {trigger_count}/3 triggers on customers table.")
    else:
        feedback.append("No triggers found on customers table.")

    # 4. Logic & Data Verification (30 pts)
    logic_score = 0
    
    # Check update on customer 1
    actual_email = result.get('customer_1_email', '')
    if actual_email == updated_email_target:
        logic_score += 5
        feedback.append("Customer 1 email update verified in database.")
    else:
        feedback.append(f"Customer 1 email incorrect. Got '{actual_email}'.")

    # Check insert/delete of customer 60
    if not result.get('customer_60_exists'):
        logic_score += 5
        feedback.append("Customer 60 correctly does not exist (was deleted).")
    else:
        feedback.append("Customer 60 still exists in table (Delete failed).")

    # Check audit log entries
    audit_data = result.get('audit_log_data', [])
    
    # Look for INSERT of 60
    has_insert = any(r.get('operation') == 'INSERT' and str(r.get('record_id')) == '60' for r in audit_data)
    # Look for UPDATE of 1
    has_update = any(r.get('operation') == 'UPDATE' and str(r.get('record_id')) == '1' for r in audit_data)
    # Look for DELETE of 60
    has_delete = any(r.get('operation') == 'DELETE' and str(r.get('record_id')) == '60' for r in audit_data)

    if has_insert:
        logic_score += 7
        feedback.append("Audit log contains INSERT for ID 60.")
    if has_update:
        logic_score += 6
        feedback.append("Audit log contains UPDATE for ID 1.")
    if has_delete:
        logic_score += 7
        feedback.append("Audit log contains DELETE for ID 60.")

    score += logic_score

    # 5. File Deliverables (25 pts)
    # CSV (15 pts)
    if result.get('csv_exists') and result.get('csv_size') > 10:
        score += 15
        feedback.append("Export CSV found.")
    else:
        feedback.append("Export CSV missing or empty.")

    # SQL Script (10 pts)
    if result.get('sql_exists') and result.get('sql_size') > 10:
        score += 10
        feedback.append("SQL script found.")
    else:
        feedback.append("SQL script missing or empty.")

    # Final check
    passed = score >= 60 and result.get('audit_table_exists') and trigger_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }