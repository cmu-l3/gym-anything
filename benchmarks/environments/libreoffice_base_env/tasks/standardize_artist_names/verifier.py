#!/usr/bin/env python3
"""
Verifier for standardize_artist_names task.

Verifies:
1. 'ArtistNameLog' table exists in the ODB file.
2. 'ArtistNameLog' contains the original "The X" names.
3. 'Artist' table no longer contains "The X" names.
4. 'Artist' table contains "X, The" names.
5. Database was saved (file modified).
"""

import json
import os
import zipfile
import re
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_standardize_artist_names(traj, env_info, task_info):
    """
    Verify the artist name standardization task by inspecting the embedded HSQLDB script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    sample_checks = metadata.get('sample_check_ids', {})

    # Setup temp files
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    local_odb_path = os.path.join(temp_dir, "chinook.odb")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Retrieve result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        # 2. Check basic file status (Anti-gaming)
        if not result.get('db_exists'):
            return {"passed": False, "score": 0, "feedback": "Database file deleted or missing."}
        
        if not result.get('db_modified'):
            feedback_parts.append("WARNING: Database file not modified (did you save?).")
            # We continue checking, but max score might be capped or fail if content isn't there
        else:
            score += 10
            feedback_parts.append("Database saved successfully.")

        # 3. Retrieve ODB file
        submitted_path = result.get('submitted_db_path')
        if not submitted_path:
            return {"passed": False, "score": score, "feedback": "No DB path in result."}
            
        try:
            copy_from_env(submitted_path, local_odb_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve ODB file: {e}"}

        # 4. Parse HSQLDB Script
        # The ODB file is a ZIP. The data is in 'database/script'.
        try:
            with zipfile.ZipFile(local_odb_path, 'r') as z:
                # Read the script file which contains the DDL and DML (INSERTs)
                script_content = z.read('database/script').decode('utf-8', errors='ignore')
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid ODB file format: {e}"}

        # --- Verification Logic ---

        # Check A: Audit Table Exists (20 pts)
        # Look for CREATE TABLE ... "ArtistNameLog"
        # Regex handles potential quoting and schema "PUBLIC"
        log_table_regex = r'CREATE\s+TABLE\s+(?:PUBLIC\.)?"ArtistNameLog"'
        if re.search(log_table_regex, script_content, re.IGNORECASE):
            score += 20
            feedback_parts.append("Audit table 'ArtistNameLog' exists.")
            audit_table_exists = True
        else:
            feedback_parts.append("Audit table 'ArtistNameLog' NOT found.")
            audit_table_exists = False

        # Parse INSERT statements to rebuild state (lightweight simulation)
        # We look for INSERT INTO ... "Artist" VALUES (...) and "ArtistNameLog"
        
        # Maps ID -> Name for Artist table
        artist_state = {} 
        # Maps ID -> OriginalName for Log table (approximate, since log might not use ID as PK, but we check content)
        log_entries = []

        # Regex to parse INSERTs: INSERT INTO "Table" VALUES(1, 'Name', ...)
        # This is a simple parser assuming standard HSQLDB export format
        for line in script_content.splitlines():
            if not line.startswith("INSERT INTO"):
                continue
            
            # Extract Table Name
            table_match = re.search(r'INSERT INTO (?:PUBLIC\.)?"?(\w+)"?\s+VALUES', line)
            if not table_match:
                continue
            table_name = table_match.group(1)
            
            # Extract Values part
            # Values are typically (1,'Name',...)
            val_part = line[line.find("VALUES")+6:].strip().strip('()')
            
            # Simple CSV splitter that respects quotes is needed strictly, 
            # but for this specific data, simple splitting might suffice if no commas in non-target fields.
            # However, artist names have commas now! "Beatles, The". So we need a smarter split.
            # We will use a basic quote-aware split.
            
            def parse_sql_values(text):
                vals = []
                current = []
                in_quote = False
                for char in text:
                    if char == "'" and (not current or current[-1] != '\\'): # Handle escape roughly
                        in_quote = not in_quote
                    elif char == ',' and not in_quote:
                        vals.append("".join(current).strip())
                        current = []
                        continue
                    current.append(char)
                vals.append("".join(current).strip())
                # Clean quotes from strings
                return [v.strip("'") for v in vals]

            values = parse_sql_values(val_part)
            
            if table_name == "Artist":
                # Artist: (ArtistId, Name)
                if len(values) >= 2:
                    a_id = values[0]
                    a_name = values[1]
                    artist_state[str(a_id)] = a_name
            
            elif table_name == "ArtistNameLog":
                # ArtistNameLog: (ArtistId, OriginalName) or similar
                # We just check existence of "The ..." strings here
                if len(values) >= 2:
                    log_entries.append(values[1]) # Assuming 2nd col is Name

        # Check B: Audit Table Content (20 pts)
        # Check if log entries contain "The Beatles", "The Who", etc.
        # We check a few known ones
        found_logs = 0
        expected_logs = 0
        for aid, info in sample_checks.items():
            expected = info['original']
            if expected in log_entries:
                found_logs += 1
            expected_logs += 1
        
        if audit_table_exists and found_logs >= 3: # Allow some misses if they missed obscure ones
            score += 20
            feedback_parts.append(f"Audit table contains {found_logs}/{expected_logs} expected entries.")
        elif audit_table_exists:
            feedback_parts.append("Audit table exists but is missing expected 'The ...' entries.")

        # Check C: Artist Table Updates (40 pts)
        # 1. No name should start with "The "
        # 2. Target IDs should be "Name, The"
        
        the_prefix_count = 0
        target_correct_count = 0
        target_total = len(sample_checks)
        
        for aid, name in artist_state.items():
            if name.startswith("The "):
                the_prefix_count += 1
        
        for aid, info in sample_checks.items():
            current_name = artist_state.get(str(aid))
            if current_name == info['expected']:
                target_correct_count += 1
        
        if the_prefix_count == 0:
            score += 10
            feedback_parts.append("All 'The' prefixes removed.")
        else:
            feedback_parts.append(f"Found {the_prefix_count} artists still starting with 'The'.")
            
        if target_correct_count == target_total:
            score += 30
            feedback_parts.append(f"All {target_total} sample artists correctly renamed.")
        elif target_correct_count > 0:
            score += int(30 * (target_correct_count / target_total))
            feedback_parts.append(f"Partially correct: {target_correct_count}/{target_total} artists renamed.")
        else:
            feedback_parts.append("No target artists were renamed correctly.")

        # Check D: Collateral Damage (10 pts)
        # Check an artist that SHOULDN'T change, e.g., "AC/DC" (ID 1) or "Iron Maiden" (ID 90)
        # Note: We rely on the artist_state dictionary populated above
        collateral_damage = False
        if artist_state.get("1") != "AC/DC":
            collateral_damage = True
        if artist_state.get("90") != "Iron Maiden":
            collateral_damage = True
            
        if not collateral_damage:
            score += 10
            feedback_parts.append("Non-target data preserved.")
        else:
            feedback_parts.append("CRITICAL: Non-target data was modified/corrupted.")

        # Final score calculation
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        import traceback
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}\n{traceback.format_exc()}"
        }
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)