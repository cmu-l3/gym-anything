#!/usr/bin/env python3
"""
Verifier for query_long_rock_tracks task.

Verifies that the agent created a saved query in LibreOffice Base with the correct logic.
1. Parses the ODB file (ZIP archive) to read content.xml.
2. Extracts the SQL command for the query 'DeepCutsPlaylist'.
3. Checks SQL for required logic:
   - Filters for Rock/Metal
   - Filters for > 300,000 ms
   - Filters for Composer IS NOT NULL
   - Includes duration calculation
   - Sorts results
4. Checks that the database file was actually saved.
"""

import json
import os
import zipfile
import tempfile
import xml.etree.ElementTree as ET
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_query_long_rock_tracks(traj, env_info, task_info):
    """
    Verify the DeepCutsPlaylist query creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('expected_query_name', 'DeepCutsPlaylist')
    
    # 1. Retrieve Result JSON and ODB file
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    odb_local_path = os.path.join(temp_dir, "chinook.odb")
    
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        copy_from_env("/tmp/result_chinook.odb", odb_local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 2. Check if file was modified (saved)
    if result_data.get("file_modified", False):
        score += 10
        feedback_parts.append("Database file saved")
    else:
        feedback_parts.append("Database file NOT saved (changes may be lost)")

    # 3. Parse ODB to find the query
    query_found = False
    sql_command = ""
    
    try:
        if not zipfile.is_zipfile(odb_local_path):
            return {"passed": False, "score": score, "feedback": "Result file is not a valid ODB/ZIP archive"}
            
        with zipfile.ZipFile(odb_local_path, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": score, "feedback": "Corrupt ODB: content.xml missing"}
                
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Namespaces in ODB content.xml
                ns = {
                    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }
                
                # Look for <db:query> inside <db:queries>
                # Structure: office:body -> office:database -> db:queries -> db:query
                queries = root.findall('.//db:query', ns)
                for q in queries:
                    name = q.get(f"{{{ns['db']}}}name")
                    if name == expected_query_name:
                        query_found = True
                        sql_command = q.get(f"{{{ns['db']}}}command", "")
                        break
                        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing ODB file: {str(e)}"}

    # 4. Evaluate the SQL
    if query_found:
        score += 20
        feedback_parts.append(f"Query '{expected_query_name}' found")
        
        # Normalize SQL for checking
        sql_upper = sql_command.upper()
        
        # Check criteria
        
        # Criterion: Genre filtering (Rock/Metal)
        # Could be done via JOIN with Genre table OR via GenreId (1=Rock, 3=Metal)
        has_genre_names = ("'ROCK'" in sql_upper or '"ROCK"' in sql_upper) and ("'METAL'" in sql_upper or '"METAL"' in sql_upper)
        has_genre_ids = ("1" in sql_upper and "3" in sql_upper and ("IN" in sql_upper or "OR" in sql_upper))
        
        if has_genre_names or has_genre_ids:
            score += 20
            feedback_parts.append("Genre filter detected")
        else:
            feedback_parts.append("Genre filter missing or incorrect (needs Rock/Metal)")

        # Criterion: Duration > 5 mins
        if "300000" in sql_upper and ">" in sql_upper:
            score += 20
            feedback_parts.append("Duration filter (> 5 min) detected")
        else:
            feedback_parts.append("Duration filter missing (needs > 300000)")

        # Criterion: Composer NOT NULL
        if "COMPOSER" in sql_upper and "NOT NULL" in sql_upper:
            score += 10
            feedback_parts.append("Composer filter detected")
        else:
            feedback_parts.append("Composer filter missing")

        # Criterion: Calculation
        if "/ 60000" in sql_upper or "/ 60000.0" in sql_upper:
            score += 10
            feedback_parts.append("Duration calculation detected")
        else:
            feedback_parts.append("Duration calculation missing")

        # Criterion: Sorting
        if "ORDER BY" in sql_upper and ("DESC" in sql_upper or "desc" in sql_command):
            score += 10
            feedback_parts.append("Sorting detected")
        else:
            feedback_parts.append("Sorting missing")

    else:
        feedback_parts.append(f"Query '{expected_query_name}' NOT found in database")

    # Final logic
    passed = score >= 70 and query_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "query_found": query_found,
            "sql_extracted": sql_command
        }
    }