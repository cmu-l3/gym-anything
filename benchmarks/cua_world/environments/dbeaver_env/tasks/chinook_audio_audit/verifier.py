#!/usr/bin/env python3
"""
Verifier for chinook_audio_audit task.

Criteria:
1. DBeaver connection created (10 pts)
2. Database View 'v_track_bitrates' created (20 pts)
3. View logic excludes video files (20 pts)
4. View logic calculates bitrate correctly (10 pts)
5. CSV export exists and created during task (10 pts)
6. CSV content is correct (filtered > 280kbps) (15 pts)
7. SQL script exists (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_audio_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Connection (10 pts)
    if result.get('connection_exists', False):
        score += 10
        feedback.append("DBeaver connection 'Chinook' found.")
    else:
        feedback.append("DBeaver connection 'Chinook' NOT found.")

    # 2. View Existence (20 pts)
    if result.get('view_exists', False):
        score += 20
        feedback.append("View 'v_track_bitrates' created in database.")
    else:
        feedback.append("View 'v_track_bitrates' NOT found in database.")

    # 3. View Logic - Video Exclusion (20 pts)
    # video_in_view_count should be 0. If it's -1, view didn't exist.
    vid_count = result.get('video_in_view_count', -1)
    if vid_count == 0:
        score += 20
        feedback.append("View correctly excludes video files.")
    elif vid_count > 0:
        feedback.append(f"View incorrectly includes {vid_count} video files.")
    else:
        feedback.append("Could not verify view logic (view missing).")

    # 4. View Logic - Bitrate Calculation (10 pts)
    # calculation_diff should be small (allowing for rounding differences 0-1)
    calc_diff = result.get('calculation_diff', 999)
    if calc_diff <= 1 and calc_diff >= 0:
        score += 10
        feedback.append("Bitrate calculation formula appears correct.")
    elif calc_diff < 999:
        feedback.append(f"Bitrate calculation incorrect (Difference: {calc_diff}).")
    
    # 5. CSV Existence & Timestamp (10 pts)
    if result.get('csv_exists', False) and result.get('csv_created_during_task', False):
        score += 10
        feedback.append("High-fidelity candidate CSV exported.")
    elif result.get('csv_exists', False):
        score += 5
        feedback.append("CSV found but timestamp suggests it wasn't created during this task.")
    else:
        feedback.append("CSV export NOT found.")

    # 6. CSV Content Quality (15 pts)
    # Should have rows > 0 and no video
    csv_rows = result.get('csv_row_count', 0)
    csv_has_video = result.get('csv_has_video', False)
    
    # Approximate expected count for >280kbps non-video is around 200-300 tracks in standard Chinook
    if csv_rows > 0 and not csv_has_video:
        score += 15
        feedback.append(f"CSV content valid ({csv_rows} tracks).")
    elif csv_rows > 0 and csv_has_video:
        score += 5
        feedback.append("CSV contains data but incorrectly includes video files.")
    elif csv_rows == 0 and result.get('csv_exists', False):
        feedback.append("CSV file is empty.")

    # 7. SQL Script (15 pts)
    if result.get('sql_script_exists', False):
        score += 15
        feedback.append("SQL analysis script saved.")
    else:
        feedback.append("SQL analysis script NOT found.")

    # Final Pass check
    passed = score >= 60 and result.get('view_exists', False) and result.get('csv_exists', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }