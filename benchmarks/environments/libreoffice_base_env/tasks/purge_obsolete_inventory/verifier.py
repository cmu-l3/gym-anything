#!/usr/bin/env python3
"""
Verifier for purge_obsolete_inventory task.

Logic:
1. Unzip the resulting ODB file.
2. Parse the 'database/script' file (HSQLDB SQL log).
3. Verify 'UnsoldTracksArchive' table exists.
4. Verify 'UnsoldTracksArchive' contains the correct unsold tracks (from ground truth).
5. Verify 'Track' table DOES NOT contain the unsold tracks.
6. Verify 'PlaylistTrack' table DOES NOT contain references to unsold tracks.
"""

import json
import os
import zipfile
import tempfile
import re
import shutil

def verify_purge_obsolete_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp directory
    temp_dir = tempfile.mkdtemp()
    try:
        # 1. Retrieve result artifacts
        copy_from_env("/tmp/task_result.json", os.path.join(temp_dir, "result.json"))
        
        with open(os.path.join(temp_dir, "result.json"), 'r') as f:
            result = json.load(f)

        if not result.get("odb_modified"):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Database file was not modified/saved."
            }

        # Copy ODB and Ground Truth
        odb_local_path = os.path.join(temp_dir, "chinook.odb")
        gt_local_path = os.path.join(temp_dir, "ground_truth.json")
        counts_local_path = os.path.join(temp_dir, "counts.json")

        copy_from_env(result["odb_path"], odb_local_path)
        copy_from_env(result["ground_truth_path"], gt_local_path)
        copy_from_env(result["counts_path"], counts_local_path)

        with open(gt_local_path, 'r') as f:
            ground_truth_unsold = json.load(f)
        
        with open(counts_local_path, 'r') as f:
            counts = json.load(f)

        unsold_ids = set(t['TrackId'] for t in ground_truth_unsold)
        expected_unsold_count = len(unsold_ids)
        total_initial_tracks = counts['total_tracks_initial']

        # 2. Extract ODB and Read Script
        with zipfile.ZipFile(odb_local_path, 'r') as zf:
            zf.extract("database/script", temp_dir)
        
        with open(os.path.join(temp_dir, "database/script"), 'r', encoding='utf-8', errors='replace') as f:
            script_content = f.read()

        # 3. Analyze Script
        score = 0
        feedback = []

        # Check 1: Archive Table Creation (20 pts)
        # Look for CREATE TABLE "UnsoldTracksArchive" ...
        # Regex handles variable whitespace and potential schema prefixes (PUBLIC.)
        archive_table_pattern = re.compile(r'CREATE\s+TABLE\s+(?:PUBLIC\.)?"UnsoldTracksArchive"', re.IGNORECASE)
        if archive_table_pattern.search(script_content):
            score += 20
            feedback.append("Archive table 'UnsoldTracksArchive' created.")
        else:
            feedback.append("Archive table 'UnsoldTracksArchive' NOT found.")
        
        # Check 2: Archive Table Population (30 pts)
        # Parse INSERT INTO "UnsoldTracksArchive" VALUES(...)
        # We need to verify that the inserted IDs match the unsold_ids set.
        # HSQLDB INSERT format: INSERT INTO "Table" VALUES(1,'Name',...)
        
        # Regex to capture values part
        insert_archive_pattern = re.compile(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"UnsoldTracksArchive"\s+VALUES\((.+)\)', re.IGNORECASE)
        
        archived_ids = set()
        for match in insert_archive_pattern.finditer(script_content):
            val_str = match.group(1)
            # Naive parsing: assuming ID is the first value and is an integer. 
            # This works for standard HSQLDB dumps unless ID is not first column.
            # Given task "create table with columns TrackId...", TrackId is likely first.
            try:
                # Split by comma, take first element
                first_val = val_str.split(',')[0].strip()
                archived_ids.add(int(first_val))
            except:
                pass

        # Verify archived IDs match expected
        intersection = archived_ids.intersection(unsold_ids)
        if len(intersection) == expected_unsold_count:
            score += 30
            feedback.append(f"All {expected_unsold_count} unsold tracks successfully archived.")
        elif len(intersection) > 0:
            partial_score = int(30 * (len(intersection) / expected_unsold_count))
            score += partial_score
            feedback.append(f"Partially archived: {len(intersection)}/{expected_unsold_count} tracks.")
        else:
            feedback.append("No correct data found in archive table.")

        # Check 3: Dependencies Cleared (PlaylistTrack) (20 pts)
        # We check that NO INSERT statements for "PlaylistTrack" contain the unsold IDs.
        # HSQLDB schema for PlaylistTrack: (PlaylistId, TrackId)
        # We need to find the position of TrackId. Usually second.
        
        # Find column definition to be sure? Assuming standard order or just searching text.
        # Safer: Check if any INSERT INTO "PlaylistTrack" ... contains ", ID)"
        
        playlist_violations = 0
        insert_playlist_pattern = re.compile(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"PlaylistTrack"\s+VALUES\((.+)\)', re.IGNORECASE)
        for match in insert_playlist_pattern.finditer(script_content):
            val_str = match.group(1)
            # PlaylistTrack is usually (PlaylistId, TrackId).
            parts = val_str.split(',')
            if len(parts) >= 2:
                try:
                    # TrackId is likely the second one
                    t_id = int(parts[1].strip())
                    if t_id in unsold_ids:
                        playlist_violations += 1
                except:
                    pass
        
        if playlist_violations == 0:
            score += 20
            feedback.append("PlaylistTrack dependencies correctly cleared.")
        else:
            feedback.append(f"Failed: Found {playlist_violations} PlaylistTrack entries for obsolete tracks.")

        # Check 4: Inventory Purged (Track Table) (30 pts)
        # We verify that INSERT INTO "Track" statements DO NOT contain the unsold IDs.
        
        track_violations = 0
        insert_track_pattern = re.compile(r'INSERT\s+INTO\s+(?:PUBLIC\.)?"Track"\s+VALUES\((.+)\)', re.IGNORECASE)
        
        # Count total tracks remaining
        remaining_track_count = 0
        
        for match in insert_track_pattern.finditer(script_content):
            remaining_track_count += 1
            val_str = match.group(1)
            try:
                # TrackId is first column
                t_id = int(val_str.split(',')[0].strip())
                if t_id in unsold_ids:
                    track_violations += 1
            except:
                pass

        expected_remaining = total_initial_tracks - expected_unsold_count
        
        if track_violations == 0:
            # Also check we didn't delete everything
            if remaining_track_count > 0:
                if abs(remaining_track_count - expected_remaining) < 5: # Tolerance for minor issues
                    score += 30
                    feedback.append("Unsold tracks successfully removed from inventory.")
                else:
                    score += 15
                    feedback.append(f"Unsold tracks removed, but total count mismatch (Expected ~{expected_remaining}, Got {remaining_track_count}).")
            else:
                feedback.append("Track table is empty! You deleted everything.")
        else:
            feedback.append(f"Failed: Found {track_violations} obsolete tracks still in the Track table.")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)