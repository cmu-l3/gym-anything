#!/usr/bin/env python3
"""
Verifier for create_schema_queries task.

Verifies that the agent created two specific SQL queries in LibreOffice Base
that inspect the HSQLDB INFORMATION_SCHEMA.

Verification Method:
1. Extract content.xml from the submitted .odb (ZIP) file.
2. Parse the XML to find <db:query> elements.
3. Validate existence, names, and SQL content of the queries.
4. Check for 'INFORMATION_SCHEMA' usage and 'PUBLIC' schema filtering.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_schema_queries(traj, env_info, task_info):
    """
    Verify the schema introspection queries task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_FILE_MODIFIED = 5
    SCORE_VLM_EVIDENCE = 5
    
    # Query 1: TableColumnCatalog (45 pts)
    SCORE_Q1_EXISTS = 15
    SCORE_Q1_SYSTEM_TABLE = 10
    SCORE_Q1_FILTER = 5
    SCORE_Q1_COLUMNS = 10
    SCORE_Q1_ORDER = 5
    
    # Query 2: PrimaryKeyCatalog (45 pts)
    SCORE_Q2_EXISTS = 15
    SCORE_Q2_SYSTEM_TABLE = 10
    SCORE_Q2_FILTER = 5
    SCORE_Q2_COLUMNS = 10
    SCORE_Q2_ORDER = 5

    score = 0
    feedback_parts = []
    
    # 1. Get result JSON and ODB file
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    
    try:
        # Load JSON result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        # Check basic file modification
        if result.get("file_modified", False):
            score += SCORE_FILE_MODIFIED
            feedback_parts.append("Database file was saved/modified")
        else:
            feedback_parts.append("Database file NOT modified (did you save?)")

        # Load ODB file
        try:
            copy_from_env("/tmp/submitted_chinook.odb", temp_odb.name)
            odb_valid = True
        except Exception as e:
            logger.error(f"Failed to copy ODB: {e}")
            odb_valid = False
            feedback_parts.append("Could not retrieve database file")

        # 2. Parse ODB content
        queries_found = {}
        if odb_valid:
            try:
                with zipfile.ZipFile(temp_odb.name, 'r') as z:
                    with z.open('content.xml') as f:
                        tree = ET.parse(f)
                        root = tree.getroot()
                        
                        # Define namespaces (ODF standard)
                        ns = {
                            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                            'xlink': 'http://www.w3.org/1999/xlink'
                        }
                        
                        # Find all query definitions
                        # Path: office:body -> office:database -> db:queries -> db:query
                        # We'll search recursively for db:query
                        for query_elem in root.findall('.//db:query', ns):
                            name = query_elem.get(f"{{{ns['db']}}}name")
                            command = query_elem.get(f"{{{ns['db']}}}command")
                            if name and command:
                                queries_found[name] = command
            except Exception as e:
                logger.error(f"Failed to parse ODB XML: {e}")
                feedback_parts.append("Failed to parse database structure")

        # 3. Verify Query 1: TableColumnCatalog
        q1_name = "TableColumnCatalog"
        if q1_name in queries_found:
            score += SCORE_Q1_EXISTS
            feedback_parts.append(f"Query '{q1_name}' found")
            
            sql = queries_found[q1_name].upper()
            
            # Check system table reference
            if "SYSTEM_COLUMNS" in sql:
                score += SCORE_Q1_SYSTEM_TABLE
            else:
                feedback_parts.append(f"'{q1_name}' missing SYSTEM_COLUMNS reference")
                
            # Check public filter
            if "PUBLIC" in sql and ("WHERE" in sql or "HAVING" in sql):
                score += SCORE_Q1_FILTER
            else:
                feedback_parts.append(f"'{q1_name}' missing 'PUBLIC' schema filter")
                
            # Check required columns
            req_cols = ["TABLE_NAME", "COLUMN_NAME", "TYPE_NAME", "ORDINAL_POSITION", "IS_NULLABLE"]
            cols_found = sum(1 for c in req_cols if c in sql)
            if cols_found >= 4: # Allow missing 1
                score += SCORE_Q1_COLUMNS
            else:
                feedback_parts.append(f"'{q1_name}' missing required columns")

            # Check sorting
            if "ORDER BY" in sql:
                score += SCORE_Q1_ORDER

        else:
            feedback_parts.append(f"Query '{q1_name}' NOT found")

        # 4. Verify Query 2: PrimaryKeyCatalog
        q2_name = "PrimaryKeyCatalog"
        if q2_name in queries_found:
            score += SCORE_Q2_EXISTS
            feedback_parts.append(f"Query '{q2_name}' found")
            
            sql = queries_found[q2_name].upper()
            
            # Check system table reference
            if "SYSTEM_PRIMARYKEYS" in sql:
                score += SCORE_Q2_SYSTEM_TABLE
            else:
                feedback_parts.append(f"'{q2_name}' missing SYSTEM_PRIMARYKEYS reference")
                
            # Check public filter
            if "PUBLIC" in sql and ("WHERE" in sql or "HAVING" in sql):
                score += SCORE_Q2_FILTER
            else:
                feedback_parts.append(f"'{q2_name}' missing 'PUBLIC' schema filter")
                
            # Check required columns
            req_cols = ["TABLE_NAME", "COLUMN_NAME", "KEY_SEQ", "PK_NAME"]
            cols_found = sum(1 for c in req_cols if c in sql)
            if cols_found >= 3: # Allow missing 1
                score += SCORE_Q2_COLUMNS
            else:
                feedback_parts.append(f"'{q2_name}' missing required columns")

            # Check sorting
            if "ORDER BY" in sql:
                score += SCORE_Q2_ORDER

        else:
            feedback_parts.append(f"Query '{q2_name}' NOT found")

        # 5. VLM Verification (Trajectory)
        # We verify that the agent actually interacted with the query design/SQL view
        frames = sample_trajectory_frames(traj, n=4)
        if frames and query_vlm:
            vlm_prompt = """
            Does this sequence of images show a user creating SQL queries in LibreOffice Base?
            Look for:
            1. The 'Create Query in SQL View' window or icon.
            2. SQL code being typed (keywords like SELECT, FROM, INFORMATION_SCHEMA).
            3. Query results showing a table-like list of metadata.
            4. Saving a query.
            
            Respond with JSON: {"evidence_found": boolean, "confidence": float}
            """
            try:
                vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("evidence_found", False):
                    score += SCORE_VLM_EVIDENCE
                    feedback_parts.append("VLM confirmed query creation workflow")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
        
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }