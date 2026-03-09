#!/usr/bin/env python3
"""
Verifier for chinook_fts_catalog task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_fts_catalog(traj, env_info, task_info):
    """
    Verify the creation of FTS5 catalog and search exports.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load metadata
    metadata = task_info.get('metadata', {})
    search_queries = metadata.get('search_queries', {})
    
    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/fts_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    # 1. Connection (10 pts)
    if result.get('dbeaver_connection_exists'):
        score += 10
        feedback.append("DBeaver connection found.")
    else:
        feedback.append("DBeaver connection 'Chinook' not found.")
        
    # 2. FTS Table Existence & Functionality (40 pts total)
    if result.get('fts_table_exists'):
        score += 15
        feedback.append("FTS table 'catalog_fts' exists.")
        
        # Check row count (15 pts)
        row_count = result.get('fts_row_count', 0)
        expected = metadata.get('expected_row_count', 3503)
        # Allow small margin just in case, though it should be exact
        if abs(row_count - expected) < 5:
            score += 15
            feedback.append(f"Row count correct ({row_count}).")
        else:
            feedback.append(f"Row count mismatch: got {row_count}, expected ~{expected}.")
            
        # Check MATCH functionality (10 pts)
        if result.get('fts_match_functional'):
            score += 10
            feedback.append("FTS MATCH queries are functional.")
        else:
            feedback.append("Table exists but does not support MATCH queries (may be standard table, not FTS).")
    else:
        feedback.append("FTS table 'catalog_fts' NOT found in database.")

    # 3. CSV Exports (36 pts total, 12 per file)
    csv_results = result.get('csv_files', {})
    
    # Iron Maiden (approx 204-214 rows)
    im_res = csv_results.get('search_iron_maiden.csv', {})
    im_meta = search_queries.get('iron_maiden', {})
    if im_res.get('exists') and im_res.get('fresh'):
        rows = im_res.get('rows', 0)
        if im_meta.get('min_rows', 0) <= rows <= im_meta.get('max_rows', 1000):
            score += 12
            feedback.append(f"Iron Maiden export valid ({rows} rows).")
        else:
            score += 6 # Partial for file existing
            feedback.append(f"Iron Maiden export row count out of range ({rows}).")
    else:
        feedback.append("Iron Maiden export missing.")

    # Blues Rock (approx 35-60 rows)
    br_res = csv_results.get('search_blues_rock.csv', {})
    br_meta = search_queries.get('blues_rock', {})
    if br_res.get('exists') and br_res.get('fresh'):
        rows = br_res.get('rows', 0)
        if br_meta.get('min_rows', 0) <= rows <= br_meta.get('max_rows', 100):
            score += 12
            feedback.append(f"Blues Rock export valid ({rows} rows).")
        else:
            score += 6
            feedback.append(f"Blues Rock export row count out of range ({rows}).")
    else:
        feedback.append("Blues Rock export missing.")

    # Bach (approx 15-45 rows)
    ba_res = csv_results.get('search_bach.csv', {})
    ba_meta = search_queries.get('bach', {})
    if ba_res.get('exists') and ba_res.get('fresh'):
        rows = ba_res.get('rows', 0)
        if ba_meta.get('min_rows', 0) <= rows <= ba_meta.get('max_rows', 100):
            score += 12
            feedback.append(f"Bach export valid ({rows} rows).")
        else:
            score += 6
            feedback.append(f"Bach export row count out of range ({rows}).")
    else:
        feedback.append("Bach export missing.")

    # 4. SQL Script (14 pts)
    script_res = result.get('sql_script', {})
    if script_res.get('exists'):
        if script_res.get('valid_keywords'):
            score += 14
            feedback.append("SQL script exists and contains FTS syntax.")
        else:
            score += 7
            feedback.append("SQL script exists but missing FTS syntax keywords.")
    else:
        feedback.append("SQL script missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }