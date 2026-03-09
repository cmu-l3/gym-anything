#!/usr/bin/env python3
"""
Verifier for create_summary_table task.

Verifies that the agent created and populated the 'EmployeeSalesSummary' table
correctly by parsing the HSQLDB script inside the saved ODB file.
"""

import json
import os
import zipfile
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_summary_table(traj, env_info, task_info):
    """
    Verify the ODB file contains the correct schema and data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rows = metadata.get('expected_rows', 3)
    # Ground truth for Chinook database
    ground_truth = metadata.get('ground_truth_values', [
        {"id": 3, "name": "Jane Peacock", "customers": 21, "invoices": 146, "sales": 833.04},
        {"id": 4, "name": "Margaret Park", "customers": 20, "invoices": 140, "sales": 775.40},
        {"id": 5, "name": "Steve Johnson", "customers": 18, "invoices": 126, "sales": 720.16}
    ])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Modification (Anti-Gaming)
    if not result_data.get("file_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not modified. Ensure you saved the file (Ctrl+S)."
        }
    score += 5
    feedback_parts.append("File modified")

    # 3. Retrieve and Extract ODB File
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    script_content = ""
    try:
        copy_from_env("/tmp/task_output.odb", temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 5, "feedback": "Saved file is not a valid ODB archive."}

        with zipfile.ZipFile(temp_odb.name, 'r') as zf:
            if 'database/script' in zf.namelist():
                script_content = zf.read('database/script').decode('utf-8', errors='ignore')
            else:
                return {"passed": False, "score": 5, "feedback": "Corrupt ODB: missing database/script."}
    except Exception as e:
        return {"passed": False, "score": 5, "feedback": f"Failed to inspect database file: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 4. Parse HSQLDB Script for Table Creation
    # Looking for: CREATE TABLE "EmployeeSalesSummary" (...)
    # Regex handles optional PUBLIC schema and quoting
    table_pattern = re.compile(
        r'CREATE\s+TABLE\s+(?:PUBLIC\.)?"?EmployeeSalesSummary"?\s*\((.+?)\)', 
        re.IGNORECASE | re.DOTALL
    )
    table_match = table_pattern.search(script_content)
    
    if not table_match:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Table 'EmployeeSalesSummary' not found in database. Did you create it and SAVE the file?"
        }
    
    score += 20
    feedback_parts.append("Table created")
    
    # 5. Verify Columns
    # We look for column names in the CREATE statement body
    create_body = table_match.group(1).upper()
    required_cols = ["EMPLOYEEID", "FULLNAME", "TITLE", "TOTALCUSTOMERS", "TOTALINVOICES", "TOTALSALESAMOUNT"]
    cols_found = 0
    for col in required_cols:
        if col in create_body:
            cols_found += 1
    
    if cols_found == len(required_cols):
        score += 20
        feedback_parts.append("All columns present")
    else:
        feedback_parts.append(f"Missing columns ({cols_found}/{len(required_cols)} found)")
        score += int(20 * (cols_found / len(required_cols)))

    # 6. Verify Data (INSERT Statements)
    # Looking for: INSERT INTO "EmployeeSalesSummary" VALUES(...)
    # HSQLDB 1.8 script format usually has one INSERT per line
    insert_pattern = re.compile(
        r'INSERT\s+INTO\s+(?:PUBLIC\.)?"?EmployeeSalesSummary"?\s+VALUES\((.+?)\)',
        re.IGNORECASE
    )
    
    inserts = insert_pattern.findall(script_content)
    
    if len(inserts) == expected_rows:
        score += 15
        feedback_parts.append(f"Correct row count ({len(inserts)})")
    else:
        feedback_parts.append(f"Incorrect row count: found {len(inserts)}, expected {expected_rows}")
        # Partial credit if at least some data exists
        if len(inserts) > 0:
            score += 5
    
    # 7. Verify Data Content
    # We need to parse the CSV-like values from the INSERT statements
    # This is a simple parser assuming standard HSQLDB formatting
    data_correct = 0
    total_checks = 0
    
    # Build a simple lookup from extracted data
    extracted_data = {}
    
    for row_str in inserts:
        # Simple splitting by comma, handling quotes crudely (usually sufficient for this task)
        # Better: use a csv parser on the string
        import csv
        reader = csv.reader([row_str], quotechar="'", skipinitialspace=True)
        try:
            row_vals = next(reader)
            if len(row_vals) >= 6:
                # Assuming order: Id, Name, Title, Cust, Inv, Sales
                e_id = int(row_vals[0])
                name = row_vals[1]
                cust = int(row_vals[3])
                inv = int(row_vals[4])
                sales = float(row_vals[5])
                extracted_data[e_id] = {"name": name, "cust": cust, "inv": inv, "sales": sales}
        except Exception:
            pass

    # Compare against ground truth
    for gt in ground_truth:
        e_id = gt['id']
        if e_id in extracted_data:
            total_checks += 3 # Name, counts, sales
            
            # Check Name
            if gt['name'].lower() in extracted_data[e_id]['name'].lower():
                data_correct += 1
            
            # Check Counts (Customer & Invoice)
            if (extracted_data[e_id]['cust'] == gt['customers'] and 
                extracted_data[e_id]['inv'] == gt['invoices']):
                data_correct += 1
                
            # Check Sales (tolerance 0.1)
            if abs(extracted_data[e_id]['sales'] - gt['sales']) < 0.1:
                data_correct += 1
        else:
            total_checks += 3 # Missed this employee entirely

    if total_checks > 0:
        data_score = int(40 * (data_correct / total_checks))
        score += data_score
        if data_correct == total_checks:
            feedback_parts.append("Data values correct")
        else:
            feedback_parts.append(f"Data verification partial ({data_correct}/{total_checks})")
    
    # Final Pass/Fail
    passed = score >= 60 and cols_found >= 4 and len(inserts) > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }