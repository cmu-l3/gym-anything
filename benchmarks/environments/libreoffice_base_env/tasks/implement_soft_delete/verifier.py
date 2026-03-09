#!/usr/bin/env python3
"""
Verifier for implement_soft_delete task.

Verifies:
1. 'IsDeleted' column exists in 'Track' table.
2. 'ActiveTracks' view exists and has correct definition.
3. Data integrity:
   - 'Metal' tracks have IsDeleted = TRUE
   - Non-Metal tracks have IsDeleted = FALSE
   - Total row count is preserved (no hard deletes)
"""

import json
import os
import zipfile
import tempfile
import re
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_hsqldb_script(script_content):
    """
    Parses HSQLDB script content to extract table definitions and data.
    Returns a dictionary with schema info and data.
    """
    tables = {}
    views = {}
    inserts = {} # Key: TableName, Value: List of rows (as lists of values)
    
    # Regex for CREATE TABLE
    # CREATE TABLE "Track"("TrackId" INTEGER NOT NULL PRIMARY KEY, ... )
    table_re = re.compile(r'CREATE TABLE "([^"]+)"\((.*)\)')
    
    # Regex for CREATE VIEW
    view_re = re.compile(r'CREATE VIEW "([^"]+)" AS (.*)')
    
    # Regex for INSERT
    # INSERT INTO "Track" VALUES(1,'Name',...)
    # We will use a simpler line start check for speed
    
    lines = script_content.splitlines()
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Parse Tables
        t_match = table_re.match(line)
        if t_match:
            table_name = t_match.group(1)
            columns_def = t_match.group(2)
            # Naive column split (might break on complex constraints, but works for standard HSQLDB dumps)
            # A more robust way is to just look for the target column string
            tables[table_name] = columns_def
            continue
            
        # Parse Views
        v_match = view_re.match(line)
        if v_match:
            view_name = v_match.group(1)
            definition = v_match.group(2)
            views[view_name] = definition
            continue
            
        # Parse Inserts
        if line.startswith('INSERT INTO "'):
            # format: INSERT INTO "TableName" VALUES(...)
            try:
                table_part, values_part = line.split(' VALUES(', 1)
                table_name = table_part.split('"')[1]
                
                # Remove trailing ')'
                values_str = values_part[:-1]
                
                # Store raw value string for parsing later if needed
                if table_name not in inserts:
                    inserts[table_name] = []
                inserts[table_name].append(values_str)
            except Exception:
                continue

    return {"tables": tables, "views": views, "inserts": inserts}

def parse_sql_values(value_str):
    """
    Parses a SQL VALUES string '1, 'String', NULL' into a python list.
    Handles quoted strings containing commas.
    """
    values = []
    current = []
    in_quote = False
    escape = False
    
    for char in value_str:
        if escape:
            current.append(char)
            escape = False
        elif char == "'":
            in_quote = not in_quote
            current.append(char)
        elif char == ',' and not in_quote:
            values.append("".join(current).strip())
            current = []
        else:
            current.append(char)
    values.append("".join(current).strip())
    
    # Clean up types
    clean_values = []
    for v in values:
        if v.upper() == 'NULL':
            clean_values.append(None)
        elif v.upper() == 'TRUE':
            clean_values.append(True)
        elif v.upper() == 'FALSE':
            clean_values.append(False)
        elif v.startswith("'") and v.endswith("'"):
            clean_values.append(v[1:-1]) # Remove quotes
        else:
            # Try number
            try:
                if '.' in v:
                    clean_values.append(float(v))
                else:
                    clean_values.append(int(v))
            except:
                clean_values.append(v)
    return clean_values

def verify_soft_delete(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    temp_json.close()
    temp_odb.close()
    
    score = 0
    feedback = []
    passed = False
    
    try:
        # 1. Get Result JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result_meta = json.load(f)
            
        if not result_meta.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Database file chinook.odb not found."}

        # 2. Get ODB File
        copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        
        # 3. Extract and Parse
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "chinook.odb is not a valid zip archive."}
            
        with zipfile.ZipFile(temp_odb.name, 'r') as zf:
            if 'database/script' not in zf.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB: database/script missing."}
            
            script_content = zf.read('database/script').decode('utf-8', errors='ignore')
            
        db_state = parse_hsqldb_script(script_content)
        
        # --- VERIFICATION CRITERIA ---
        
        # Criterion 1: Schema Modification (20 pts)
        track_schema = db_state['tables'].get('Track', '')
        if 'IsDeleted' in track_schema or 'ISDELETED' in track_schema.upper():
            # Check type (BOOLEAN or BIT)
            if 'BOOLEAN' in track_schema.upper() or 'BIT' in track_schema.upper():
                score += 20
                feedback.append("Schema check passed: 'IsDeleted' column found.")
            else:
                score += 10
                feedback.append("Schema partial: 'IsDeleted' column found but type might be incorrect.")
        else:
            feedback.append("Schema check failed: 'IsDeleted' column missing from Track table.")
            
        # Criterion 2: View Creation (20 pts)
        view_def = db_state['views'].get('ActiveTracks', '')
        if not view_def:
             # Try case insensitive
             for v in db_state['views']:
                 if v.upper() == 'ACTIVETRACKS':
                     view_def = db_state['views'][v]
                     break
        
        if view_def:
            if 'IsDeleted' in view_def and ('FALSE' in view_def.upper() or '0' in view_def):
                score += 20
                feedback.append("View check passed: 'ActiveTracks' view filters by IsDeleted.")
            else:
                score += 10
                feedback.append("View check partial: 'ActiveTracks' exists but filter logic seems missing.")
        else:
            feedback.append("View check failed: 'ActiveTracks' view not found.")

        # --- DATA VERIFICATION ---
        
        # Find Metal Genre ID
        metal_id = None
        genre_rows = db_state['inserts'].get('Genre', [])
        for row_str in genre_rows:
            vals = parse_sql_values(row_str)
            # Format: GenreId, Name
            if len(vals) >= 2 and vals[1] == 'Metal':
                metal_id = vals[0]
                break
        
        if metal_id is None:
            feedback.append("Error: Could not find 'Metal' genre in database to verify logic.")
        else:
            # Parse Track Data
            track_rows = db_state['inserts'].get('Track', [])
            
            # Identify column indices from CREATE statement or assume standard Chinook order
            # Standard Chinook Track: TrackId, Name, AlbumId, MediaTypeId, GenreId, Composer, Milliseconds, Bytes, UnitPrice
            # New schema should have IsDeleted at the end.
            
            # Simple heuristic: GenreId is usually index 4 (0-based) in standard schema
            # IsDeleted should be the last one.
            
            total_tracks = len(track_rows)
            correct_metal = 0
            correct_non_metal = 0
            total_metal = 0
            total_non_metal = 0
            
            for row_str in track_rows:
                vals = parse_sql_values(row_str)
                
                # Check if we have the extra column
                # Standard columns = 9. Expecting 10.
                if len(vals) < 10:
                    continue
                
                # GenreId is typically at index 4
                gid = vals[4]
                
                # IsDeleted is typically at index -1
                is_deleted = vals[-1]
                
                # Convert HSQLDB boolean repr to python bool
                if is_deleted is True or str(is_deleted).upper() == 'TRUE' or str(is_deleted) == '1':
                    is_deleted_bool = True
                else:
                    is_deleted_bool = False
                
                if gid == metal_id:
                    total_metal += 1
                    if is_deleted_bool:
                        correct_metal += 1
                else:
                    total_non_metal += 1
                    if not is_deleted_bool:
                        correct_non_metal += 1
            
            # Criterion 3: Targeted Update (30 pts)
            if total_metal > 0 and correct_metal == total_metal:
                score += 30
                feedback.append(f"Targeted update passed: All {total_metal} Metal tracks marked deleted.")
            elif total_metal > 0 and correct_metal > 0:
                score += 15
                feedback.append(f"Targeted update partial: {correct_metal}/{total_metal} Metal tracks marked deleted.")
            else:
                feedback.append("Targeted update failed: No Metal tracks marked deleted.")
                
            # Criterion 4: Data Initialization (20 pts)
            if total_non_metal > 0 and correct_non_metal == total_non_metal:
                score += 20
                feedback.append(f"Initialization passed: All {total_non_metal} non-Metal tracks active.")
            elif total_non_metal > 0:
                # Allow small tolerance? No, initialization should be global.
                score += 0
                feedback.append(f"Initialization failed: Only {correct_non_metal}/{total_non_metal} non-Metal tracks active.")
                
            # Criterion 5: Data Preservation (10 pts)
            # Original Chinook has 3503 tracks
            if total_tracks == 3503:
                score += 10
                feedback.append("Data preservation passed: Row count preserved (3503).")
            else:
                feedback.append(f"Data preservation warning: Row count changed ({total_tracks} vs 3503).")

        passed = (score >= 70)

    except Exception as e:
        score = 0
        passed = False
        feedback.append(f"Verification error: {str(e)}")
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.remove(temp_json.name)
        if os.path.exists(temp_odb.name):
            os.remove(temp_odb.name)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }