#!/usr/bin/env python3
"""
Verifier for create_provider_schedule task.
Checks if the correct appointment block exists in the database.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_provider_schedule(traj, env_info, task_info):
    """
    Verifies that a provider schedule block was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    found = result.get("block_found", False)
    is_new = result.get("is_newly_created", False)
    data = result.get("block_data", {})
    
    start_dt_str = data.get("start_datetime", "")
    end_dt_str = data.get("end_datetime", "")
    provider = data.get("provider", "")
    service = data.get("service", "")
    
    # Metadata targets
    target_start_time = "09:00:00"
    target_end_time = "17:00:00"
    target_provider = "Super User"
    target_service = "General Medicine"

    feedback_parts = []
    score = 0
    
    # Criterion 1: Block Exists (30 pts)
    if found:
        score += 30
        feedback_parts.append("Block found in database")
    else:
        return {"passed": False, "score": 0, "feedback": "No appointment block found for Super User on target date"}

    # Criterion 2: Anti-gaming / Freshness (20 pts)
    if is_new:
        score += 20
        feedback_parts.append("Block created during task")
    else:
        feedback_parts.append("Block predates task start (stale data)")

    # Criterion 3: Provider & Service (20 pts)
    if provider == target_provider and service == target_service:
        score += 20
        feedback_parts.append(f"Correct provider ({provider}) and service ({service})")
    else:
        feedback_parts.append(f"Mismatch: Provider='{provider}', Service='{service}'")

    # Criterion 4: Times (30 pts)
    # Parse times to handle seconds/tolerance
    try:
        # DB format is usually "YYYY-MM-DD HH:MM:SS"
        s_time = start_dt_str.split(' ')[1] if ' ' in start_dt_str else ""
        e_time = end_dt_str.split(' ')[1] if ' ' in end_dt_str else ""
        
        # Simple string comparison is often enough if DB normalizes, but let's be safe
        if s_time.startswith("09:00") and e_time.startswith("17:00"):
            score += 30
            feedback_parts.append("Time range correct (09:00-17:00)")
        else:
            feedback_parts.append(f"Time mismatch: Found {s_time}-{e_time}")
            # Partial credit for getting close?
            if s_time.startswith("09") and e_time.startswith("17"):
                score += 15
    except Exception:
        feedback_parts.append("Error parsing time fields")

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }