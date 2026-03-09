#!/usr/bin/env python3
"""
Verifier for implement_qc_workflow task.
Analyzes the HSQLDB script file extracted from the LibreOffice Base ODB file.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_script(script_content):
    """
    Parses the HSQLDB script to find the Track table schema and data.
    Returns:
        schema: dict of {column_name: index} for the Track table
        rows: list of lists (values for each row in Track)
        views: list of view names defined
    """
    schema = {}
    rows = []
    views = []
    
    lines = script_content.splitlines()
    
    # Regex to find CREATE TABLE "Track" (...)
    # HSQLDB format: CREATE TABLE "Track"("TrackId" INTEGER NOT NULL PRIMARY KEY, "Name" ...)
    # Note: spacing can vary.
    
    for line in lines:
        # Check for View definitions
        view_match = re.search(r'CREATE VIEW "([^"]+)"', line, re.IGNORECASE)
        if view_match:
            views.append(view_match.group(1))
            continue
            
        # Check for Track table definition
        if 'CREATE TABLE "Track"' in line:
            # Extract content inside parentheses
            # This is a simple parser assuming standard HSQLDB 1.8 output which is usually one line
            content_match = re.search(r'CREATE TABLE "Track"\((.*)\)', line)
            if content_match:
                columns_def = content_match.group(1)
                # Split by comma, but be careful of commas in types like NUMERIC(10,2)
                # Simple split might fail, but HSQLDB script output is machine generated and regular
                # We can split by '",' which separates column definitions
                parts = columns_def.split('",')
                for idx, part in enumerate(parts):
                    # Extract column name
                    col_name_match = re.search(r'"([^"]+)"', part)
                    if col_name_match:
                        col_name = col_name_match.group(1)
                        schema[col_name] = idx
        
        # Check for Data
        if line.startswith('INSERT INTO "Track"'):
            # Extract values
            # INSERT INTO "Track" VALUES(1,'Name',...)
            val_match = re.search(r'VALUES\((.*)\)', line)
            if val_match:
                val_str = val_match.group(1)
                # A proper CSV parser is needed to handle commas in strings, 
                # but for this verification we mostly care about the numeric IDs and the status at the end.
                # Given the constraints, a simple parse might suffice if we are careful.
                # However, track names contain commas.
                # Strategy: We know the structure.
                # We need MediaTypeId and QC_Status.
                # QC_Status should be the last one if added recently.
                
                # Let's try to parse the values list properly-ish
                vals = []
                current_val = ""
                in_quote = False
                for char in val_str:
                    if char == "'" and not (current_val.endswith('\\')): # Simple escape check
                        in_quote = not in_quote
                        current_val += char
                    elif char == ',' and not in_quote:
                        vals.append(current_val.strip())
                        current_val = ""
                    else:
                        current_val += char
                vals.append(current_val.strip())
                rows.append(vals)

    return schema, rows, views

def verify_implement_qc_workflow(traj, env_info, task_info):
    """
    Verifies that the QC_Status column was added and populated correctly,
    and that the view was created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        if not result.get('db_script_extracted'):
            return {"passed": False, "score": 0, "feedback": "Database file could not be analyzed (save failed or file corrupted)."}

        # Copy the SQL script
        copy_from_env("/tmp/db_script.sql", temp_script.name)
        with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
            script_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)
        if os.path.exists(temp_script.name): os.unlink(temp_script.name)

    # Parse the script
    schema, rows, views = parse_hsqldb_script(script_content)
    
    score = 0
    feedback = []
    
    # 1. Verify Schema (20 points)
    if "QC_Status" in schema:
        score += 20
        feedback.append("Schema check passed: 'QC_Status' column found.")
        qc_col_idx = schema["QC_Status"]
    else:
        feedback.append("Schema check failed: 'QC_Status' column NOT found in 'Track' table.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify View Creation (20 points)
    if "v_QC_Pending_List" in views:
        score += 20
        feedback.append("View check passed: 'v_QC_Pending_List' found.")
    else:
        feedback.append("View check failed: 'v_QC_Pending_List' NOT found.")

    # 3. Verify Data Logic (60 points total)
    # MediaTypeId is usually index 3 in the original schema.
    # We should look it up to be safe.
    media_type_idx = schema.get("MediaTypeId", 3)
    
    correct_approved = 0
    correct_pending = 0
    correct_legacy = 0
    total_approved_target = 0
    total_pending_target = 0
    total_legacy_target = 0
    errors = 0
    
    for row in rows:
        if len(row) <= qc_col_idx:
            continue
            
        # Get MediaTypeId (strip quotes/spaces)
        try:
            mt_id = int(row[media_type_idx].strip("'"))
        except:
            continue
            
        # Get Status value (strip quotes)
        status = row[qc_col_idx].strip("'")
        if status == "NULL": status = None
        
        # Check logic
        if mt_id == 1: # MPEG
            total_approved_target += 1
            if status == "Approved": correct_approved += 1
            elif status: errors += 1
        elif mt_id == 2: # Protected AAC
            total_pending_target += 1
            if status == "Pending Review": correct_pending += 1
            elif status: errors += 1
        elif mt_id == 4: # Purchased AAC
            total_legacy_target += 1
            if status == "Legacy": correct_legacy += 1
            elif status: errors += 1

    # Logic Scoring
    # Approved (25 pts)
    if total_approved_target > 0 and correct_approved / total_approved_target > 0.95:
        score += 25
        feedback.append(f"Approved logic passed ({correct_approved}/{total_approved_target}).")
    else:
        feedback.append(f"Approved logic failed ({correct_approved}/{total_approved_target} correct).")

    # Pending (25 pts)
    if total_pending_target > 0 and correct_pending / total_pending_target > 0.95:
        score += 25
        feedback.append(f"Pending logic passed ({correct_pending}/{total_pending_target}).")
    else:
        feedback.append(f"Pending logic failed ({correct_pending}/{total_pending_target} correct).")

    # Legacy (10 pts)
    if total_legacy_target > 0 and correct_legacy / total_legacy_target > 0.95:
        score += 10
        feedback.append(f"Legacy logic passed ({correct_legacy}/{total_legacy_target}).")
    else:
        feedback.append(f"Legacy logic failed ({correct_legacy}/{total_legacy_target} correct).")
        
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }