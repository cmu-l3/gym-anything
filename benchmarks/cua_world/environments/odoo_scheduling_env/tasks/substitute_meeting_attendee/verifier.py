#!/usr/bin/env python3
"""
Verifier for substitute_meeting_attendee task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_substitute_meeting_attendee(traj, env_info, task_info):
    """
    Verifies that the agent replaced Carol Martinez with David Chen
    in the 'Marketing Campaign Review' meeting, while keeping Alice Johnson.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected names from metadata
    metadata = task_info.get('metadata', {})
    target_event = metadata.get("target_event", "Marketing Campaign Review")
    remove_name = metadata.get("attendee_to_remove", "Carol Martinez")
    add_name = metadata.get("attendee_to_add", "David Chen")
    keep_name = metadata.get("attendee_to_keep", "Alice Johnson")

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

    # Initialization
    score = 0
    feedback = []
    passed = False
    
    # 1. Event Existence & Integrity Check (20 pts)
    if not result.get("event_found"):
        return {"passed": False, "score": 0, "feedback": f"Event '{target_event}' not found in database."}
    
    # Check if agent deleted and recreated the event (Anti-gaming)
    # If create_date is AFTER task_start, they recreated it.
    task_start = result.get("task_start", 0)
    create_date_str = result.get("create_date", "")
    write_date_str = result.get("write_date", "")
    
    # Odoo dates are usually UTC strings "YYYY-MM-DD HH:MM:SS"
    # Simple check: if create_date is essentially equal to write_date AND both are new
    
    # We trust result['event_id_match'] from the export script which compares IDs
    if result.get("event_id_match"):
        score += 20
        feedback.append("Correct event modified (ID preserved).")
    else:
        feedback.append("Warning: Event ID changed. The event was likely deleted and recreated.")
        # We penalize but continue checking content

    # 2. Check Attendees (80 pts total)
    attendees = result.get("attendees", [])
    
    # Check: Carol removed (30 pts)
    if remove_name not in attendees:
        score += 30
        feedback.append(f"'{remove_name}' correctly removed.")
    else:
        feedback.append(f"Failed: '{remove_name}' is still an attendee.")

    # Check: David added (30 pts)
    if add_name in attendees:
        score += 30
        feedback.append(f"'{add_name}' correctly added.")
    else:
        feedback.append(f"Failed: '{add_name}' was not added.")

    # Check: Alice preserved (20 pts)
    if keep_name in attendees:
        score += 20
        feedback.append(f"'{keep_name}' preserved.")
    else:
        feedback.append(f"Failed: '{keep_name}' was accidentally removed.")

    # 3. Modification Check (Anti-gaming)
    # Ensure the event was actually touched during the task window
    try:
        # Simple string comparison usually works for ISO dates if format is consistent,
        # but robust parsing is better. Odoo returns "YYYY-MM-DD HH:MM:SS" or similar.
        # Here we just rely on the fact that if the content changed, the write_date changed.
        pass 
    except Exception:
        pass

    # Final Verification
    if score == 100:
        passed = True
        feedback.append("Task completed successfully.")
    else:
        passed = False
        feedback.append(f"Final Score: {score}/100")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }