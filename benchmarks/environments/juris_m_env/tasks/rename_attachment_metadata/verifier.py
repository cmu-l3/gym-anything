#!/usr/bin/env python3
"""
Verifier for rename_attachment_metadata task.

Verification Strategy:
1. Verify `scan_generic.pdf` no longer exists in the storage directory.
2. Verify a new PDF file exists in the same directory.
3. Verify the new filename contains "Marbury" and "1803".
4. Verify the database record (itemAttachments.path) has been updated.
5. Verify the file modification time is after task start.

Scoring:
- Old file removed: 30 pts
- New file exists: 30 pts
- Filename accuracy: 20 pts
- Database updated: 20 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_attachment(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the attachment was renamed based on metadata."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load metadata expectations
    metadata = task_info.get("metadata", {})
    expected_part_1 = metadata.get("expected_name_part_1", "Marbury")
    expected_part_2 = metadata.get("expected_name_part_2", "1803")

    # Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?"
        }

    score = 0
    feedback = []
    
    # Extract data
    old_file_exists = result.get("old_file_exists", True)
    new_file_exists = result.get("new_file_exists", False)
    new_filename = result.get("new_filename", "")
    db_path_value = result.get("db_path_value", "")
    task_start = result.get("task_start", 0)
    new_file_mtime = result.get("new_file_mtime", 0)

    # 1. Old file removed (30 pts)
    if not old_file_exists:
        score += 30
        feedback.append("Original generic filename removed (+30)")
    else:
        feedback.append("Original file 'scan_generic.pdf' still exists")

    # 2. New file exists (30 pts)
    if new_file_exists:
        score += 30
        feedback.append("New renamed file found (+30)")
        
        # 3. Filename accuracy (20 pts)
        if expected_part_1 in new_filename and expected_part_2 in new_filename:
            score += 20
            feedback.append(f"Filename '{new_filename}' contains expected metadata (+20)")
        else:
            feedback.append(f"Filename '{new_filename}' missing expected parts '{expected_part_1}' or '{expected_part_2}'")
            
        # Check timestamp (anti-gaming)
        if new_file_mtime > task_start:
            feedback.append("File modification confirmed during task")
        else:
            feedback.append("Warning: File modification time predates task start")
    else:
        feedback.append("No file matching 'Marbury' found in storage")

    # 4. Database integrity (20 pts)
    # The path in DB should look like "storage:Marbury v. Madison - 1803.pdf"
    if db_path_value and "storage:" in db_path_value and expected_part_1 in db_path_value:
        score += 20
        feedback.append("Database record updated correctly (+20)")
    elif db_path_value:
        feedback.append(f"Database record mismatch: {db_path_value}")
    else:
        feedback.append("Database record not found")

    # Determine pass/fail
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }