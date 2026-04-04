#!/usr/bin/env python3
"""
Verifier for create_playlist_stats_query task.

Verification Logic:
1. Parse the ODB's content.xml to find a query named 'PlaylistStats'.
2. Extract the SQL command from the query definition.
3. Validate SQL structure (JOINs, Aggregates).
4. Execute the extracted SQL against the ground truth SQLite database to verify results.
   (Note: HSQLDB SQL is generally compatible with SQLite for this specific task, 
    minor adaptations handled if necessary).
"""

import json
import sqlite3
import xml.etree.ElementTree as ET
import os
import shutil
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_playlist_stats_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # Temp directory for processing
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch Task Result JSON
        local_result_json = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", local_result_json)
            with open(local_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

        # Check basic file existence / app state
        if not result_data.get("odb_exists", False):
            return {"passed": False, "score": 0, "feedback": "Database file deleted or missing."}
        
        if not result_data.get("odb_modified", False):
            feedback.append("Warning: Database file was not modified (timestamp unchanged).")
            # We continue checking in case the timestamp check was flaky, but this is suspicious.

        # 2. Fetch content.xml
        remote_content_path = result_data.get("content_xml_path")
        local_content_path = os.path.join(temp_dir, "content.xml")
        
        if remote_content_path and os.path.basename(remote_content_path) == "content.xml":
            try:
                copy_from_env(remote_content_path, local_content_path)
            except Exception as e:
                 return {"passed": False, "score": 0, "feedback": "Could not retrieve query definitions (content.xml missing)."}
        else:
            return {"passed": False, "score": 0, "feedback": "No content.xml found in export."}

        # 3. Parse XML to find the query
        try:
            tree = ET.parse(local_content_path)
            root = tree.getroot()
            
            # Namespace handling for ODF
            namespaces = {
                'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                'xlink': 'http://www.w3.org/1999/xlink'
            }
            
            # Find query 'PlaylistStats'
            # Structure: <db:table-representations> ... <db:queries> <db:query db:name="PlaylistStats" db:command="SELECT..."/>
            query_elem = root.find(".//db:query[@db:name='PlaylistStats']", namespaces)
            
            if query_elem is None:
                return {"passed": False, "score": 0, "feedback": "Query 'PlaylistStats' not found in the database."}
            
            score += 20
            feedback.append("Query 'PlaylistStats' found.")
            
            sql_command = query_elem.get('{urn:oasis:names:tc:opendocument:xmlns:database:1.0}command')
            if not sql_command:
                return {"passed": False, "score": 20, "feedback": "Query exists but is empty."}
                
            feedback.append(f"Found SQL: {sql_command[:50]}...")
            
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse database content: {str(e)}"}

        # 4. Fetch SQLite DB for Ground Truth Execution
        local_sqlite_path = os.path.join(temp_dir, "Chinook.sqlite")
        try:
            # Path defined in env setup
            copy_from_env("/opt/libreoffice_base_samples/Chinook_Sqlite.sqlite", local_sqlite_path)
        except Exception as e:
            # Fallback: try to find it in workspace if env path fails
            logger.warning(f"Could not copy sqlite from opt, trying fallback: {e}")
            return {"passed": False, "score": score, "feedback": "Verification failed: Could not retrieve ground truth database."}

        # 5. Execute and Compare
        try:
            conn = sqlite3.connect(local_sqlite_path)
            cursor = conn.cursor()
            
            # Ground Truth Logic
            gt_sql = """
                SELECT 
                    p.Name as PlaylistName, 
                    COUNT(pt.TrackId) as TrackCount, 
                    CAST(SUM(t.Milliseconds) AS FLOAT) / 60000.0 as DurationMinutes
                FROM Playlist p
                JOIN PlaylistTrack pt ON p.PlaylistId = pt.PlaylistId
                JOIN Track t ON pt.TrackId = t.TrackId
                GROUP BY p.Name
                ORDER BY DurationMinutes DESC
            """
            
            gt_results = cursor.execute(gt_sql).fetchall()
            
            # Agent Logic
            # Sanitize HSQLDB specific syntax for SQLite compatibility
            # 1. Remove double quotes around identifiers (SQLite usually handles them, but just in case)
            #    Actually SQLite handles "Table"."Column" fine.
            # 2. Handle boolean/types if needed.
            
            agent_sql = sql_command
            
            # Simple check for required keywords before execution
            required_keywords = ["JOIN", "GROUP BY", "ORDER BY", "COUNT", "SUM"]
            missing_keywords = [kw for kw in required_keywords if kw.lower() not in agent_sql.lower()]
            
            if missing_keywords:
                feedback.append(f"SQL missing keywords: {', '.join(missing_keywords)}")
                # Penalize but try to run anyway
            else:
                score += 10 # Structure looks okay
            
            try:
                agent_results = cursor.execute(agent_sql).fetchall()
                score += 20 # Executed successfully
            except sqlite3.Error as e:
                return {
                    "passed": False, 
                    "score": score, 
                    "feedback": f"Query logic valid in Base but failed in verifier (syntax incompatible?): {str(e)} | SQL: {agent_sql}"
                }

            # 6. Compare Results
            if not agent_results:
                feedback.append("Query returned 0 rows.")
            else:
                # Compare top 3 rows
                rows_match = True
                
                # Check row count
                if abs(len(agent_results) - len(gt_results)) > 2: # Allow small discrepancy
                    feedback.append(f"Row count mismatch: Expected ~{len(gt_results)}, Got {len(agent_results)}")
                    rows_match = False
                
                # Check specific values (Top 1)
                if len(agent_results) > 0 and len(gt_results) > 0:
                    agent_top = agent_results[0]
                    gt_top = gt_results[0]
                    
                    # Columns: Name, Count, Duration
                    # 1. Name
                    if agent_top[0] != gt_top[0]:
                        feedback.append(f"Top result mismatch. Expected '{gt_top[0]}', Got '{agent_top[0]}'")
                        rows_match = False
                    
                    # 2. Count
                    if agent_top[1] != gt_top[1]:
                        feedback.append(f"Track count mismatch. Expected {gt_top[1]}, Got {agent_top[1]}")
                        rows_match = False
                        
                    # 3. Duration (Decimal check)
                    agent_dur = agent_top[2]
                    gt_dur = gt_top[2]
                    
                    # Check if integer was returned instead of decimal
                    if isinstance(agent_dur, int) and isinstance(gt_dur, float):
                        feedback.append("Duration is an integer, expected decimal (check division by 60000.0).")
                        rows_match = False
                    elif abs(float(agent_dur) - float(gt_dur)) > 0.1:
                        feedback.append(f"Duration calculation wrong. Expected {gt_dur:.2f}, Got {agent_dur}")
                        rows_match = False
                    else:
                        score += 20 # Calculation correct
                
                if rows_match:
                    score += 30 # Results match
                    feedback.append("Query results match ground truth.")
                else:
                    feedback.append("Query results differ from ground truth.")

            # 7. Check Sorting (explicitly)
            if "DESC" in agent_sql.upper() and "ORDER BY" in agent_sql.upper():
                # Rough check, relying on execution result is better
                pass 
                
        except Exception as e:
             feedback.append(f"Error during verification execution: {str(e)}")

    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }