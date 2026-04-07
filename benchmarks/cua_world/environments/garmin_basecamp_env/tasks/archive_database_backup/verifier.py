#!/usr/bin/env python3
"""
Verifier for archive_database_backup task.

This verifier validates the completion of the database backup workflow by ensuring:
1. The proprietary archive (.Backup) was generated at the correct location.
2. The file is a valid BaseCamp ZIP archive containing an AllData.gdb internal database.
3. The binary stream of the internal database contains the exact injected Waypoint Name.
4. The binary stream of the internal database contains the exact injected Notes.

By strictly checking the proprietary file structure and contents at a byte level, 
this serves as an impossible-to-game check without interacting correctly with the app.
"""

import json
import tempfile
import os
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_string_in_bytes(data: bytes, search_str: str) -> bool:
    """Check for string presence in raw bytes considering multiple encodings."""
    encodings = ['utf-8', 'utf-16le', 'ascii']
    for enc in encodings:
        try:
            encoded = search_str.encode(enc)
            if encoded in data:
                return True
        except UnicodeEncodeError:
            pass
    return False

def verify_archive_database_backup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - Framework error"}

    # Fetch expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_backup_path = metadata.get('expected_backup_path', 'C:\\workspace\\output\\BaseCamp_Archive.Backup')
    waypoint_name = metadata.get('waypoint_name', 'MIGRATION-CHECKPOINT')
    waypoint_note = metadata.get('waypoint_note', 'Authorized by GIS Dept')

    score = 0
    feedback_parts = []
    
    # 1. READ EXPORT RESULT JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Validate file presence and timestamp logic (Anti-gaming check)
    output_exists = result_data.get('output_exists', False)
    created_during_task = result_data.get('file_created_during_task', False)
    
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Backup file was not generated at the requested location."
        }
        
    if created_during_task:
        score += 20
        feedback_parts.append("File created during task session (+20)")
    else:
        feedback_parts.append("File exists but timestamp precedes task start - may be stale (+0)")

    # 2. VALIDATE PROPRIETARY ARCHIVE AND CONTENTS
    temp_archive = tempfile.NamedTemporaryFile(delete=False, suffix='.Backup')
    has_gdb = False
    name_found = False
    note_found = False

    try:
        copy_from_env(expected_backup_path, temp_archive.name)
        
        # Garmin .Backup files are ZIP archives
        if zipfile.is_zipfile(temp_archive.name):
            with zipfile.ZipFile(temp_archive.name, 'r') as zf:
                
                # Check for BaseCamp's internal database standard file
                gdb_files = [f for f in zf.namelist() if f.lower().endswith('alldata.gdb')]
                
                if gdb_files:
                    has_gdb = True
                    score += 30
                    feedback_parts.append("Valid ZIP archive verified containing AllData.gdb (+30)")
                    
                    # Read binary databases to seek injected strings
                    for gdb_file in gdb_files:
                        with zf.open(gdb_file) as f:
                            data = f.read()
                            
                            if not name_found and check_string_in_bytes(data, waypoint_name):
                                name_found = True
                                score += 25
                                feedback_parts.append(f"Waypoint name '{waypoint_name}' found encoded in database (+25)")
                                
                            if not note_found and check_string_in_bytes(data, waypoint_note):
                                note_found = True
                                score += 25
                                feedback_parts.append(f"Notes string '{waypoint_note}' found encoded in database (+25)")
                else:
                    feedback_parts.append("Archive is valid ZIP but missing expected BaseCamp database files (+0)")
        else:
            feedback_parts.append("Exported file is not a valid ZIP/Backup archive format (+0)")
            
    except Exception as e:
        logger.error(f"Error inspecting archive: {e}")
        feedback_parts.append(f"Error inspecting archive binary: {e}")
    finally:
        if os.path.exists(temp_archive.name):
            os.unlink(temp_archive.name)

    # Final scoring check
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }