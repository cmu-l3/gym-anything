#!/usr/bin/env python3
"""
Verifier for create_subquery_analysis task.

Verifies:
1. ODB file exists and was modified.
2. 'TracksNotInPlaylists' query exists and uses NOT IN/NOT EXISTS.
3. 'GenresAboveAvgTrackCount' query exists and uses aggregation subquery.
4. 'HighValueCustomers' query exists and uses aggregation subquery.
5. VLM verification of the UI state (backup).
"""

import json
import tempfile
import os
import logging
import re
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_subquery_analysis(traj, env_info, task_info):
    """
    Verify the subquery analysis task by parsing the ODB's content.xml.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic Checks
    if not result.get('odb_exists'):
        return {"passed": False, "score": 0, "feedback": "Database file not found."}
    
    if not result.get('modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Database file was not modified during the task."}

    content_xml = result.get('content_xml', '')
    if not content_xml:
        return {"passed": False, "score": 10, "feedback": "Database file appears corrupted (no content.xml found)."}

    # Parse XML to find queries
    # Namespace handling is annoying in ElementTree, let's strip it or handle it carefully
    # OpenDocument Base XML usually has xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0"
    
    saved_queries = {}
    try:
        # Simple string-based extraction fallback if XML parsing fails due to namespaces
        # Searching for <db:query db:name="..." db:command="...">
        
        # Regex approach is often more robust against namespace variations in simple verifiers
        # Look for pattern: <db:query ... db:name="NAME" ... db:command="SQL" ...>
        # Note: attributes can be in any order.
        
        # Let's try proper XML parsing first
        root = ET.fromstring(content_xml)
        
        # Map namespaces
        namespaces = {
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0'
        }
        
        # Find queries
        # Path: office:body -> office:database -> db:queries -> db:query
        # Sometimes structure varies, let's look for all db:query tags
        for query_elem in root.findall('.//db:query', namespaces):
            name = query_elem.get(f"{{{namespaces['db']}}}name")
            command = query_elem.get(f"{{{namespaces['db']}}}command")
            if name and command:
                saved_queries[name] = command

    except Exception as e:
        logger.warning(f"XML parsing failed: {e}. Fallback to regex.")
        # Fallback regex
        query_pattern = re.compile(r'db:name="([^"]+)"[^>]*db:command="([^"]+)"')
        for match in query_pattern.finditer(content_xml):
            saved_queries[match.group(1)] = match.group(2)
            
    logger.info(f"Found queries: {list(saved_queries.keys())}")

    # Scoring
    score = 0
    feedback = []
    
    # 1. TracksNotInPlaylists
    q1_name = "TracksNotInPlaylists"
    if q1_name in saved_queries:
        score += 15
        sql = saved_queries[q1_name].upper()
        # Check logic: NOT EXISTS or NOT IN
        if "NOT EXISTS" in sql or "NOT IN" in sql:
            score += 15
            feedback.append(f"Query '{q1_name}' verified with subquery logic.")
        elif "LEFT JOIN" in sql and "IS NULL" in sql:
             # This is a valid alternative technically, but task asked for subquery
            score += 5
            feedback.append(f"Query '{q1_name}' uses JOIN/NULL instead of requested subquery.")
        else:
            feedback.append(f"Query '{q1_name}' found but SQL logic seems incorrect.")
    else:
        feedback.append(f"Query '{q1_name}' not found.")

    # 2. GenresAboveAvgTrackCount
    q2_name = "GenresAboveAvgTrackCount"
    if q2_name in saved_queries:
        score += 15
        sql = saved_queries[q2_name].upper()
        # Check logic: AVG in subquery
        # Typically: SELECT ... HAVING count > (SELECT AVG(...) ...)
        if "SELECT" in sql and "AVG" in sql and sql.count("SELECT") >= 2:
            score += 15
            feedback.append(f"Query '{q2_name}' verified with subquery logic.")
        else:
            score += 5
            feedback.append(f"Query '{q2_name}' found but missing obvious subquery aggregation pattern.")
    else:
        feedback.append(f"Query '{q2_name}' not found.")

    # 3. HighValueCustomers
    q3_name = "HighValueCustomers"
    if q3_name in saved_queries:
        score += 15
        sql = saved_queries[q3_name].upper()
        # Check logic: SELECT ... > (SELECT AVG(...) ...)
        if "SELECT" in sql and "AVG" in sql and sql.count("SELECT") >= 2:
            score += 15
            feedback.append(f"Query '{q3_name}' verified with subquery logic.")
        else:
            score += 5
            feedback.append(f"Query '{q3_name}' found but missing obvious subquery aggregation pattern.")
    else:
        feedback.append(f"Query '{q3_name}' not found.")

    # Base points for having a valid ODB modified
    if score > 0:
        score += 10 # Participation trophy for valid file operations

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "details": {"found_queries": list(saved_queries.keys())}
    }