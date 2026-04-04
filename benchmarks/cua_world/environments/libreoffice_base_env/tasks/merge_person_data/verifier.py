#!/usr/bin/env python3
"""
Verifier for merge_person_data task.

Checks:
1. ODB file modified (Anti-gaming)
2. 'Person' table creation (DDL check)
3. Correct columns in 'Person' table
4. Row counts for Customers and Employees (DML check)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_person_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_total = metadata.get('expected_total_rows', 67)
    expected_customers = metadata.get('expected_customer_rows', 59)
    expected_employees = metadata.get('expected_employee_rows', 8)

    # 1. Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve HSQLDB script
    remote_script_path = result.get('hsqldb_script_path')
    if not remote_script_path:
        return {"passed": False, "score": 0, "feedback": "Result missing script path"}

    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env(remote_script_path, temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load DB script: {e}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: File Modification (Anti-gaming) ---
    if result.get('file_modified', False):
        score += 10
        feedback_parts.append("Database saved")
    else:
        feedback_parts.append("Database NOT modified (did you save?)")

    # --- Check 2: Table Existence (DDL) ---
    # Look for CREATE TABLE "Person" or CREATE TABLE PUBLIC."Person"
    # Regex handles potential quoting and casing
    table_regex = re.compile(r'CREATE\s+TABLE\s+(?:PUBLIC\.)?"?Person"?', re.IGNORECASE)
    if table_regex.search(script_content):
        score += 20
        feedback_parts.append("'Person' table created")
        
        # --- Check 3: Column Definitions ---
        # We look for the column names in the CREATE statement lines (simplified check)
        # HSQLDB script usually puts the whole CREATE statement on one line or split cleanly
        # We'll just search the whole file for the columns in proximity to the table creation if possible,
        # but simple string search is often robust enough for the DDL section.
        missing_cols = []
        for col in ['FirstName', 'LastName', 'Email', 'Role']:
            # Case insensitive search for column definition
            if not re.search(fr'"{col}"\s+\w+', script_content, re.IGNORECASE):
                missing_cols.append(col)
        
        if not missing_cols:
            score += 20
            feedback_parts.append("All columns present")
        else:
            feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}")
    else:
        feedback_parts.append("'Person' table NOT found")

    # --- Check 4: Data Insertion (DML) ---
    # Look for INSERT INTO ... "Person" ... VALUES (...)
    # HSQLDB text script format: INSERT INTO "Person" VALUES(..., 'Customer')
    
    # Normalize script content for easier searching
    # Remove newlines to handle multi-line inserts if they happen (unlikely in script file but possible)
    
    # We count occurrences of 'Customer' and 'Employee' in INSERT statements targeting 'Person'
    
    # Find all insert lines for Person table
    insert_pattern = re.compile(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"?Person"?\s+VALUES\s*\((.*?)\)', re.IGNORECASE)
    person_inserts = insert_pattern.findall(script_content)
    
    total_inserts = len(person_inserts)
    customer_count = 0
    employee_count = 0
    
    for val_str in person_inserts:
        if "'Customer'" in val_str:
            customer_count += 1
        if "'Employee'" in val_str:
            employee_count += 1

    # Scoring Data
    data_score = 0
    
    # Check Customer Data
    if customer_count == expected_customers:
        data_score += 20
        feedback_parts.append(f"Customer rows correct ({customer_count})")
    elif customer_count > 0:
        data_score += 10
        feedback_parts.append(f"Partial customer rows ({customer_count}/{expected_customers})")
    else:
        feedback_parts.append("No Customer rows found")

    # Check Employee Data
    if employee_count == expected_employees:
        data_score += 20
        feedback_parts.append(f"Employee rows correct ({employee_count})")
    elif employee_count > 0:
        data_score += 10
        feedback_parts.append(f"Partial employee rows ({employee_count}/{expected_employees})")
    else:
        feedback_parts.append("No Employee rows found")

    # Check Total/Exactness
    if total_inserts == expected_total and customer_count == expected_customers and employee_count == expected_employees:
        data_score += 10
        feedback_parts.append("Total row count exact")
    elif total_inserts > 0:
         feedback_parts.append(f"Total rows: {total_inserts} (Expected: {expected_total})")

    score += data_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }