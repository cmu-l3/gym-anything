#!/usr/bin/env python3
"""
Verifier for create_self_join_query task.

Verification Logic:
1. Inspects the submitted ODB file (which is a ZIP archive).
2. Parses 'content.xml' to find the saved query definition.
3. Checks if a query named 'EmployeeHierarchy' exists.
4. Extracts the SQL command from the query definition.
5. Performs static analysis on the SQL (Self Join, Left Join, Aliases).
6. Executes the extracted SQL against the reference SQLite database to verify correctness of output.
"""

import json
import sqlite3
import zipfile
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_self_join_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    reference_db_path = metadata.get('reference_db_path', '/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite')
    
    # 1. Retrieve the task result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not task_result.get("odb_modified", False):
        return {"passed": False, "score": 0, "feedback": "The database file was not modified. Did you save your changes?"}

    # 2. Retrieve the ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        copy_from_env("/tmp/submitted_chinook.odb", temp_odb.name)
        
        # 3. Parse content.xml from the ODB zip
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            with z.open('content.xml') as f:
                content_xml = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to inspect ODB file: {str(e)}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 4. Extract Query Definition
    query_name = "EmployeeHierarchy"
    found_query = False
    sql_command = ""
    
    try:
        # Namespaces in ODB content.xml
        namespaces = {
            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        root = ET.fromstring(content_xml)
        queries = root.findall('.//db:query', namespaces)
        
        for q in queries:
            name = q.get(f"{{{namespaces['db']}}}name")
            if name == query_name:
                found_query = True
                sql_command = q.get(f"{{{namespaces['db']}}}command")
                break
                
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"XML parsing error: {str(e)}"}

    if not found_query:
        return {"passed": False, "score": 0, "feedback": f"Query '{query_name}' not found in the database."}

    logger.info(f"Found SQL: {sql_command}")

    # 5. Scoring
    score = 0
    feedback = []
    
    # Static Analysis
    score += 15 # Found the query
    
    # Check for Self Join patterns (referencing Employee table twice)
    # Simple regex to count occurrences of "Employee" (case insensitive)
    if len(re.findall(r'Employee', sql_command, re.IGNORECASE)) >= 2:
        score += 15
        feedback.append("Self-join structure detected.")
    else:
        feedback.append("SQL does not appear to join 'Employee' table to itself.")

    # Check for LEFT JOIN
    if re.search(r'LEFT\s+(OUTER\s+)?JOIN', sql_command, re.IGNORECASE):
        score += 10
        feedback.append("LEFT JOIN used.")
    else:
        feedback.append("LEFT JOIN not found (required for including top-level manager).")

    # 6. Dynamic Verification (Execute against SQLite)
    # We might need to sanitize HSQLDB syntax to SQLite syntax if they differ significantly.
    # Common diffs: " vs ' quotes, || vs + for concat (standard SQL uses ||, HSQLDB and SQLite both support || or have compat modes).
    # LibreOffice Base often puts quotes around table/col names: "Employee"."FirstName". SQLite handles this fine.
    
    # Retrieve reference DB
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.sqlite')
    try:
        # We need to get the reference DB from the container to run locally
        copy_from_env(reference_db_path, temp_db.name)
        
        conn = sqlite3.connect(temp_db.name)
        cursor = conn.cursor()
        
        try:
            cursor.execute(sql_command)
            rows = cursor.fetchall()
            col_names = [description[0] for description in cursor.description]
            
            # Row Count Check
            if len(rows) == 8:
                score += 10
                feedback.append("Correct row count (8).")
            else:
                feedback.append(f"Incorrect row count: {len(rows)} (expected 8).")
            
            # Column Count Check
            if len(col_names) == 4:
                score += 10
                feedback.append("Correct column count.")
            else:
                feedback.append(f"Incorrect column count: {len(col_names)} (expected 4).")

            # Data Verification
            # Check Row 1 (Andrew Adams, General Manager, No Manager)
            # Find row where EmployeeName contains "Andrew" and "Adams"
            andrew_row = None
            for r in rows:
                # convert all to string for safe searching
                row_str = " ".join([str(x) for x in r])
                if "Andrew" in row_str and "Adams" in row_str:
                    andrew_row = r
                    break
            
            if andrew_row:
                # Andrew should have NULL/None manager
                # In the result, manager columns (indices 2 and 3 usually) should be None or empty
                # Note: aliases might not match exact order, but usually query follows select order.
                # Let's assume select order: EmpName, EmpTitle, MgrName, MgrTitle
                mgr_name_val = andrew_row[2]
                if mgr_name_val is None or mgr_name_val == "":
                    score += 10
                    feedback.append("General Manager correctly has no manager.")
                else:
                    feedback.append(f"General Manager has unexpected manager: {mgr_name_val}")
            else:
                feedback.append("Andrew Adams not found in results.")

            # Check a standard employee (e.g., Jane Peacock reports to Nancy Edwards)
            jane_row = None
            for r in rows:
                row_str = " ".join([str(x) for x in r])
                if "Jane" in row_str and "Peacock" in row_str:
                    jane_row = r
                    break
            
            if jane_row:
                if "Nancy" in str(jane_row) and "Edwards" in str(jane_row):
                    score += 10
                    feedback.append("Employee reporting relationship verified.")
                else:
                    feedback.append("Incorrect manager for Jane Peacock.")
            
            # Check sorting (by ID usually means Andrew (1) is first or last depending on direction)
            # Task asked for sorting by EmployeeId.
            # We can't strictly verify sorting order on the python list unless we assume the SELECT included ID, which the prompt didn't explicitly demand in the *output* columns (just "Sort by").
            # However, if the SQL works, we give points.
            
            # If we reached here without SQL error
            score += 20 # Functional query points

        except sqlite3.Error as e:
            feedback.append(f"SQL Execution failed on reference DB: {str(e)}. (Syntax might be specific to HSQLDB but usually compatible).")
            # If execution fails, we rely on static analysis scores accumulated so far.
            
    except Exception as e:
        feedback.append(f"Verification system error: {str(e)}")
    finally:
        if os.path.exists(temp_db.name):
            os.unlink(temp_db.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }