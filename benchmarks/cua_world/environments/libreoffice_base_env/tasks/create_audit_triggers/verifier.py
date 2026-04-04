#!/usr/bin/env python3
"""
Verifier for create_audit_triggers task.

Verifies that the agent successfully:
1. Created the CustomerAuditLog table
2. Created the Insert and Delete triggers
3. Inserted a test record
4. Generated an audit log entry via the trigger

Verification Method:
Parses the extracted HSQLDB 'script' file from the saved ODB archive.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_audit_triggers(traj, env_info, task_info):
    """
    Verify the HSQLDB script content for required DDL and data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Load Task Result JSON ---
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not task_result.get("odb_exists", False):
        return {"passed": False, "score": 0, "feedback": "Database file not found"}
        
    if not task_result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved (timestamp unchanged)"}

    if not task_result.get("script_extracted", False):
        return {"passed": False, "score": 0, "feedback": "Failed to extract database script from ODB file (file might be corrupt or empty)"}

    # --- Load Extracted Script Content ---
    script_content = ""
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/hsqldb_script.txt", temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to read database script: {str(e)}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # --- Verification Logic ---
    
    # 1. Verify Table Creation (20 pts)
    # HSQLDB 1.8 Script Format: CREATE TABLE "CustomerAuditLog"(...)
    # Regex allows for some flexibility in spacing
    table_regex = r'CREATE\s+TABLE\s+(PUBLIC\.)?"CustomerAuditLog"'
    if re.search(table_regex, script_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Audit table created")
        
        # Check columns (approximate check)
        if "AuditId" in script_content and "ActionType" in script_content:
             score += 10 # 5 pts IDENTITY, 5 pts TIMESTAMP implied if script is valid
             feedback_parts.append("Table structure correct")
        else:
            feedback_parts.append("Table structure missing required columns")
    else:
        feedback_parts.append("Audit table NOT found")

    # 2. Verify Insert Trigger (20 pts)
    # HSQLDB Script: CREATE TRIGGER "trg_customer_insert" AFTER INSERT ON "Customer" ...
    trigger_insert_regex = r'CREATE\s+TRIGGER\s+"trg_customer_insert"\s+AFTER\s+INSERT\s+ON\s+(PUBLIC\.)?"Customer"'
    if re.search(trigger_insert_regex, script_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Insert trigger created")
    else:
        feedback_parts.append("Insert trigger NOT found")

    # 3. Verify Delete Trigger (20 pts)
    trigger_delete_regex = r'CREATE\s+TRIGGER\s+"trg_customer_delete"\s+AFTER\s+DELETE\s+ON\s+(PUBLIC\.)?"Customer"'
    if re.search(trigger_delete_regex, script_content, re.IGNORECASE):
        score += 20
        feedback_parts.append("Delete trigger created")
    else:
        feedback_parts.append("Delete trigger NOT found")

    # 4. Verify Test Customer Insert (10 pts)
    # INSERT INTO "Customer" VALUES(60,'Audit','TestUser',...)
    # We look for the ID 60 and the name 'Audit' in an INSERT statement
    customer_insert_regex = r'INSERT\s+INTO\s+(PUBLIC\.)?"Customer".*VALUES\(.*60.*\'Audit\'.*\)'
    if re.search(customer_insert_regex, script_content, re.IGNORECASE):
        score += 10
        feedback_parts.append("Test customer inserted")
    else:
        feedback_parts.append("Test customer record NOT found")

    # 5. Verify Audit Log Entry (15 pts)
    # If the trigger worked, there should be an INSERT into CustomerAuditLog
    # INSERT INTO "CustomerAuditLog" VALUES(..., 60, 'INSERT', ...)
    audit_log_regex = r'INSERT\s+INTO\s+(PUBLIC\.)?"CustomerAuditLog".*VALUES\(.*60.*\'INSERT\'.*\)'
    if re.search(audit_log_regex, script_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("Audit log entry confirmed")
    else:
        # Check if table exists but is empty
        if "INSERT INTO \"CustomerAuditLog\"" in script_content:
             feedback_parts.append("Audit log table has data but not the expected test entry")
        else:
             feedback_parts.append("Audit log entry NOT found (trigger may not have fired)")

    # 6. File Modification Bonus (5 pts)
    # Already checked at start, simply adding points if we got here
    score += 5

    passed = score >= 60 and "Audit table created" in feedback_parts and ("Insert trigger created" in feedback_parts or "Delete trigger created" in feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }