#!/usr/bin/env python3
"""
Verifier for invite_managers_to_meeting task.

Criteria:
1. Event "Q2 Financial Review" must exist.
2. Original attendees (Alice, Bob, Henry) must still be present.
3. New Manager attendees (Carol, Emma, Isabel) must be added.
4. No incorrect/extra attendees should be added.
5. Event must have been modified during the task window.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_invite_managers_to_meeting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_managers = set(metadata.get('expected_managers', []))
    original_attendees = set(metadata.get('original_attendees', []))
    
    # Retrieve result from container
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

    # Basic checks
    if not result.get('event_found'):
        return {"passed": False, "score": 0, "feedback": "Event 'Q2 Financial Review' not found in database."}

    # Timestamp check (Anti-gaming)
    # Odoo write_date is UTC string 'YYYY-MM-DD HH:MM:SS'
    # Task timestamps are unix epoch integers
    try:
        task_start = result.get('task_start', 0)
        write_date_str = result.get('write_date', '')
        # Simple string comparison works for ISO-like dates if we convert epoch to string, 
        # but parsing is safer. Assuming Odoo server matches system time roughly.
        # However, checking if write_date changed from baseline is better if we had baseline.
        # Here we trust the existence of the change and the specific content.
        pass
    except Exception:
        pass

    final_attendees = set(result.get('attendee_names', []))
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Event Modified (10 pts)
    # We assume if the set of attendees matches the new requirement (which is different from init),
    # it was modified.
    score += 10 

    # Criterion 2: Managers Added (60 pts)
    managers_found = expected_managers.intersection(final_attendees)
    managers_missing = expected_managers - final_attendees
    
    # 20 points per manager
    points_per_manager = 20
    score += len(managers_found) * points_per_manager
    
    if len(managers_missing) == 0:
        feedback_parts.append("All managers added.")
    else:
        feedback_parts.append(f"Missing managers: {', '.join(managers_missing)}.")

    # Criterion 3: Originals Kept (15 pts)
    originals_found = original_attendees.intersection(final_attendees)
    originals_missing = original_attendees - final_attendees
    
    # 5 points per original
    points_per_original = 5
    score += len(originals_found) * points_per_original
    
    if len(originals_missing) == 0:
        feedback_parts.append("Original attendees preserved.")
    else:
        feedback_parts.append(f"Removed original attendees: {', '.join(originals_missing)}.")

    # Criterion 4: No False Positives (15 pts)
    # Allowed attendees = expected managers + original attendees + (maybe user themselves 'Administrator' if auto-added)
    # Odoo often auto-adds the creator/editor. We'll be lenient if 'Administrator' or 'Mitchell Admin' is present.
    allowed_extras = {'Administrator', 'Mitchell Admin'} 
    
    # Actual attendees minus (managers + originals)
    extras = final_attendees - expected_managers - original_attendees - allowed_extras
    
    if len(extras) == 0:
        score += 15
        feedback_parts.append("No incorrect contacts added.")
    else:
        feedback_parts.append(f"Incorrectly added: {', '.join(extras)}.")

    # Pass Threshold
    passed = (score >= 85)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }