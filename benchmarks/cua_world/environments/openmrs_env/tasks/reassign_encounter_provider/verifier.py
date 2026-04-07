#!/usr/bin/env python3
"""
Verifier for reassign_encounter_provider task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_omrs_date(date_str):
    """Parses OpenMRS ISO8601 date string."""
    if not date_str:
        return None
    # Format: 2024-01-01T10:00:00.000+0000
    # Python < 3.7 doesn't handle timezone +0000 well with strptime %z sometimes,
    # but basic ISO parsing usually works.
    try:
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        try:
             # Try without microsec
            return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S%z")
        except:
            return None

def verify_reassign_provider(traj, env_info, task_info):
    """
    Verifies that the encounter provider was correctly reassigned.
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

    score = 0
    feedback = []
    
    # Extract data
    task_start_ts = result.get("task_start_timestamp", 0)
    expected_uuid = result.get("expected_provider_uuid")
    bad_uuid = result.get("bad_provider_uuid")
    current_providers = result.get("current_providers", [])
    timestamps = result.get("encounter_timestamps", {})
    
    current_uuids = [p.get('uuid') for p in current_providers]
    
    # Criterion 1: Target Encounter Modified (20 pts)
    # Check if encounter was modified after task start
    date_changed_str = timestamps.get("dateChanged")
    modified_during_task = False
    
    if date_changed_str:
        dt = parse_omrs_date(date_changed_str)
        if dt and dt.timestamp() > task_start_ts:
            modified_during_task = True
            
    if modified_during_task:
        score += 20
        feedback.append("Encounter was modified during the task.")
    else:
        feedback.append("Encounter does not appear to have been modified (dateChanged not updated).")

    # Criterion 2: Provider Updated (50 pts)
    if expected_uuid in current_uuids:
        score += 50
        feedback.append("Correct provider (Cordelia Clinician) found on encounter.")
    else:
        feedback.append("Correct provider NOT found on encounter.")

    # Criterion 3: Old Provider Removed (20 pts)
    if bad_uuid not in current_uuids:
        score += 20
        feedback.append("Incorrect provider (Super User) was removed.")
    else:
        feedback.append("Incorrect provider (Super User) is STILL assigned.")
        
    # Criterion 4: Data Integrity (10 pts)
    # Implicitly checked if only provider changed, but hard to verify fully without deep history.
    # We give points if we have exactly 1 provider and it's the correct one (clean state).
    if len(current_uuids) == 1 and expected_uuid in current_uuids:
        score += 10
        feedback.append("Encounter has exactly one provider (clean state).")
    else:
        feedback.append(f"Encounter has {len(current_uuids)} providers (expected 1).")

    # Final Check
    passed = (score >= 70) and (expected_uuid in current_uuids)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }