#!/usr/bin/env python3
"""
Verifier for rename_tables_columns task in LibreOffice Base.
Verifies that specific tables and columns were renamed to snake_case using HSQLDB script parsing.
"""

import json
import os
import tempfile
import zipfile
import re
import hashlib
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_tables_columns(traj, env_info, task_info):
    """
    Verify table and column renames by parsing the ODB's embedded HSQLDB script.
    
    Criteria:
    1. ODB file modified (5 pts)
    2. Content changed (hash check) (5 pts)
    3. Tables renamed correctly (15 pts each)
    4. Columns renamed correctly (10 pts each)
    5. Data integrity (row counts) preserved (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Define expectations
    expected_renames = {
        "tables": {
            "invoice_line": "InvoiceLine",
            "playlist_track": "PlaylistTrack"
        },
        "columns": {
            "Genre": "genre_name",
            "MediaType": "type_name",
            "Artist": "artist_name",
            "Playlist": "playlist_name",
            "Album": "album_title"
        }
    }
    
    # Expected row counts (from metadata or hardcoded for standard Chinook)
    # Note: These map to the *original* table names. We check whatever name we find.
    expected_counts = {
        "InvoiceLine": 2240,
        "invoice_line": 2240,
        "PlaylistTrack": 8715,
        "playlist_track": 8715,
        "Genre": 25,
        "MediaType": 5,
        "Artist": 275,
        "Playlist": 18,
        "Album": 347
    }

    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # 2. Check ODB Modification
    if task_result.get("odb_modified", False):
        score += 5
        feedback_parts.append("Database file saved")
    else:
        feedback_parts.append("Database file NOT saved/modified")
        return {"passed": False, "score": 0, "feedback": "Task failed: Database file was not saved."}

    # 3. Retrieve and Parse ODB File
    with tempfile.NamedTemporaryFile(delete=False, suffix='.odb') as f:
        temp_odb_path = f.name

    try:
        copy_from_env("/home/ga/chinook.odb", temp_odb_path)
        
        with zipfile.ZipFile(temp_odb_path, 'r') as z:
            script_content = z.read('database/script').decode('utf-8')
            
        # Anti-gaming: Check hash against original
        current_hash = hashlib.sha256(script_content.encode('utf-8')).hexdigest()
        original_hash = task_result.get("original_script_hash", "")
        
        if current_hash == original_hash:
            feedback_parts.append("No changes detected in database structure")
            return {"passed": False, "score": 5, "feedback": "Database file saved but no changes were made."}
        else:
            score += 5
            feedback_parts.append("Database structure modified")

        # Parsing Helpers
        def get_tables(text):
            return re.findall(r'CREATE TABLE PUBLIC\."([^"]+)"', text)

        def get_columns(text, table):
            # Regex to find CREATE TABLE block and extract columns
            pattern = rf'CREATE TABLE PUBLIC\."{re.escape(table)}"\(([^)]+)\)'
            match = re.search(pattern, text)
            if not match: return []
            return re.findall(r'"([^"]+)"\s+\w+', match.group(1))

        def count_inserts(text, table):
            return len(re.findall(rf'INSERT INTO PUBLIC\."{re.escape(table)}"', text))

        current_tables = get_tables(script_content)
        
        # 4. Verify Table Renames (15 pts each)
        for new_name, old_name in expected_renames["tables"].items():
            if new_name in current_tables:
                if old_name not in current_tables:
                    score += 15
                    feedback_parts.append(f"Table '{old_name}' -> '{new_name}' ✅")
                else:
                    score += 10
                    feedback_parts.append(f"Table '{new_name}' created but '{old_name}' still exists (partial) ⚠️")
            else:
                feedback_parts.append(f"Table '{old_name}' NOT renamed to '{new_name}' ❌")

        # 5. Verify Column Renames (10 pts each)
        for table, new_col in expected_renames["columns"].items():
            # Handle if the table itself was renamed (none of these tables were targets for table renaming in this task, but good for robustness)
            # In this task, Genre, MediaType, Artist, Playlist, Album are NOT renamed.
            
            # Check if column exists in table
            cols = get_columns(script_content, table)
            
            # If table not found by that name, maybe check case variants (though strictly task said preserve)
            if not cols:
                # Try finding table if user renamed it unexpectedly? Unlikely for this task scope.
                feedback_parts.append(f"Table '{table}' not found for column check")
                continue

            if new_col in cols:
                # Check if old column is gone
                old_col_map = {"genre_name": "Name", "type_name": "Name", "artist_name": "Name", "playlist_name": "Name", "album_title": "Title"}
                old_col = old_col_map.get(new_col, "Name")
                
                if old_col not in cols:
                    score += 10
                    feedback_parts.append(f"Column '{table}.{new_col}' renamed ✅")
                else:
                    score += 5
                    feedback_parts.append(f"Column '{table}.{new_col}' created but old still exists ⚠️")
            else:
                feedback_parts.append(f"Column '{table}.{new_col}' NOT found ❌")

        # 6. Verify Data Integrity (10 pts)
        integrity_passed = True
        
        # Check integrity of renamed tables
        for new_name, old_name in expected_renames["tables"].items():
            target = new_name if new_name in current_tables else old_name
            count = count_inserts(script_content, target)
            expected = expected_counts.get(old_name, 0)
            
            if count != expected:
                integrity_passed = False
                feedback_parts.append(f"Data loss in {target}: found {count}, expected {expected}")

        # Check integrity of column-renamed tables
        for table in expected_renames["columns"].keys():
            count = count_inserts(script_content, table)
            expected = expected_counts.get(table, 0)
            if count != expected:
                integrity_passed = False
                feedback_parts.append(f"Data loss in {table}: found {count}, expected {expected}")

        if integrity_passed:
            score += 10
            feedback_parts.append("Data integrity preserved ✅")
        else:
            feedback_parts.append("Data integrity check FAILED ❌")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odb_path):
            os.unlink(temp_odb_path)

    # Final Result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }