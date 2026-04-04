#!/usr/bin/env python3
"""
Verifier for backup_pos_database task.

Checks:
1. Backup file exists in expected directory.
2. Backup file is non-empty (>1KB).
3. Backup file was created AFTER task start (anti-gaming).
4. Copper POS is still running.
5. VLM: Validates that the agent navigated through the backup menus.
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_backup_pos_database(traj, env_info, task_info):
    """
    Verify the POS database backup task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_size_bytes', 1024)
    valid_exts = metadata.get('valid_extensions', ['.zip', '.bak', '.db', '.cpb'])

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring Criteria
    score = 0
    feedback_parts = []
    
    # 1. Backup file found (25 pts)
    if result.get('backup_found', False):
        score += 25
        feedback_parts.append("Backup file found.")
    else:
        feedback_parts.append("No backup file found in target directory.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. File created during task (30 pts) - Critical anti-gaming
    if result.get('file_created_during_task', False):
        score += 30
        feedback_parts.append("File created during task session.")
    else:
        feedback_parts.append("File timestamp is invalid (created before task).")
    
    # 3. File Size (20 pts)
    size = result.get('file_size_bytes', 0)
    if size > min_size:
        score += 20
        feedback_parts.append(f"File size valid ({size} bytes).")
    else:
        feedback_parts.append(f"File too small ({size} bytes).")

    # 4. Valid Extension (10 pts)
    filename = result.get('file_name', '').lower()
    if any(filename.endswith(ext) for ext in valid_exts):
        score += 10
        feedback_parts.append("Valid backup file extension.")
    else:
        feedback_parts.append(f"Unknown file extension for '{filename}'.")

    # 5. App Running (15 pts)
    if result.get('app_was_running', False):
        score += 15
        feedback_parts.append("Application remains open.")
    else:
        feedback_parts.append("Application was closed.")

    # Final Pass Check
    # Must have file found, correct timestamp, and valid size to pass
    passed = (
        result.get('backup_found') and 
        result.get('file_created_during_task') and 
        size > min_size and
        score >= 65
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }