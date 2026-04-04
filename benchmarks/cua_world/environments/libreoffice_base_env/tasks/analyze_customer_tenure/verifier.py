#!/usr/bin/env python3
"""
Verifier for analyze_customer_tenure task.

Verification Strategy:
1. Check if the ODB file was modified during the task.
2. Extract the 'content.xml' from the ODB (which is a ZIP file).
3. Parse the XML to find a query named 'LongTermLoyalty'.
4. Analyze the SQL command within the query for required logic:
   - Uses DATEDIFF function
   - Uses MIN and MAX aggregates
   - Filters for > 1095 days
   - References Customer and Invoice tables
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_customer_tenure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('query_name', 'LongTermLoyalty')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 1: Get Result JSON ---
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

    # Basic checks
    if not result.get('odb_exists', False):
        return {"passed": False, "score": 0, "feedback": "Database file not found"}
    
    if not result.get('odb_modified', False):
        feedback_parts.append("Warning: Database file was not saved/modified during task")
        # We continue checking in case they saved it very quickly or timestamps are tricky,
        # but usually this is a fail condition in strict mode.
    else:
        score += 10
        feedback_parts.append("Database file saved")

    # --- Step 2: Get ODB File ---
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    odb_path = "/tmp/chinook_result.odb" # Created by export_result.sh
    
    try:
        copy_from_env(odb_path, temp_odb.name)
    except Exception as e:
        # Fallback to home path
        try:
            copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        except Exception as e2:
            return {"passed": False, "score": score, "feedback": "Could not retrieve database file for inspection"}

    # --- Step 3: Analyze ODB Content ---
    query_found = False
    sql_command = ""
    
    try:
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": score, "feedback": "Database file is not a valid ODB archive"}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": score, "feedback": "Invalid ODB: content.xml missing"}
            
            with z.open('content.xml') as f:
                content_xml = f.read()
                
        # Parse XML
        # Namespaces are tricky in ODB, usually:
        # xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0"
        root = ET.fromstring(content_xml)
        
        # Find namespaces
        namespaces = dict([node for _, node in ET.iterparse(temp_odb.name, events=['start-ns'])])
        # Ensure 'db' is in namespaces if not auto-detected correctly or verify manual mapping
        if 'db' not in namespaces:
            namespaces['db'] = "urn:oasis:names:tc:opendocument:xmlns:database:1.0"

        # Search for queries
        # Path: office:body -> office:database -> db:queries -> db:query
        # We'll search recursively for db:query
        for query in root.findall(".//db:query", namespaces):
            name = query.get(f"{{{namespaces['db']}}}name")
            if name == expected_query_name:
                query_found = True
                sql_command = query.get(f"{{{namespaces['db']}}}command")
                break
                
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing ODB file: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # --- Step 4: Evaluate Query ---
    if not query_found:
        feedback_parts.append(f"Query '{expected_query_name}' NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    
    score += 20 # Query exists
    feedback_parts.append(f"Query '{expected_query_name}' found")
    
    # Analyze SQL Content
    sql_upper = sql_command.upper()
    
    # 1. Check for DATEDIFF (20 pts)
    if 'DATEDIFF' in sql_upper:
        score += 20
        feedback_parts.append("Uses DATEDIFF")
    else:
        feedback_parts.append("Missing DATEDIFF function")

    # 2. Check for Aggregates (20 pts)
    has_min = 'MIN' in sql_upper
    has_max = 'MAX' in sql_upper
    if has_min and has_max:
        score += 20
        feedback_parts.append("Uses MIN and MAX")
    elif has_min or has_max:
        score += 10
        feedback_parts.append("Uses partial aggregates")
    else:
        feedback_parts.append("Missing MIN/MAX aggregates")

    # 3. Check for Filtering > 1095 (20 pts)
    # Could be in HAVING or a nested WHERE
    if '1095' in sql_upper:
        score += 20
        feedback_parts.append("Filter value (1095) found")
    else:
        feedback_parts.append("Missing filter for 1095 days")

    # 4. Check Table References (10 pts)
    # Simple string check for table names
    # Note: HSQLDB might quote them like "Customer"
    has_customer = 'CUSTOMER' in sql_upper
    has_invoice = 'INVOICE' in sql_upper
    
    if has_customer and has_invoice:
        score += 10
        feedback_parts.append("References required tables")
    else:
        feedback_parts.append("Missing table references")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "query_name": expected_query_name,
            "sql_extracted": sql_command
        }
    }