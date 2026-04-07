#!/usr/bin/env python3
"""Verifier for migrate_logbook_to_sqlite task.

Checks that a valid SQLite database was generated via the 'Save As' format filter,
and verifies its internal integrity and records.
"""

import os
import json
import sqlite3
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_migrate_logbook_to_sqlite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_dive_count = metadata.get('expected_dive_count', 8)

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Read exported result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    db_exists = result.get("db_exists", False)
    db_created_during_task = result.get("db_created_during_task", False)
    ssrf_exists = result.get("ssrf_exists", False)
    ssrf_size = result.get("ssrf_size_bytes", 0)

    # 2. Basic file and timestamp checks
    if db_exists:
        score += 10
        feedback_parts.append("DB file exists")
    else:
        feedback_parts.append("dives.db was NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if db_created_during_task:
        score += 10
        feedback_parts.append("DB created during task")
    else:
        feedback_parts.append("DB was not created during task time bounds")

    # 3. Source file intact check (Non-destructive Save As)
    if ssrf_exists and ssrf_size > 1000:
        score += 10
        feedback_parts.append("Original XML logbook intact")
    else:
        feedback_parts.append("Original XML logbook missing or destroyed")

    # 4. Verify SQLite Integrity and Content
    temp_db = tempfile.NamedTemporaryFile(delete=False, suffix='.db')
    temp_ssrf = tempfile.NamedTemporaryFile(delete=False, suffix='.ssrf')
    
    try:
        copy_from_env("/home/ga/Documents/dives.db", temp_db.name)
        
        # Verify it's a valid SQLite DB, not just a renamed XML file
        try:
            conn = sqlite3.connect(temp_db.name)
            cursor = conn.cursor()
            
            # Check for standard subsurface schema tables
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = [row[0] for row in cursor.fetchall()]
            
            if len(tables) > 0:
                score += 30
                feedback_parts.append("Valid SQLite format")
                
                # Verify dive counts
                if 'dives' in tables:
                    cursor.execute("SELECT count(*) FROM dives")
                    count = cursor.fetchone()[0]
                    
                    if count == expected_dive_count:
                        score += 40
                        feedback_parts.append(f"Contains exactly {count} dives")
                    else:
                        feedback_parts.append(f"DB contains {count} dives, expected {expected_dive_count}")
                else:
                    feedback_parts.append("Table 'dives' not found in DB")
            else:
                feedback_parts.append("DB is empty (no tables)")
                
            conn.close()
            
        except sqlite3.DatabaseError:
            feedback_parts.append("File is NOT a valid SQLite database (Agent likely just renamed the XML extension)")
            
    except Exception as e:
        logger.error(f"Error checking DB integrity: {e}")
        feedback_parts.append(f"Error reading DB: {e}")
        
    finally:
        if os.path.exists(temp_db.name):
            os.unlink(temp_db.name)
        if os.path.exists(temp_ssrf.name):
            os.unlink(temp_ssrf.name)

    # Calculate final status
    passed = score >= 90  # Requires DB existence, SQLite validity, and correct record counts

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }