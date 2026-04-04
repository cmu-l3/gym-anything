#!/usr/bin/env python3
"""
Verifier for generate_customer_usernames task.

Task Requirements:
1. Add 'Username' column to 'Customer' table.
2. Populate 'Username' with lowercase email prefix (before '@').
3. Save changes.

Verification Strategy:
1. Parse the extracted HSQLDB script file (INSERT statements).
2. Validate schema: Check if new values exist in the INSERTs.
3. Validate logic: Check if Username == lower(Email.split('@')[0]).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_insert(line):
    """
    Parses a HSQLDB INSERT statement line into a list of values.
    Example: INSERT INTO "Customer" VALUES(1,'Name',...,'email@ex.com',...)
    Handles quoted strings and numbers.
    """
    # Simple regex to find the content inside VALUES(...)
    # Note: This is a simplified parser. HSQLDB 1.8 script format is fairly regular.
    match = re.search(r'VALUES\((.*)\)', line)
    if not match:
        return []
    
    raw_values = match.group(1)
    
    # Split by comma, respecting single quotes
    values = []
    current_val = []
    in_quote = False
    i = 0
    while i < len(raw_values):
        char = raw_values[i]
        if char == "'" and (i == 0 or raw_values[i-1] != '\\'):
            in_quote = not in_quote
            current_val.append(char)
        elif char == ',' and not in_quote:
            # End of value
            val_str = "".join(current_val).strip()
            # Clean up quotes
            if val_str.startswith("'") and val_str.endswith("'"):
                val_str = val_str[1:-1]
            values.append(val_str)
            current_val = []
        else:
            current_val.append(char)
        i += 1
    
    # Append last value
    if current_val:
        val_str = "".join(current_val).strip()
        if val_str.startswith("'") and val_str.endswith("'"):
            val_str = val_str[1:-1]
        values.append(val_str)
        
    return values

def verify_generate_customer_usernames(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
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

    # Check if file was modified (Anti-gaming)
    if not result.get("file_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not saved/modified. Remember to save (Ctrl+S)."
        }

    # Retrieve and parse the HSQLDB script
    script_path = result.get("script_path")
    if not script_path or not result.get("script_extracted", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Could not read database script. Save might have failed."
        }

    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env(script_path, temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve DB script: {e}"}
    finally:
        if os.path.exists(temp_script.name):
            os.unlink(temp_script.name)

    # ANALYSIS
    customer_inserts = [l for l in script_lines if 'INSERT INTO "Customer"' in l]
    
    if not customer_inserts:
        return {"passed": False, "score": 0, "feedback": "No customer records found in database."}

    # Analyze first record to detect schema change
    # Original Customer table has 13 columns.
    # New schema should have 14 columns (or more).
    first_row = parse_hsqldb_insert(customer_inserts[0])
    col_count = len(first_row)
    
    score_schema = 0
    score_data = 0
    score_complete = 0
    feedback_parts = []

    # 1. Schema Check
    if col_count > 13:
        score_schema = 20
        feedback_parts.append("Schema check passed: New column detected.")
    else:
        feedback_parts.append(f"Schema check failed: Expected >13 columns, found {col_count}.")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Data Logic Check
    # Email is column index 11 (0-based) in original schema
    # Username is likely the last column (index col_count - 1)
    email_idx = 11
    username_idx = col_count - 1
    
    correct_count = 0
    total_rows = len(customer_inserts)
    
    for line in customer_inserts:
        vals = parse_hsqldb_insert(line)
        if len(vals) <= username_idx:
            continue
            
        email = vals[email_idx]
        username = vals[username_idx]
        
        # Logic: username = lower(email_prefix)
        expected_username = email.split('@')[0].lower()
        
        if username == expected_username:
            correct_count += 1
    
    # Scoring
    # Data transformation score (max 60)
    if total_rows > 0:
        accuracy = correct_count / total_rows
        score_data = int(accuracy * 60)
    
    # Completeness score (max 20)
    if correct_count == 59: # 59 is the known row count
        score_complete = 20
        feedback_parts.append("All 59 records updated correctly.")
    elif correct_count > 0:
        score_complete = 10
        feedback_parts.append(f"Partial update: {correct_count}/59 correct.")
    else:
        feedback_parts.append("No records match the expected username format.")

    total_score = score_schema + score_data + score_complete
    
    passed = total_score >= 80

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }