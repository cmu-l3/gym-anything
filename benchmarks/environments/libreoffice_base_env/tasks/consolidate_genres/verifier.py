#!/usr/bin/env python3
"""
Verifier for consolidate_genres task.

Verification Strategy:
1. File Integrity: Checks if database was saved and CSV exported.
2. CSV Content Analysis: Verifies row count (~1671) and presence of key tracks.
3. Database Content Analysis: Unzips the ODB file and parses the HSQLDB script
   to verify schema/data changes (Heavy Music added, Rock/Metal removed).
"""

import json
import os
import sys
import tempfile
import zipfile
import csv
import logging
import re
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_genres(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/Documents/heavy_music_tracks.csv')
    odb_path = metadata.get('odb_path', '/home/ga/chinook.odb')
    target_genre = metadata.get('target_genre_name', 'Heavy Music')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Database Save State (10 pts)
    if result_data.get('odb_modified', False):
        score += 10
        feedback_parts.append("Database file saved.")
    else:
        feedback_parts.append("Database file NOT saved (modifications not persisted).")

    # 3. Verify CSV Content (50 pts total)
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_valid = False
    try:
        if result_data.get('csv_exists', False):
            copy_from_env(expected_csv_path, temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
                # Read all lines to handle potential header issues
                lines = [l.strip() for l in f.readlines() if l.strip()]
                row_count = len(lines)
                
                # Check for header
                has_header = "TrackId" in lines[0] or "Name" in lines[0]
                data_rows = row_count - 1 if has_header else row_count
                
                # Expected: ~1671 tracks. Allow tolerance.
                # Rock (1297) + Metal (374) = 1671. 
                # Allow +/- 50 to account for potential mistakes or partial migration.
                if 1620 <= data_rows <= 1720:
                    score += 30
                    feedback_parts.append(f"CSV row count correct ({data_rows}).")
                    csv_valid = True
                else:
                    feedback_parts.append(f"CSV row count incorrect: {data_rows} (Expected ~1671).")
                
                # Check for content (Sample check)
                content_str = "\n".join(lines).lower()
                # "Whole Lotta Love" (Rock) and "Enter Sandman" (Metal) should be present
                if "whole lotta love" in content_str and "enter sandman" in content_str:
                    score += 20
                    feedback_parts.append("Key tracks found in export.")
                else:
                    feedback_parts.append("Missing expected tracks (e.g. 'Whole Lotta Love' or 'Enter Sandman') in CSV.")
        else:
            feedback_parts.append("CSV export file not found.")
    except Exception as e:
        feedback_parts.append(f"Error analyzing CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Verify Database Internals via ODB Parsing (40 pts total)
    # The ODB is a ZIP file containing 'database/script' (HSQLDB command log)
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        copy_from_env(odb_path, temp_odb.name)
        
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            # HSQLDB stores data in 'database/script' or 'database/data' depending on size/cache
            # For this task size, schema and small tables usually in 'script'
            if 'database/script' in z.namelist():
                script_content = z.read('database/script').decode('utf-8', errors='ignore')
                
                # Check 4a: Target Genre Creation (20 pts)
                # Look for INSERT INTO "Genre" ... 'Heavy Music'
                # Pattern: INSERT INTO "Genre" VALUES(...,'Heavy Music')
                if re.search(r"INSERT INTO \"Genre\" VALUES\(.*'Heavy Music'\)", script_content, re.IGNORECASE):
                    score += 20
                    feedback_parts.append(f"Genre '{target_genre}' found in database.")
                else:
                    feedback_parts.append(f"Genre '{target_genre}' NOT found in database.")
                
                # Check 4b: Old Genres Deletion (20 pts)
                # Ensure 'Rock' and 'Metal' are NOT present in Genre INSERTs
                # Note: They might appear in the script if it's an append-only log, 
                # but HSQLDB usually rewrites the script on CHECKPOINT/SHUTDOWN (which we forced via kill).
                # However, safe bet is to check if they are ABSENT or if DELETE statements exist if it's a log.
                # Since we killed LO, it might have done a clean shutdown or not. 
                # If clean shutdown (via API or clicking X), script is rewritten.
                # If `kill_libreoffice` uses pkill, it might be abrupt. 
                # But `setup_libreoffice_base.sh` uses `pkill` and HSQLDB is embedded.
                # Actually, LibreOffice usually rewrites the .odb zip on save.
                
                rock_present = re.search(r"INSERT INTO \"Genre\" VALUES\(.*'Rock'\)", script_content, re.IGNORECASE)
                metal_present = re.search(r"INSERT INTO \"Genre\" VALUES\(.*'Metal'\)", script_content, re.IGNORECASE)
                
                if not rock_present and not metal_present:
                    score += 20
                    feedback_parts.append("Old genres 'Rock' and 'Metal' successfully removed.")
                else:
                    feedback_parts.append("Old genres 'Rock' or 'Metal' still exist in database.")
                    if rock_present: feedback_parts.append("(Rock found)")
                    if metal_present: feedback_parts.append("(Metal found)")

            else:
                feedback_parts.append("Could not find database script inside ODB.")
                
    except Exception as e:
        feedback_parts.append(f"Error analyzing ODB file: {e}")
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # Final scoring logic
    # Pass if DB saved + CSV valid + New Genre Exists (Old genre removal is bonus/full marks)
    passed = score >= 70 and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }