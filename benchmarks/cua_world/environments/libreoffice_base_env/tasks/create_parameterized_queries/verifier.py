#!/usr/bin/env python3
"""
Verifier for create_parameterized_queries task.

Verifies that:
1. Two specific named queries exist in the ODB file (TrackSearch, InvoicesByDateRange).
2. The ODB file is a ZIP archive containing content.xml.
3. The SQL in content.xml contains the correct parameters, joins, and columns.
4. The file was actually modified during the task (anti-gaming).
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_query_sql(content_xml_path, query_name):
    """Parse content.xml to find the SQL command for a named query."""
    try:
        tree = ET.parse(content_xml_path)
        root = tree.getroot()
        
        # Namespaces in ODB content.xml
        ns = {
            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        # Search for <db:query> elements
        # Note: Depending on LO version, tag structure might vary slightly, 
        # but usually it is under office:body/office:database/db:queries/db:query
        
        # We'll iterate all elements to find db:query to be safe against schema variations
        for elem in root.iter():
            if elem.tag.endswith('query'):
                # Check name attribute (handles namespaced and non-namespaced attribs)
                name_attr = None
                for key, val in elem.attrib.items():
                    if key.endswith('name') and val == query_name:
                        name_attr = val
                        break
                
                if name_attr:
                    # Found the query, get the command (SQL)
                    for key, val in elem.attrib.items():
                        if key.endswith('command'):
                            return val
        return None
    except Exception as e:
        logger.error(f"Error parsing XML: {e}")
        return None

def verify_create_parameterized_queries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Create a temporary directory for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Retrieve result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basic file existence
        if not result.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "Database file chinook.odb not found"}

        # 2. Check anti-gaming (file modification)
        if result.get("file_modified", False):
            score += 5
            feedback_parts.append("Database saved successfully")
        else:
            feedback_parts.append("WARNING: Database file timestamp not updated (did you save?)")

        # 3. Retrieve the ODB file
        submission_path = result.get("submission_path", "/tmp/submission.odb")
        local_odb_path = os.path.join(temp_dir, "submission.odb")
        
        try:
            copy_from_env(submission_path, local_odb_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 4. Extract content.xml from ODB (which is a zip)
        content_xml_path = os.path.join(temp_dir, "content.xml")
        try:
            with zipfile.ZipFile(local_odb_path, 'r') as z:
                z.extract("content.xml", temp_dir)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid ODB file format (not a valid zip): {e}"}

        # =========================================================
        # Verify Query 1: TrackSearch
        # =========================================================
        track_sql = extract_query_sql(content_xml_path, "TrackSearch")
        
        if track_sql:
            score += 8
            feedback_parts.append("TrackSearch query found")
            
            sql_upper = track_sql.upper()
            
            # Check parameter
            if ":TRACK_NAME" in sql_upper:
                score += 8
            else:
                feedback_parts.append("TrackSearch: Missing ':track_name' parameter")

            # Check LIKE
            if "LIKE" in sql_upper:
                score += 7
            else:
                feedback_parts.append("TrackSearch: Missing 'LIKE' operator")

            # Check Tables
            tables_found = 0
            for tbl in ["TRACK", "ALBUM", "ARTIST", "GENRE"]:
                if tbl in sql_upper:
                    tables_found += 1
            if tables_found == 4:
                score += 12
            elif tables_found >= 3:
                score += 6
                feedback_parts.append(f"TrackSearch: Found {tables_found}/4 tables")
            else:
                feedback_parts.append("TrackSearch: Missing required table joins")

            # Check Columns (heuristic check for key column names)
            cols_found = 0
            for col in ["TRACKID", "TITLE", "NAME", "UNITPRICE"]:
                if col in sql_upper:
                    cols_found += 1
            if cols_found >= 3:
                score += 10
            else:
                feedback_parts.append("TrackSearch: Missing required columns")
                
            # Check Order By
            if "ORDER BY" in sql_upper:
                score += 5
        else:
            feedback_parts.append("TrackSearch query NOT found")

        # =========================================================
        # Verify Query 2: InvoicesByDateRange
        # =========================================================
        invoice_sql = extract_query_sql(content_xml_path, "InvoicesByDateRange")
        
        if invoice_sql:
            score += 8
            feedback_parts.append("InvoicesByDateRange query found")
            
            sql_upper = invoice_sql.upper()
            
            # Check parameters
            if ":START_DATE" in sql_upper and ":END_DATE" in sql_upper:
                score += 10
            elif ":START_DATE" in sql_upper or ":END_DATE" in sql_upper:
                score += 5
                feedback_parts.append("InvoicesByDateRange: Missing one date parameter")
            else:
                feedback_parts.append("InvoicesByDateRange: Missing date parameters")

            # Check Tables
            if "INVOICE" in sql_upper and "CUSTOMER" in sql_upper:
                score += 12
            else:
                feedback_parts.append("InvoicesByDateRange: Missing Invoice or Customer table")

            # Check Columns
            cols_found = 0
            for col in ["INVOICEID", "INVOICEDATE", "FIRSTNAME", "LASTNAME", "TOTAL"]:
                if col in sql_upper:
                    cols_found += 1
            if cols_found >= 4:
                score += 10
            else:
                feedback_parts.append("InvoicesByDateRange: Missing required columns")

            # Check Order By Desc
            if "ORDER BY" in sql_upper and "DESC" in sql_upper:
                score += 5
            elif "ORDER BY" in sql_upper:
                score += 3
                feedback_parts.append("InvoicesByDateRange: Missing DESC sort")
        else:
            feedback_parts.append("InvoicesByDateRange query NOT found")

    except Exception as e:
        feedback_parts.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup
        shutil.rmtree(temp_dir, ignore_errors=True)

    # Final pass determination
    # Must have created both queries to be considered "passed" fundamentally, 
    # but the score reflects partial progress.
    # Threshold 65 means roughly one perfect query or two decent attempts.
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }