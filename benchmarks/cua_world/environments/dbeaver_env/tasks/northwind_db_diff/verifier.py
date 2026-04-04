#!/usr/bin/env python3
"""
Verifier for northwind_db_diff task.
"""

import json
import base64
import csv
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_db_diff(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Connection Verification (16 pts)
    if result.get('conn_prod_exists'):
        score += 8
        feedback.append("NorthwindProd connection created.")
    else:
        feedback.append("Missing 'NorthwindProd' connection.")

    if result.get('conn_staging_exists'):
        score += 8
        feedback.append("NorthwindStaging connection created.")
    else:
        feedback.append("Missing 'NorthwindStaging' connection.")

    # 2. CSV Report Verification (54 pts)
    csv_exists = result.get('csv_exists')
    csv_b64 = result.get('csv_content_b64', "")
    
    if csv_exists and csv_b64:
        score += 5 # File exists
        try:
            csv_text = base64.b64decode(csv_b64).decode('utf-8')
            reader = csv.DictReader(io.StringIO(csv_text))
            rows = list(reader)
            
            # Check Headers
            headers = reader.fieldnames if reader.fieldnames else []
            required_headers = ['ChangeType', 'TableName', 'RecordIdentifier', 'FieldName', 'OldValue', 'NewValue']
            # Case insensitive check
            header_map = {h.lower(): h for h in headers}
            missing_headers = [h for h in required_headers if h.lower() not in header_map]
            
            if not missing_headers:
                score += 7
                feedback.append("CSV Headers format correct.")
                
                # Check Content Logic
                # Ground truth expectations
                # Product: 3 INSERTs, 5 UPDATEs
                # Customer: 2 DELETEs
                # Category: 1 INSERT
                # OrderDetail: 4 UPDATEs
                
                inserts = [r for r in rows if r.get(header_map['changetype'], '').upper() == 'INSERT']
                updates = [r for r in rows if r.get(header_map['changetype'], '').upper() == 'UPDATE']
                deletes = [r for r in rows if r.get(header_map['changetype'], '').upper() == 'DELETE']
                
                # Check Product Inserts
                prod_inserts = [r for r in inserts if 'Product' in r.get(header_map['tablename'], '')]
                if len(prod_inserts) >= 3:
                    score += 10
                    feedback.append("Identified Product INSERTs.")
                
                # Check Product Updates
                prod_updates = [r for r in updates if 'Product' in r.get(header_map['tablename'], '')]
                if len(prod_updates) >= 5:
                    score += 12
                    feedback.append("Identified Product UPDATEs.")

                # Check Customer Deletes
                cust_deletes = [r for r in deletes if 'Customer' in r.get(header_map['tablename'], '')]
                if len(cust_deletes) >= 2:
                    score += 10
                    feedback.append("Identified Customer DELETEs.")
                
                # Check Category Insert
                cat_inserts = [r for r in inserts if 'Category' in r.get(header_map['tablename'], '')]
                if len(cat_inserts) >= 1:
                    score += 5
                    feedback.append("Identified Category INSERT.")
                
                # Check OrderDetail Updates
                od_updates = [r for r in updates if 'OrderDetail' in r.get(header_map['tablename'], '')]
                if len(od_updates) >= 4:
                    score += 5
                    feedback.append("Identified OrderDetail UPDATEs.")

            else:
                feedback.append(f"CSV missing headers: {', '.join(missing_headers)}")
        except Exception as e:
            feedback.append(f"Error parsing CSV: {str(e)}")
    else:
        feedback.append("Diff Report CSV not found.")

    # 3. SQL Script Verification (30 pts)
    sql_exists = result.get('sql_exists')
    sync_success = result.get('sync_success')
    sync_error = result.get('sync_error')
    
    if sql_exists:
        score += 5 # File exists
        
        # Keyword check
        sql_b64 = result.get('sql_content_b64', "")
        try:
            sql_text = base64.b64decode(sql_b64).decode('utf-8').upper()
            if "INSERT" in sql_text and "UPDATE" in sql_text and "DELETE" in sql_text:
                score += 5
                feedback.append("SQL script contains required operations.")
        except:
            pass

        # Execution check
        if sync_success:
            score += 20
            feedback.append("SQL Synchronization script successfully verified against database.")
        else:
            feedback.append(f"SQL Script failed verification execution: {sync_error}")
    else:
        feedback.append("Synchronization SQL script not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }