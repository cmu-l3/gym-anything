#!/usr/bin/env python3
"""
Verifier for create_set_operation_queries task.

Verifies that the user created 4 specific named queries in the LibreOffice Base ODB file.
Since ODB files are ZIP archives containing XML, this verifier:
1. Copies the ODB file from the environment.
2. Unzips it to access content.xml.
3. Parses content.xml to find <db:query> elements.
4. Checks for the existence of required query names.
5. Performs simple static analysis on the SQL command text to verify intent (checking for keywords).

Required Queries:
- TracksWithoutPlaylist (Expect: EXCEPT / NOT IN / NOT EXISTS)
- SharedMusicAnd90s (Expect: INTERSECT / IN / EXISTS / JOIN)
- MusicNotIn90s (Expect: EXCEPT / NOT IN / NOT EXISTS)
- UnpurchasedTracks (Expect: EXCEPT / NOT IN / NOT EXISTS)
"""

import json
import tempfile
import os
import zipfile
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_set_operation_queries(traj, env_info, task_info):
    """
    Verify the creation of set operation queries in LibreOffice Base.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_queries = metadata.get('required_queries', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get the result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basic file status (Anti-gaming)
    if not task_result.get('odb_exists', False):
        return {"passed": False, "score": 0, "feedback": "Database file not found"}
    
    if task_result.get('odb_modified_during_task', False):
        score += 10
        feedback_parts.append("Database saved during task")
    else:
        feedback_parts.append("Warning: Database not saved/modified during task")

    # 3. Retrieve and Parse the ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    content_xml_path = None
    
    try:
        # Copy ODB from container
        copy_from_env(task_result.get('odb_path', '/home/ga/chinook.odb'), temp_odb.name)
        
        # ODB is a zip file. We need to extract content.xml
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid ODB/ZIP archive"}
            
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": score, "feedback": "Corrupt ODB: content.xml missing"}
            
            # Extract content.xml content directly to memory
            content_xml_data = z.read('content.xml')
            
        # Parse XML
        # Namespaces in ODB content.xml are usually bound
        # db:query is usually {urn:oasis:names:tc:opendocument:xmlns:database:1.0}query
        namespaces = {
            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        root = ET.fromstring(content_xml_data)
        
        # Find all query definitions
        # Structure is usually: office:body -> office:database -> db:queries -> db:query
        # We'll search recursively for db:query
        queries_found = {}
        for query_elem in root.findall('.//db:query', namespaces):
            name = query_elem.get(f"{{{namespaces['db']}}}name")
            command = query_elem.get(f"{{{namespaces['db']}}}command")
            if name and command:
                queries_found[name] = command

        logger.info(f"Found queries: {list(queries_found.keys())}")
        
        # 4. Verify each required query
        queries_passed = 0
        
        for req in required_queries:
            req_name = req['name']
            
            if req_name in queries_found:
                query_sql = queries_found[req_name].upper()
                
                # Check 1: Query Exists (10 pts each)
                score += 10
                step_feedback = [f"Query '{req_name}' exists"]
                
                # Check 2: Valid Logic/Keywords (12.5 pts each)
                # We check if the SQL contains at least one of the valid approach keywords
                valid_keywords = req.get('keywords', [])
                has_keyword = any(k in query_sql for k in valid_keywords)
                
                # Also check if it references required tables
                required_tables = req.get('tables', [])
                # Simple check: table names usually appear in FROM or JOIN clauses
                # We just check if the string exists in the query
                has_tables = all(t.upper() in query_sql for t in required_tables)
                
                # Specific check for Playlist IDs if required (e.g., 1 and 5)
                required_ids = req.get('ids', [])
                has_ids = all(pid in query_sql for pid in required_ids)
                
                if has_keyword and has_tables and has_ids:
                    score += 12.5
                    step_feedback.append("SQL logic valid")
                    queries_passed += 1
                else:
                    missing = []
                    if not has_keyword: missing.append("missing set operation keywords")
                    if not has_tables: missing.append("missing table references")
                    if not has_ids: missing.append("missing specific IDs")
                    step_feedback.append(f"SQL check failed ({', '.join(missing)})")
                    
                feedback_parts.append(f"[{req_name}: " + ", ".join(step_feedback) + "]")
                
            else:
                feedback_parts.append(f"Missing query: '{req_name}'")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 5. Finalize Score
    # Total points possible: 10 (save) + 4 * (10 + 12.5) = 100
    
    # Requirement: Must have at least 2 queries fully correct to pass
    passed = queries_passed >= 2 and score >= 50
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }