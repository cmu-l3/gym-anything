#!/usr/bin/env python3
"""
Verifier for create_indexes task.

Verifies that:
1. The Chinook ODB file exists and was modified during the task.
2. The embedded HSQLDB script contains the correct CREATE INDEX statements.
3. Indexes target the correct tables and columns.
"""

import json
import os
import sys
import tempfile
import zipfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_indexes_from_script(script_content):
    """
    Parse CREATE INDEX statements from HSQLDB script content.
    Returns a list of parsed index dictionaries.
    """
    indexes = []
    # Regex to capture basic index structure: CREATE INDEX "Name" ON "Table"("Col1", "Col2"...)
    # HSQLDB 1.8 syntax often looks like: CREATE INDEX "idx_name" ON "table_name"("col1","col2")
    # We use a case-insensitive, flexible regex
    
    lines = script_content.split('\n')
    for line in lines:
        line = line.strip()
        # Look for CREATE INDEX lines
        if line.upper().startswith('CREATE INDEX') or line.upper().startswith('CREATE UNIQUE INDEX'):
            # Basic parsing logic
            try:
                # Remove 'PUBLIC.' schema prefix if present for easier matching
                clean_line = line.replace('PUBLIC.', '').replace('public.', '')
                
                # Extract index name
                # Matches: CREATE INDEX "Name" ...
                name_match = re.search(r'INDEX\s+"?(\w+)"?\s+ON', clean_line, re.IGNORECASE)
                if not name_match:
                    continue
                index_name = name_match.group(1)
                
                # Extract table name
                # Matches: ... ON "Table" ...
                table_match = re.search(r'ON\s+"?(\w+)"?\s*\(', clean_line, re.IGNORECASE)
                if not table_match:
                    continue
                table_name = table_match.group(1)
                
                # Extract columns
                # Matches: ... ("Col1", "Col2")
                cols_match = re.search(r'\((.+)\)', clean_line)
                if not cols_match:
                    continue
                
                cols_str = cols_match.group(1)
                # Split by comma and clean up quotes/spaces
                columns = [c.strip().strip('"').strip("'") for c in cols_str.split(',')]
                
                indexes.append({
                    'name': index_name,
                    'table': table_name,
                    'columns': columns,
                    'raw': line
                })
            except Exception as e:
                logger.warning(f"Failed to parse index line: {line} - {e}")
                
    return indexes

def verify_create_indexes(traj, env_info, task_info):
    """
    Verify the database indexes were created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Retrieve metadata / scoring weights
    # -------------------------------------
    odb_path_container = "/home/ga/chinook.odb"
    
    # 2. Retrieve Task Result JSON
    # -------------------------------------
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check basic file existence and modification
    if not task_result.get('odb_exists'):
        return {"passed": False, "score": 0, "feedback": "Chinook ODB file missing"}
    
    if task_result.get('odb_modified_during_task'):
        score += 15
        feedback_parts.append("Database saved successfully")
    else:
        feedback_parts.append("Database NOT saved (modification time unchanged)")
        # If not saved, indexes won't be in the file, but we'll check anyway just in case of filesystem quirks
    
    if task_result.get('odb_size_bytes', 0) < 1000:
        return {"passed": False, "score": 0, "feedback": "ODB file is corrupted or empty"}
        
    score += 10 # Integrity check pass
        
    # 3. Retrieve and Parse ODB File
    # -------------------------------------
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    found_indexes = []
    
    try:
        copy_from_env(odb_path_container, temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": score, "feedback": "Retrieved file is not a valid ODB/ZIP archive"}
            
        with zipfile.ZipFile(temp_odb.name, 'r') as zf:
            if 'database/script' in zf.namelist():
                script_content = zf.read('database/script').decode('utf-8', errors='replace')
                found_indexes = parse_indexes_from_script(script_content)
            else:
                return {"passed": False, "score": score, "feedback": "ODB archive missing 'database/script' file"}
                
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error inspecting ODB file: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # 4. Verify Specific Indexes
    # -------------------------------------
    required_indexes = task_info.get('metadata', {}).get('required_indexes', [])
    
    for req in required_indexes:
        req_name = req['name']
        req_table = req['table']
        req_cols = [c.upper() for c in req['columns']]
        
        # Search for match in found_indexes
        match_found = False
        partial_match = False
        
        for found in found_indexes:
            # Check name match (case-insensitive)
            if found['name'].upper() == req_name.upper():
                # Check table match
                if found['table'].upper() == req_table.upper():
                    # Check columns match
                    found_cols = [c.upper() for c in found['columns']]
                    if found_cols == req_cols:
                        match_found = True
                        break
                    elif set(found_cols) == set(req_cols):
                        # Columns match but order is different (only relevant for composite)
                        if len(req_cols) > 1:
                            feedback_parts.append(f"Index '{req_name}' found but column order incorrect")
                        else:
                            # Single column order doesn't matter
                            match_found = True
                            break
                    else:
                        feedback_parts.append(f"Index '{req_name}' found but columns mismatch ({found['columns']})")
                else:
                    feedback_parts.append(f"Index '{req_name}' found on wrong table '{found['table']}'")
                partial_match = True
        
        if match_found:
            points = 25 if len(req_cols) > 1 else 20  # More points for composite index
            score += points
            feedback_parts.append(f"Index '{req_name}' verified")
        elif not partial_match:
            feedback_parts.append(f"Index '{req_name}' missing")

    # 5. Final Scoring
    # -------------------------------------
    # Total possible: 15 (saved) + 10 (integrity) + 20 + 20 + 25 = 90
    # Let's normalize to 100 or adjust weights in code
    # Adjusting to match total 100:
    # Saved: 15
    # Integrity: 10
    # Index 1 (Name): 20
    # Index 2 (Composer): 20
    # Index 3 (Composite): 25
    # Bonus for perfect composite order: 10 (handled in composite check logic implicitly? No, let's add explicitly)
    
    # Let's verify composite order specifically for extra points if it wasn't strictly checked above
    # The logic above required exact list equality (ordered), so "match_found" implies correct order.
    # If order was wrong, we logged it but didn't give points.
    # To be generous, let's give partial credit for wrong order in composite.
    
    # Refined logic for composite index specifically (idx_Invoice_Cust_Date)
    # The loop above gave 0 points if order was wrong. Let's fix that manually if needed, 
    # but strictly following the prompt instructions ("in that order") suggests 0 is fair or partial.
    # Let's leave strict logic: exact match = full points.

    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }