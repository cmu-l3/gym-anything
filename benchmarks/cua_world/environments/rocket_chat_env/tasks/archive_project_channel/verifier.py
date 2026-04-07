#!/usr/bin/env python3
"""
Verifier for archive_project_channel task.

Checks:
1. Channel 'project-alpha' must still exist (not deleted).
2. Channel must have 'archived' status set to true.
3. Channel modification timestamp should be after task start.
"""

import json
import os
import tempfile
import logging
from dateutil import parser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_project_channel(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    passed = False

    # Extract fields
    channel_found = result.get("channel_found", False)
    is_archived = result.get("is_archived", False)
    updated_at_str = result.get("channel_updated_at", "")
    task_start_ts = result.get("task_start_ts", 0)

    # CRITERION 1: Channel Integrity (20 pts)
    # The channel must NOT be deleted.
    if channel_found:
        score += 20
        feedback_parts.append("Channel 'project-alpha' was preserved (not deleted).")
    else:
        feedback_parts.append("CRITICAL: Channel 'project-alpha' was deleted or not found!")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # CRITERION 2: Archived Status (80 pts)
    if is_archived:
        score += 80
        feedback_parts.append("Channel is correctly archived.")
    else:
        feedback_parts.append("Channel is NOT archived.")
        # Check if they just made it Read Only manually (partial credit usually not given for specific 'Archive' action requests, but useful feedback)
        if result.get("is_read_only", False):
            feedback_parts.append("(Channel is Read-Only, but not using the Archive feature).")

    # Anti-gaming: Check timestamp
    # Ensure the update happened after task start
    if updated_at_str and is_archived:
        try:
            # Rocket.Chat timestamps are ISO 8601 strings
            update_ts = parser.parse(updated_at_str).timestamp()
            if update_ts < task_start_ts:
                score = 0
                feedback_parts.append("Anti-gaming: Channel state appears unchanged since before task start.")
        except Exception as e:
            logger.warning(f"Failed to parse timestamp: {e}")

    # Final decision
    if score >= 100:
        passed = True
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }