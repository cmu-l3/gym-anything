#!/usr/bin/env python3
"""
Verifier for Delete Playlist Records task.
Checks if the specific records were removed from the HSQLDB script inside the ODB file.
"""

import json
import tempfile
import os
import zipfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_delete_playlist_records(traj, env_info, task_info):
    """
    Verify that records for PlaylistId=17 were deleted from the ODB file.
    
    Scoring:
    - ODB file saved/modified: 20 pts
    - PlaylistTrack records (children) deleted: 35 pts
    - Playlist record (parent) deleted: 25 pts
    - Other playlists preserved (integrity check): 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Setup temporary directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Retrieve task result JSON
        result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # 2. Check if file was saved (Criterion 1: 20 pts)
        odb_modified = result.get("odb_modified", False)
        if odb_modified:
            score += 20
            feedback_parts.append("Database file was saved")
        else:
            feedback_parts.append("Database file NOT saved (changes not persisted)")
            # If not saved, we can't verify content changes usually, but we check anyway just in case
        
        # 3. Retrieve and Analyze ODB file
        odb_local_path = os.path.join(temp_dir, "chinook.odb")
        try:
            copy_from_env("/home/ga/chinook.odb", odb_local_path)
            
            # Extract database/script from the ODB (zip) file
            if not zipfile.is_zipfile(odb_local_path):
                return {"passed": False, "score": score, "feedback": "Corrupt ODB file"}
                
            with zipfile.ZipFile(odb_local_path, 'r') as zf:
                # The HSQLDB data is stored in 'database/script'
                script_content = zf.read('database/script').decode('utf-8', errors='replace')
                
            # Parse the script to count records
            lines = script_content.splitlines()
            
            # Count PlaylistTrack records for ID 17
            # Format: INSERT INTO PUBLIC."PlaylistTrack" VALUES(17,...)
            pt_remaining = sum(1 for line in lines if 'INSERT INTO PUBLIC."PlaylistTrack" VALUES(17,' in line)
            
            # Count Playlist record for ID 17
            # Format: INSERT INTO PUBLIC."Playlist" VALUES(17,...)
            pl_remaining = sum(1 for line in lines if 'INSERT INTO PUBLIC."Playlist" VALUES(17,' in line)
            
            # Count total playlists (to ensure not everything was deleted)
            total_pl_remaining = sum(1 for line in lines if 'INSERT INTO PUBLIC."Playlist" VALUES(' in line)
            
            # Get initial counts from metadata/result
            initial_state = result.get("initial_state", {})
            initial_total_pl = initial_state.get("total_playlists", 18)
            
            # Criterion 2: PlaylistTrack records deleted (35 pts)
            if pt_remaining == 0:
                score += 35
                feedback_parts.append("All track associations deleted")
            else:
                feedback_parts.append(f"Failed to delete {pt_remaining} track associations")
                
            # Criterion 3: Playlist record deleted (25 pts)
            if pl_remaining == 0:
                score += 25
                feedback_parts.append("Playlist record deleted")
            else:
                feedback_parts.append("Playlist record still exists")
                
            # Criterion 4: Integrity check (20 pts)
            # Expected remaining playlists = Initial - 1 (if successful) or Initial (if failed)
            # We just want to ensure mass deletion didn't occur (e.g. DELETE FROM Playlist without WHERE)
            if total_pl_remaining >= (initial_total_pl - 1):
                score += 20
                feedback_parts.append("Other data preserved")
            else:
                feedback_parts.append(f"CRITICAL: Too many records deleted! (Remaining: {total_pl_remaining}, Expected: ~{initial_total_pl - 1})")
                score = 0 # Mass deletion penalty
                
        except Exception as e:
            feedback_parts.append(f"Failed to analyze ODB content: {e}")
            if odb_modified:
                # If file was modified but we can't read it, it might be corrupt
                score = 10 # minimal points for trying

    # Calculate final status
    # Pass threshold: 60 points (Needs save + both deletes, or at least perfect execution of deletes even if save timestamp is edge case)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }