#!/usr/bin/env python3
"""
Verifier for update_recurring_event_series task.

Criteria:
1. Future event location is "Strategy Room" (50 pts) - Proves series update
2. First event location is "Strategy Room" (20 pts) - Proves basic edit
3. Event is still recurring (20 pts) - Proves structure maintained
4. Events were found (10 pts) - Proves no accidental deletion
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_recurring_event_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    odoo_data = result.get("odoo_data", {})
    score = 0
    feedback = []

    # Check if events exist
    if not odoo_data.get("events_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No 'Weekly Operations Sync' events found. Did you delete them?"
        }
    
    score += 10
    feedback.append("Target events found (10/10)")

    # Check future event location (Critical for series update)
    expected_loc = "Strategy Room"
    future_loc = odoo_data.get("future_event_location")
    
    if future_loc == expected_loc:
        score += 50
        feedback.append("Future event location updated correctly (50/50)")
    else:
        feedback.append(f"Future event location is '{future_loc}', expected '{expected_loc}'. (Did you select 'All events'?)")

    # Check first event location
    first_loc = odoo_data.get("first_event_location")
    if first_loc == expected_loc:
        score += 20
        feedback.append("Current event location updated correctly (20/20)")
    else:
        feedback.append(f"Current event location is '{first_loc}', expected '{expected_loc}'")

    # Check recurrence integrity
    if odoo_data.get("is_recurring"):
        score += 20
        feedback.append("Event series structure maintained (20/20)")
    else:
        feedback.append("Event series is no longer recurring. (Did you delete and recreate as single events?)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }