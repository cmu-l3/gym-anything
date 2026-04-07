#!/usr/bin/env python3
"""
Verifier for remove_meeting_attendee task.

Checks:
1. "Budget Committee Meeting" event exists (15 pts)
2. James O'Brien is NOT in attendees (40 pts)
3. Grace Patel, Henry Kim, Bob Williams ARE in attendees (30 pts)
4. Event details (Location, Description) match baseline (10 pts)
5. Anti-gaming: State actually changed from baseline (5 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remove_meeting_attendee(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    odoo_state = result.get('odoo_state', {})
    if not odoo_state or odoo_state.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Odoo query failed: {odoo_state.get('error')}"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check Event Existence (15 pts)
    if odoo_state.get('event_exists'):
        score += 15
        feedback_parts.append("Event exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Event 'Budget Committee Meeting' was deleted or not found."}

    attendee_names = odoo_state.get('attendees', {}).values()
    attendee_names_list = list(attendee_names)
    
    # 2. Check James O'Brien Removed (40 pts)
    if "James O'Brien" not in attendee_names_list:
        score += 40
        feedback_parts.append("James O'Brien removed")
    else:
        feedback_parts.append("James O'Brien still present")

    # 3. Check Other Attendees Retained (30 pts - 10 each)
    required_attendees = ["Grace Patel", "Henry Kim", "Bob Williams"]
    for person in required_attendees:
        if person in attendee_names_list:
            score += 10
        else:
            feedback_parts.append(f"{person} missing")
    if all(p in attendee_names_list for p in required_attendees):
        feedback_parts.append("Key attendees retained")

    # 4. Check Details Unchanged (10 pts)
    # Note: Description check handles potential HTML wrapper or None values
    event_data = odoo_state.get('event_data', {})
    location = event_data.get('location', '')
    description = event_data.get('description', '') or ''
    
    # Simple check - strict equality might be flaky if Odoo adds <p> tags, 
    # but description shouldn't change at all in this task.
    # The setup script sets: Location='Board Room', Desc='Monthly budget review...'
    
    details_ok = True
    if location != 'Board Room':
        details_ok = False
        feedback_parts.append(f"Location changed to '{location}'")
    
    # Check for keyword in description to be lenient on HTML formatting
    if "Monthly budget review" not in description:
        details_ok = False
        feedback_parts.append("Description content altered")

    if details_ok:
        score += 10
        feedback_parts.append("Event details preserved")

    # 5. Anti-gaming (5 pts)
    # Check if the list of attendees is strictly different from baseline
    baseline = odoo_state.get('baseline', {})
    initial_ids = set(baseline.get('initial_partner_ids', []))
    current_ids = set(event_data.get('partner_ids', []))
    
    if initial_ids != current_ids and len(current_ids) < len(initial_ids):
        score += 5
    else:
        feedback_parts.append("No change detected or attendees increased")

    # Final Pass Calculation
    # Pass threshold: 55 pts (Event exists + James removed = 55)
    passed = score >= 55

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }