#!/usr/bin/env python3
"""
Verifier for chinook_blob_management task.

Scoring Criteria:
1. Table `employee_badges` exists (10 pts)
2. Columns defined correctly (BadgeId, EmployeeId, BadgeData, IssueDate) (10 pts)
3. Foreign Key constraint exists (15 pts)
4. Record inserted for Andrew Adams (EmployeeId=1) (15 pts)
5. Binary Data Integrity in DB matches source (25 pts)
6. Binary Data Export file matches source (15 pts)
7. DDL Script Saved (10 pts)

Total: 100 points
Pass Threshold: 65 points (Must have valid table + data integrity)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_blob_management(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    source_hash = result.get("source_hash", "source_missing")
    export_exists = result.get("export_exists", False)
    export_hash = result.get("export_hash", "")
    ddl_exists = result.get("ddl_exists", False)
    
    db_state = result.get("db_state", {})
    table_exists = db_state.get("table_exists", False)
    columns_correct = db_state.get("columns_correct", False)
    fk_exists = db_state.get("fk_exists", False)
    record_exists = db_state.get("record_exists", False)
    blob_hash = db_state.get("blob_hash", "")
    
    # 1. Table Exists (10)
    if table_exists:
        score += 10
        feedback_parts.append("Table 'employee_badges' created.")
    else:
        feedback_parts.append("Table 'employee_badges' NOT found.")

    # 2. Columns Correct (10)
    if columns_correct:
        score += 10
        feedback_parts.append("Columns defined correctly.")
    elif table_exists:
        found = db_state.get("columns_found", [])
        feedback_parts.append(f"Columns incorrect. Found: {found}")

    # 3. Foreign Key (15)
    if fk_exists:
        score += 15
        feedback_parts.append("Foreign Key constraint verified.")
    else:
        feedback_parts.append("Foreign Key constraint missing or incorrect.")

    # 4. Record Inserted (15)
    if record_exists:
        score += 15
        feedback_parts.append("Record for Andrew Adams found.")
    else:
        feedback_parts.append("Record for EmployeeId=1 NOT found.")

    # 5. DB Blob Integrity (25)
    # This is critical - did they actually upload the binary correctly?
    if blob_hash == source_hash and source_hash != "source_missing":
        score += 25
        feedback_parts.append("Image data stored correctly in database.")
    elif record_exists:
        feedback_parts.append("Image data stored, but hash mismatch (corruption or wrong file).")
    else:
        feedback_parts.append("No image data to verify.")

    # 6. Export Integrity (15)
    # Checks if they can use the tool to extract data back out
    if export_exists:
        if export_hash == source_hash:
            score += 15
            feedback_parts.append("Exported file matches original source.")
        else:
            score += 5 # Partial credit for exporting *something*
            feedback_parts.append("Exported file exists but content mismatch.")
    else:
        feedback_parts.append("Exported file 'verified_badge.png' not found.")

    # 7. DDL Script (10)
    if ddl_exists:
        score += 10
        feedback_parts.append("DDL script saved.")
    else:
        feedback_parts.append("DDL script not found.")

    # Determine pass/fail
    # Pass threshold 65 means they need at least:
    # Table (10) + Columns (10) + Record (15) + DB Blob (25) = 60 + partial others
    # OR
    # Table (10) + Columns (10) + FK (15) + Record (15) + Export (15) = 65
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }