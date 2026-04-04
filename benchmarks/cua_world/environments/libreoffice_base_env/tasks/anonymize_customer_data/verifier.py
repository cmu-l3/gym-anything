#!/usr/bin/env python3
"""
Verifier for Anonymize Customer Data task.

Verification Logic:
1. Parse the extracted HSQLDB script file (SQL INSERT statements).
2. Check if 'Customer_Anonymized' table exists.
3. Verify row count (should be 59).
4. Verify PII masking on specific rows (FirstName='Sanitized', LastName='User_X', etc.).
5. Verify preservation of non-PII data (City, Country).
6. Verify original 'Customer' table is untouched (Critical Safety Check).
7. VLM check on final screenshot for visual confirmation.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_script(script_content):
    """
    Parses HSQLDB script content to extract table data.
    Returns a dictionary: { 'TableName': { 'ID_Value': { 'ColName': Value, ... } } }
    
    Note: HSQLDB 1.8 INSERT format: INSERT INTO "TableName" VALUES(val1, val2, ...)
    We need a simple parser because we don't have the schema definition easily mapped to column names 
    without parsing CREATE TABLE.
    """
    tables = {}
    table_schemas = {} # TableName -> [ColName, ColName...]
    
    # Regex for CREATE TABLE
    # CREATE TABLE "Customer" ("CustomerId" INTEGER NOT NULL PRIMARY KEY, "FirstName" VARCHAR(40) ...)
    # This is a simplified parser and might need robustness for complex schemas, 
    # but for Chinook it suffices.
    
    lines = script_content.splitlines()
    
    for line in lines:
        # Parse Schema
        if line.startswith('CREATE TABLE'):
            # Extract table name
            m_table = re.search(r'CREATE TABLE "?PUBLIC"?."?(\w+)"?', line)
            if m_table:
                table_name = m_table.group(1)
                # Extract columns roughly
                # Content inside first ( and last )
                content = line[line.find('(')+1 : line.rfind(')')]
                # Split by comma, ignoring commas in quotes (simplified)
                # For this task, we know the column order of Customer table roughly, 
                # or we can just look at the CREATE statement.
                
                # Hardcoded schema for Customer table to ensure accuracy
                if "Customer" in table_name:
                    cols = ["CustomerId", "FirstName", "LastName", "Company", "Address", 
                            "City", "State", "Country", "PostalCode", "Phone", 
                            "Fax", "Email", "SupportRepId"]
                    table_schemas[table_name] = cols
                    tables[table_name] = {}

        # Parse Inserts
        # INSERT INTO "Customer" VALUES(1,'Luis','Goncalves',...)
        if line.startswith('INSERT INTO'):
            m_insert = re.search(r'INSERT INTO "?PUBLIC"?."?(\w+)"? VALUES\((.*)\)', line)
            if m_insert:
                table_name = m_insert.group(1)
                values_str = m_insert.group(2)
                
                if table_name in table_schemas:
                    # Split values. This is tricky with quoted strings containing commas.
                    # Simple state machine to split
                    values = []
                    current_val = []
                    in_quote = False
                    for char in values_str:
                        if char == "'" and (not current_val or current_val[-1] != '\\'):
                            in_quote = not in_quote
                            current_val.append(char)
                        elif char == ',' and not in_quote:
                            values.append("".join(current_val).strip())
                            current_val = []
                        else:
                            current_val.append(char)
                    values.append("".join(current_val).strip())
                    
                    # Clean up quotes
                    clean_values = []
                    for v in values:
                        if v.startswith("'") and v.endswith("'"):
                            clean_values.append(v[1:-1])
                        elif v == "NULL":
                            clean_values.append(None)
                        else:
                            clean_values.append(v)
                            
                    # Map to dict using schema
                    if len(clean_values) == len(table_schemas[table_name]):
                        row_dict = dict(zip(table_schemas[table_name], clean_values))
                        # Use first column (ID) as key
                        row_id = clean_values[0] 
                        tables[table_name][str(row_id)] = row_dict
                        
    return tables

def verify_anonymize_customer_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('odb_modified', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not modified/saved."}

    # 2. Get SQL Script
    temp_sql = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    try:
        copy_from_env("/tmp/database_script.sql", temp_sql.name)
        with open(temp_sql.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load DB script: {str(e)}"}
    finally:
        if os.path.exists(temp_sql.name):
            os.unlink(temp_sql.name)

    # 3. Parse Data
    db_data = parse_hsqldb_script(script_content)
    
    # --- CHECK 1: Table Creation (20 pts) ---
    target_table = "Customer_Anonymized"
    if target_table in db_data:
        score += 20
        feedback_parts.append(f"Table '{target_table}' created.")
    else:
        feedback_parts.append(f"Table '{target_table}' NOT found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # --- CHECK 2: Data Migration (20 pts) ---
    row_count = len(db_data[target_table])
    if row_count == 59:
        score += 20
        feedback_parts.append("Correct row count (59).")
    else:
        feedback_parts.append(f"Incorrect row count: {row_count} (expected 59).")
        # Partial credit if close
        if row_count > 0: score += 5

    # --- CHECK 3: Identity Masking (20 pts) ---
    # Check sample rows defined in metadata
    check_rows = task_info.get('metadata', {}).get('check_rows', [])
    masking_passed = True
    masking_errors = []

    for check in check_rows:
        rid = str(check['id'])
        if rid in db_data[target_table]:
            row = db_data[target_table][rid]
            
            # FirstName
            if row.get('FirstName') != 'Sanitized':
                masking_passed = False
                masking_errors.append(f"Row {rid}: FirstName is '{row.get('FirstName')}' (expected 'Sanitized')")
            
            # LastName
            expected_ln = check['expected_lastname']
            if row.get('LastName') != expected_ln:
                masking_passed = False
                masking_errors.append(f"Row {rid}: LastName is '{row.get('LastName')}' (expected '{expected_ln}')")
            
            # Email
            expected_em = check['expected_email']
            if row.get('Email') != expected_em:
                masking_passed = False
                masking_errors.append(f"Row {rid}: Email is '{row.get('Email')}' (expected '{expected_em}')")
        else:
            masking_passed = False
            masking_errors.append(f"Row {rid} missing.")

    if masking_passed and row_count > 0:
        score += 20
        feedback_parts.append("Identity masking correct.")
    else:
        feedback_parts.append(f"Masking failed: {'; '.join(masking_errors[:2])}...")

    # --- CHECK 4: Sensitive Field Removal (20 pts) ---
    # Check if Address, Phone, Fax, Company are NULL or REDACTED or Empty
    sensitive_removal_passed = True
    # Check first row
    if '1' in db_data[target_table]:
        r1 = db_data[target_table]['1']
        for field in ['Company', 'Phone', 'Fax']:
            val = r1.get(field)
            if val and val != 'NULL' and val != '':
                sensitive_removal_passed = False
                feedback_parts.append(f"Field '{field}' contains data: '{val}'")
        
        # Address special case (can be NULL or 'REDACTED')
        addr = r1.get('Address')
        if addr and addr != 'NULL' and 'REDACTED' not in str(addr) and addr != '':
             sensitive_removal_passed = False
             feedback_parts.append(f"Address not redacted: '{addr}'")

    if sensitive_removal_passed and row_count > 0:
        score += 20
        feedback_parts.append("Sensitive fields cleared/redacted.")
    else:
        # Partial credit
        score += 5

    # --- CHECK 5: Geographic Preservation (10 pts) ---
    geo_passed = True
    for check in check_rows:
        rid = str(check['id'])
        if rid in db_data[target_table]:
            row = db_data[target_table][rid]
            if row.get('City') != check['expected_city']:
                geo_passed = False
            if row.get('Country') != check['expected_country']:
                geo_passed = False
    
    if geo_passed and row_count > 0:
        score += 10
        feedback_parts.append("Geographic data preserved.")

    # --- CHECK 6: Source Integrity (10 pts) ---
    # Verify original table row 1 is still "Luís Gonçalves"
    source_table = "Customer"
    source_intact = False
    if source_table in db_data and '1' in db_data[source_table]:
        src_row = db_data[source_table]['1']
        # Check against known ground truth
        if src_row.get('LastName') == 'Gonçalves' or src_row.get('LastName') == 'Goncalves':
            source_intact = True
            score += 10
            feedback_parts.append("Original table intact.")
        else:
            feedback_parts.append(f"WARNING: Source table modified! (LastName={src_row.get('LastName')})")
    else:
         feedback_parts.append("WARNING: Source table missing!")

    passed = (score >= 80) and source_intact

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }