#!/usr/bin/env python3
"""
Verifier for create_string_query task.

Verification Strategy:
1. Parse the ODB file (which is a ZIP archive).
2. Read 'content.xml' inside the ODB.
3. Look for a <db:query> element with the name 'CustomerDirectory'.
4. Analyze the SQL command within that element for required logic.
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

def verify_create_string_query(traj, env_info, task_info):
    """
    Verify the agent created the CustomerDirectory query correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Required SQL components based on task description
    required_keywords = {
        "UPPER": 5,      # For name formatting
        "COALESCE": 5,   # For handling NULL address fields
        "SUBSTRING": 5,  # For email domain
        "LOCATE": 5,     # For finding '@' in email
        "FROM": 0,
        "Customer": 0,
        "ORDER BY": 5    # For sorting
    }
    
    # Check for concatenation (|| or CONCAT)
    concat_score = 5
    
    # 1. Retrieve result JSON and ODB file
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    
    try:
        # Get JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basic file status
        if not result.get("odb_exists", False):
            return {"passed": False, "score": 0, "feedback": "Database file not found"}
            
        if not result.get("odb_modified", False):
            feedback_parts.append("Warning: Database file timestamp indicates no changes saved")
            # We continue verification in case timestamp logic was flaky, but it's a bad sign

        # Get ODB file
        try:
            copy_from_env("/tmp/result.odb", temp_odb.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 2. Parse ODB (ZIP) content
        query_found = False
        sql_command = ""
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "Result file is not a valid ODB/ZIP archive"}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB: content.xml missing"}
            
            content_xml = z.read('content.xml')
            
            # Parse XML
            # Namespace map for ODF
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                'xlink': 'http://www.w3.org/1999/xlink'
            }
            
            root = ET.fromstring(content_xml)
            
            # Find the query definition
            # Path: office:body -> office:database -> db:queries -> db:query
            # Note: The structure might be nested under table-representations or similar depending on LO version,
            # but usually it's under db:queries.
            
            # Search for any db:query element with the right name
            for query in root.findall('.//db:query', namespaces):
                name = query.get(f"{{{namespaces['db']}}}name")
                if name == "CustomerDirectory":
                    query_found = True
                    sql_command = query.get(f"{{{namespaces['db']}}}command", "")
                    break

        # 3. Score the finding
        if not query_found:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Saved query 'CustomerDirectory' not found in database. Did you save it with the exact name?"
            }
        
        score += 30
        feedback_parts.append("Query 'CustomerDirectory' exists")

        # 4. Analyze SQL
        sql_upper = sql_command.upper()
        
        # Check concatenation
        if "||" in sql_command or "CONCAT" in sql_upper:
            score += concat_score
            feedback_parts.append("Uses concatenation")
        else:
            feedback_parts.append("Missing string concatenation (||)")

        # Check other keywords
        for keyword, pts in required_keywords.items():
            if keyword in sql_upper:
                score += pts
                # feedback_parts.append(f"Uses {keyword}") 
            else:
                feedback_parts.append(f"Missing keyword: {keyword}")

        # Check Column Aliases (proxy for correct structure)
        # We look for the exact aliases requested in the description
        expected_aliases = ["FormattedName", "FullAddress", "EmailDomain"]
        aliases_found = 0
        for alias in expected_aliases:
            # Check for "AS \"Alias\"" or just "Alias" depending on how LO saves it
            # LO often saves as: ... AS "FormattedName"
            if f'"{alias.upper()}"' in sql_upper or f'"{alias}"' in sql_command:
                aliases_found += 1
            elif alias.upper() in sql_upper: # Loose check
                aliases_found += 1
        
        if aliases_found == 3:
            score += 20
            feedback_parts.append("Required column aliases found")
        elif aliases_found > 0:
            score += 10
            feedback_parts.append(f"Some column aliases found ({aliases_found}/3)")
        else:
            feedback_parts.append("Missing required column aliases (FormattedName, FullAddress, EmailDomain)")

        # Check logic specific to requirements
        
        # Address should use COALESCE on State/PostalCode
        # Simple heuristic check
        if "COALESCE" in sql_upper and ("STATE" in sql_upper or "POSTALCODE" in sql_upper):
            score += 10
            feedback_parts.append("Null handling logic detected")
        
        # Email domain logic: SUBSTRING + LOCATE + @
        if "SUBSTRING" in sql_upper and "LOCATE" in sql_upper and "@" in sql_command:
            score += 10
            feedback_parts.append("Email domain extraction logic detected")
            
        # 5. Final pass check
        # We need a score >= 60 to pass
        # Max score is 30(exist) + 5(concat) + 25(keywords) + 20(aliases) + 10(nulls) + 10(email) = 100
        
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {"sql_extracted": sql_command}
        }

    except Exception as e:
        logger.exception("Verification failed with error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)