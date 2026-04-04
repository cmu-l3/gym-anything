#!/usr/bin/env python3
"""
Verifier for create_crosstab_query task.

Verification Strategy:
1. Parse the saved LibreOffice Base (.odb) file.
2. The .odb file is a ZIP archive containing 'content.xml'.
3. 'content.xml' contains the query definitions in the <office:body> section.
4. We extract the SQL command for the query named 'CountrySalesPivot'.
5. We verify the SQL contains the required Pivot/Crosstab logic (CASE, SUM, GROUP BY).
6. We verify the file was modified during the task.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_crosstab_query(traj, env_info, task_info):
    """
    Verify that the user created a valid crosstab query in the ODB file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('expected_query_name', 'CountrySalesPivot')
    required_keywords = metadata.get('required_keywords', ["CASE", "SUM", "GROUP BY"])
    
    score = 0
    feedback_parts = []
    
    # Setup temporary files
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    
    try:
        # 1. Get the result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json.name)
            with open(temp_result_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file mechanics
        if not result.get('odb_exists'):
            return {"passed": False, "score": 0, "feedback": "Database file not found."}
            
        if result.get('odb_modified_during_task'):
            score += 10
            feedback_parts.append("Database file saved.")
        else:
            feedback_parts.append("Warning: Database file was not modified (did you save?).")

        # 2. Get the ODB file
        try:
            copy_from_env("/tmp/chinook_result.odb", temp_odb.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {str(e)}"}

        # 3. Analyze ODB content (Zip > content.xml)
        query_found = False
        query_sql = ""
        
        try:
            if not zipfile.is_zipfile(temp_odb.name):
                return {"passed": False, "score": score, "feedback": "Result file is not a valid ODB archive."}

            with zipfile.ZipFile(temp_odb.name, 'r') as z:
                if 'content.xml' not in z.namelist():
                    return {"passed": False, "score": score, "feedback": "Corrupt ODB: content.xml missing."}
                
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # ODB XML Namespaces
                ns = {
                    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }
                
                # Find queries in: office:body > office:database > db:queries > db:query
                # Note: ElementTree searching with namespaces requires explicit syntax or ignoring them
                # Let's iterate recursively to find db:query tags
                
                for query_elem in root.iter(f"{{{ns['db']}}}query"):
                    name = query_elem.get(f"{{{ns['db']}}}name")
                    command = query_elem.get(f"{{{ns['db']}}}command")
                    
                    if name == expected_query_name:
                        query_found = True
                        query_sql = command
                        break
                        
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse ODB file: {str(e)}"}

        # 4. Evaluate the Query
        if query_found:
            score += 30
            feedback_parts.append(f"Query '{expected_query_name}' found.")
            
            # Analyze SQL Content
            sql_upper = query_sql.upper()
            
            # Check structure (CASE, SUM, GROUP BY) - worth 40 points
            keywords_found = [kw for kw in required_keywords if kw in sql_upper]
            keyword_score = 0
            
            if "CASE" in keywords_found and "SUM" in keywords_found:
                keyword_score += 15
            if "GROUP BY" in keywords_found:
                keyword_score += 10
            if "ORDER BY" in keywords_found:
                keyword_score += 5
            if "2009" in keywords_found and "2013" in keywords_found:
                keyword_score += 10
                
            if keyword_score == 40:
                feedback_parts.append("SQL structure looks correct (Pivot logic found).")
            else:
                missing = [kw for kw in required_keywords if kw not in keywords_found]
                feedback_parts.append(f"SQL missing keywords: {', '.join(missing)}")
            
            score += keyword_score
            
            # Check for correct column aliases (checking for specific years)
            # We look for "Sales_2009" or similar in the raw string (case-insensitive)
            aliases_found = 0
            required_aliases = ["Sales_2009", "Sales_2013", "Grand_Total"]
            for alias in required_aliases:
                if alias.lower() in query_sql.lower():
                    aliases_found += 1
            
            if aliases_found == len(required_aliases):
                score += 20
                feedback_parts.append("Column aliases correct.")
            else:
                feedback_parts.append("Missing required column aliases (e.g., Sales_2009, Grand_Total).")
                
        else:
            feedback_parts.append(f"Query '{expected_query_name}' NOT found in database.")

        # 5. Final Validations
        passed = score >= 60 and query_found
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)