#!/usr/bin/env python3
"""
Verifier for analyze_storage_usage task.

Checks if the user created a specific SQL query in LibreOffice Base by inspecting
the saved ODB file (which is a ZIP archive containing XML definitions).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_storage_usage(traj, env_info, task_info):
    """
    Verify the GenreStorageStats query creation in LibreOffice Base.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('expected_query_name', 'GenreStorageStats')
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Task Result JSON
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

    # 2. Check File modification
    if not task_result.get("odb_exists", False):
        return {"passed": False, "score": 0, "feedback": "Database file not found"}
    
    if task_result.get("odb_modified", False):
        score += 10
        feedback_parts.append("Database saved successfully")
    else:
        feedback_parts.append("Warning: Database timestamp not updated (did you save?)")

    # 3. Retrieve and Inspect ODB File
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    odb_path = task_result.get("odb_path", "/home/ga/chinook.odb")
    
    try:
        copy_from_env(odb_path, temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid ODB/ZIP archive"}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": score, "feedback": "Corrupt ODB: content.xml missing"}
            
            with z.open('content.xml') as f:
                content_xml = f.read()
                
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to inspect ODB file: {str(e)}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 4. Parse XML to find the Query
    # Namespaces in ODF are tricky, usually xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0"
    try:
        root = ET.fromstring(content_xml)
        
        # Define namespaces
        namespaces = {
            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        # Find the query definition
        # Path: office:body -> office:database -> db:queries -> db:query
        query_elem = None
        
        # Search all db:query elements
        for q in root.findall(".//db:query", namespaces):
            name = q.get(f"{{{namespaces['db']}}}name")
            if name == expected_query_name:
                query_elem = q
                break
        
        if not query_elem:
            feedback_parts.append(f"Query '{expected_query_name}' NOT found in database")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
        score += 20
        feedback_parts.append(f"Query '{expected_query_name}' found")
        
        # Get SQL Command
        # It might be in 'db:command' attribute or 'db:file-based-database' structure
        sql_command = query_elem.get(f"{{{namespaces['db']}}}command", "")
        
        if not sql_command:
            # Sometimes it's a child element? In ODF 1.2 it's typically an attribute for simple queries
            feedback_parts.append("Could not extract SQL command text")
        else:
            sql_upper = sql_command.upper()
            
            # 5. SQL Logic Verification
            
            # Check JOINS
            if "JOIN" in sql_upper and "GENRE" in sql_upper and "TRACK" in sql_upper:
                score += 20
                feedback_parts.append("Joins tables correctly")
            else:
                feedback_parts.append("Missing JOIN or table references")
                
            # Check GROUP BY
            if "GROUP BY" in sql_upper:
                score += 20
                feedback_parts.append("Includes GROUP BY")
            else:
                feedback_parts.append("Missing GROUP BY clause")

            # Check Unit Conversion (Division)
            # 1048576 or 1024*1024
            if "1048576" in sql_upper or ("1024" in sql_upper and "*" in sql_upper):
                score += 20
                feedback_parts.append("Includes unit conversion logic")
            elif "/" in sql_upper:
                score += 10
                feedback_parts.append("Includes division but maybe wrong constant")
            else:
                feedback_parts.append("Missing unit conversion (division)")
                
            # Check Aggregates
            if "SUM" in sql_upper and "COUNT" in sql_upper:
                score += 10
                feedback_parts.append("Includes SUM and COUNT aggregates")
            else:
                feedback_parts.append("Missing required aggregate functions")
                
            # Check Ordering
            if "ORDER BY" in sql_upper and ("DESC" in sql_upper or "DESCENDING" in sql_upper):
                score += 10
                feedback_parts.append("Includes sorting (DESC)")
            else:
                feedback_parts.append("Missing or incorrect sorting")
                
            # Bonus: Check Aliases if possible (hard with just string match, but 'AS "TotalMB"' might exist)
            if 'AS "TotalMB"' in sql_command or 'AS "TOTALMB"' in sql_upper:
                feedback_parts.append("Alias 'TotalMB' found")

    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Failed to parse ODB content.xml"}

    # Final Score Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"sql_extracted": sql_command if 'sql_command' in locals() else "None"}
    }