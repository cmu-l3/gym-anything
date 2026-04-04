#!/usr/bin/env python3
"""Verifier for organize_invoices_custom_folder task."""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_invoices(traj, env_info, task_info):
    """
    Verify that the 'Invoices' folder was created and the conversation was moved into it.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_folder_name = metadata.get('folder_name', 'Invoices')
    
    # Load result
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
    
    # Data extraction
    folder_found = result.get('folder_found', False)
    folder_id = result.get('folder_id', '')
    folder_created_at_str = result.get('folder_created_at', '')
    
    conversation_found = result.get('conversation_found', False)
    current_folder_id = result.get('current_folder_id', '')
    task_start_ts = result.get('task_start_timestamp', 0)

    # Criterion 1: Folder 'Invoices' created (40 points)
    if folder_found and folder_id:
        score += 40
        feedback_parts.append(f"Folder '{expected_folder_name}' exists")
    else:
        feedback_parts.append(f"Folder '{expected_folder_name}' NOT found")

    # Criterion 2: Folder created AFTER task start (10 points) - Anti-gaming
    # Parse DB timestamp (usually YYYY-MM-DD HH:MM:SS)
    folder_fresh = False
    if folder_found and folder_created_at_str:
        try:
            # Assuming DB time is roughly synced or we check relative to start
            # FreeScout DB usually UTC. `date +%s` is UTC.
            # Handle potential format variations
            if '.' in folder_created_at_str:
                fmt = '%Y-%m-%d %H:%M:%S.%f'
            else:
                fmt = '%Y-%m-%d %H:%M:%S'
            
            created_dt = datetime.strptime(folder_created_at_str, fmt)
            created_ts = created_dt.timestamp()
            
            # Allow small clock skew (e.g., 60s buffer if needed, but usually strict > is fine)
            if created_ts >= task_start_ts:
                score += 10
                folder_fresh = True
                feedback_parts.append("Folder created during task")
            else:
                feedback_parts.append("Folder creation timestamp predates task start (pre-existing?)")
        except Exception as e:
            logger.warning(f"Timestamp parse error: {e}")
            feedback_parts.append("Could not verify folder creation time")
    elif folder_found:
        feedback_parts.append("No creation timestamp available")

    # Criterion 3: Conversation moved to new folder (50 points)
    moved_correctly = False
    if conversation_found:
        if str(current_folder_id) == str(folder_id) and folder_id != '':
            score += 50
            moved_correctly = True
            feedback_parts.append("Conversation moved to 'Invoices' folder")
        else:
            feedback_parts.append(f"Conversation not in 'Invoices' folder (Current Folder ID: {current_folder_id}, Expected: {folder_id})")
    else:
        feedback_parts.append("Target conversation not found in database")

    # Pass logic: Must have created folder AND moved conversation
    passed = score >= 90 and folder_found and moved_correctly

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }