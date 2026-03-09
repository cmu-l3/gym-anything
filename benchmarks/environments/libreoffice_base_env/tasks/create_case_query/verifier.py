#!/usr/bin/env python3
"""
Verifier for create_case_query task.

Verification Strategy:
1. Programmatic (80%): Inspect the binary ODB file (ZIP archive).
   - Extract content.xml
   - Regex search for the saved query "TrackCategories"
   - Verify SQL contains CASE, WHEN, correct thresholds, aliases, and ORDER BY.
2. VLM (20%): Verify the process via trajectory.
   - Confirm agent used the SQL editor window.
   - Confirm agent saved the query.
"""

import json
import tempfile
import os
import re
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_case_query(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_query_name = metadata.get('query_name', 'TrackCategories')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 1. READ RESULT JSON
    # ================================================================
    task_result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json') as f:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # Basic checks
    if not task_result.get('file_modified_timestamp', False):
        feedback_parts.append("ODB file was not modified (timestamp check failed)")
    elif not task_result.get('file_content_changed', False):
        feedback_parts.append("ODB file content matches initial state (agent did nothing)")
    else:
        score += 10
        feedback_parts.append("Database file modified successfully")

    # ================================================================
    # 2. INSPECT ODB FILE CONTENT
    # ================================================================
    odb_content_xml = ""
    try:
        # Copy ODB file to host
        with tempfile.NamedTemporaryFile(suffix='.odb') as odb_file:
            copy_from_env(task_result.get('odb_path', '/home/ga/chinook.odb'), odb_file.name)
            
            # Open as ZIP and extract content.xml
            with zipfile.ZipFile(odb_file.name, 'r') as zf:
                odb_content_xml = zf.read('content.xml').decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to inspect ODB: {e}")
        feedback_parts.append("Could not inspect database file (may be corrupted or missing)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Find the query in XML
    # Format: <db:query db:name="TrackCategories" db:command="SELECT ..."/>
    # Regex is case-insensitive for safety
    query_pattern = re.compile(
        r'(?:db:)?query\s+[^>]*?(?:db:)?name\s*=\s*["\']([^"\']+)["\'][^>]*?(?:db:)?command\s*=\s*["\']([^"\']+)["\']',
        re.IGNORECASE | re.DOTALL
    )
    
    found_queries = query_pattern.findall(odb_content_xml)
    target_sql = ""
    
    # Normalize name search
    normalized_expected = expected_query_name.lower().replace(" ", "")
    
    for name, command in found_queries:
        if normalized_expected in name.lower().replace(" ", ""):
            target_sql = command
            # Unescape XML entities
            target_sql = (target_sql.replace('&lt;', '<')
                                    .replace('&gt;', '>')
                                    .replace('&amp;', '&')
                                    .replace('&quot;', '"')
                                    .replace('&apos;', "'"))
            break
            
    if target_sql:
        score += 20
        feedback_parts.append(f"Query '{expected_query_name}' found")
        
        sql_upper = target_sql.upper()
        
        # Check CASE WHEN syntax (20 pts)
        case_count = sql_upper.count('CASE')
        when_count = sql_upper.count('WHEN')
        if case_count >= 2 and when_count >= 2:
            score += 20
            feedback_parts.append("Correct CASE WHEN syntax detected")
        elif case_count >= 1:
            score += 10
            feedback_parts.append("Partial CASE WHEN syntax detected")
        else:
            feedback_parts.append("Missing CASE expressions")
            
        # Check Duration Logic (15 pts)
        # Looking for milliseconds and thresholds 180000, 360000
        has_ms = 'MILLISECONDS' in sql_upper
        has_dur_thresholds = '180000' in target_sql and '360000' in target_sql
        if has_ms and has_dur_thresholds:
            score += 15
            feedback_parts.append("Duration categorization logic correct")
        elif has_ms:
            score += 5
            feedback_parts.append("Duration column used but thresholds incorrect")
        else:
            feedback_parts.append("Missing duration logic")

        # Check Price Logic (15 pts)
        # Looking for UnitPrice and thresholds 1.0, 1.5
        has_price = 'UNITPRICE' in sql_upper
        # Regex for price to handle 1.00 vs 1.0 vs 1
        has_price_thresholds = re.search(r'1\.0\d*', target_sql) and re.search(r'1\.5\d*', target_sql)
        if has_price and has_price_thresholds:
            score += 15
            feedback_parts.append("Price categorization logic correct")
        elif has_price:
            score += 5
            feedback_parts.append("Price column used but thresholds incorrect")
        else:
            feedback_parts.append("Missing price logic")
            
        # Check Aliases (5 pts)
        if 'DURATIONCATEGORY' in sql_upper.replace('"', '').replace("'", ""):
            score += 5
        if 'PRICECATEGORY' in sql_upper.replace('"', '').replace("'", ""):
            score += 5
            
        # Check ORDER BY (10 pts)
        if 'ORDER BY' in sql_upper and 'NAME' in sql_upper.split('ORDER BY')[-1]:
            score += 10
            feedback_parts.append("Sorted by Name")
        elif 'ORDER BY' in sql_upper:
            score += 5
            feedback_parts.append("Sorted (incorrect column)")
            
    else:
        feedback_parts.append(f"Query '{expected_query_name}' NOT found in database")
        # Try to find loose match for partial credit
        if 'CASE' in odb_content_xml and 'WHEN' in odb_content_xml:
            score += 10
            feedback_parts.append("Found some CASE SQL but in wrong query or unsaved")

    # ================================================================
    # 3. VLM VERIFICATION (Process Check)
    # ================================================================
    # This is a backup to verify the agent actually interacted with the UI
    # properly, especially if the ODB save failed but the agent tried.
    
    # We only run VLM if score < 100 to check for partial credit or confirm validity
    if score < 100 or score >= 60:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Review these screenshots of a user working in LibreOffice Base.
        Check for the following:
        1. Is the "Create Query in SQL View" window visible? (Text editor for SQL)
        2. Did the user type a SQL query involving "CASE", "WHEN", "SELECT"?
        3. Did the user save the query as "TrackCategories"?
        
        Return JSON: {"sql_editor_visible": bool, "case_sql_visible": bool, "save_dialog_visible": bool}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('sql_editor_visible', False):
                # Bonus/Confirmation
                pass
            if parsed.get('case_sql_visible', False) and not target_sql:
                score += 10
                feedback_parts.append("VLM confirmed SQL was typed (but maybe not saved correctly)")
        except Exception:
            pass # VLM failure shouldn't penalize if programmatic check passed

    # Final scoring
    score = min(100, score)
    passed = score >= 60 and target_sql != ""
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }