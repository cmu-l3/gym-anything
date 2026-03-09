#!/usr/bin/env python3
"""
Verifier for perform_annual_db_rollover task.

Criteria:
1. Backup file exists (30 pts)
   - Must be created AFTER task start.
   - Must have significant size (proving data was there before purge).
2. Verification export exists (30 pts)
   - Must be created AFTER task start.
   - Must be "empty" (header only or 0 records).
3. Sequencing (10 pts)
   - Backup timestamp < Export timestamp (Archive BEFORE Purge).
4. VLM Verification (30 pts)
   - Trajectory shows database/log view.
   - Final state shows empty list.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_annual_db_rollover(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    feedback_parts = []
    task_start = result.get('task_start', 0)

    # --- 1. Backup Verification (30 pts) ---
    backup = result.get('backup', {})
    backup_exists = backup.get('exists', False)
    backup_mtime = backup.get('mtime', 0)
    backup_size = backup.get('size_bytes', 0)

    if backup_exists:
        if backup_mtime > task_start:
            # Check size - a valid backup of a DB should be > 1KB (usually much larger)
            # An empty text file is not a backup.
            if backup_size > 5000: # 5KB threshold
                score += 30
                feedback_parts.append("Valid backup created")
            elif backup_size > 0:
                score += 15
                feedback_parts.append("Backup created but unusually small (<5KB)")
            else:
                feedback_parts.append("Backup file is empty (0 bytes)")
        else:
            feedback_parts.append("Backup file predates task start (cheating detected)")
    else:
        feedback_parts.append("No backup file found")

    # --- 2. Purge Verification via Export (30 pts) ---
    export = result.get('export', {})
    export_exists = export.get('exists', False)
    export_mtime = export.get('mtime', 0)
    export_lines = export.get('line_count', 0)

    if export_exists:
        if export_mtime > task_start:
            # CSV with header only usually has 1 line. Empty file has 0.
            # If it has > 5 lines, they probably didn't purge.
            if export_lines <= 2:
                score += 30
                feedback_parts.append("Export confirms log is empty (purged)")
            else:
                feedback_parts.append(f"Export contains {export_lines} lines - Purge failed (records still exist)")
        else:
            feedback_parts.append("Export file predates task start")
    else:
        feedback_parts.append("No verification export found")

    # --- 3. Sequencing (10 pts) ---
    # Did they backup BEFORE export?
    if backup_exists and export_exists and backup_mtime > 0 and export_mtime > 0:
        if backup_mtime < export_mtime:
            score += 10
            feedback_parts.append("Correct sequence: Backup before Purge")
        else:
            feedback_parts.append("Incorrect sequence: Exported empty log before backup?")

    # --- 4. VLM Verification (30 pts) ---
    # We want to see evidence of the process
    frames = sample_trajectory_frames(traj, n=5)
    final_img = get_final_screenshot(traj)
    
    # Add final image to frames for analysis
    if final_img:
        frames.append(final_img)

    if not frames:
        feedback_parts.append("No screenshots available for VLM")
    else:
        prompt = """
        Analyze these screenshots of a user performing a database maintenance task in 'Jolly Lobby Track'.
        The user was supposed to:
        1. Backup the database
        2. Delete/Purge all visitor records
        3. Verify the log is empty

        Look for:
        - A 'Backup', 'Save As', or file dialog window.
        - A 'Delete', 'Purge', or 'Clear' confirmation dialog.
        - The main visitor grid showing 0 records or being empty in the final frames.
        - The Lobby Track application window.

        Return JSON:
        {
            "backup_dialog_seen": boolean,
            "delete_action_seen": boolean,
            "final_grid_empty": boolean,
            "app_visible": boolean
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            vlm_data = vlm_response.get('parsed', {})
            
            vlm_score = 0
            if vlm_data.get('app_visible'):
                vlm_score += 5
            if vlm_data.get('backup_dialog_seen'):
                vlm_score += 5
            if vlm_data.get('delete_action_seen'):
                vlm_score += 10
            if vlm_data.get('final_grid_empty'):
                vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"VLM verification score: {vlm_score}/30")
            
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback points if programmatic checks passed strongly
            if score >= 60:
                score += 15
                feedback_parts.append("VLM failed, granting fallback points based on strong programmatic evidence")

    # Final result
    passed = score >= 80
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }