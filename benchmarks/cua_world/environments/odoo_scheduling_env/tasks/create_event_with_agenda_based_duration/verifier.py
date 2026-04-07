#!/usr/bin/env python3
"""
Verifier for create_event_with_agenda_based_duration task.
Verifies that the agent created a meeting with the correctly calculated duration
based on provided agenda items.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_event_with_agenda_based_duration(traj, env_info, task_info):
    """
    Verify the Odoo calendar event creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_duration = metadata.get('expected_duration', 2.0)
    expected_location = metadata.get('expected_location', "Engineering Lab")
    expected_attendees = set(metadata.get('expected_attendees', ["David Chen", "Emma Thompson"]))
    required_keywords = metadata.get('required_description_keywords', [])
    expected_date_str = metadata.get('expected_date', "2026-03-13") # YYYY-MM-DD
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No event named 'System Architecture Review' was found in the calendar."
        }

    event = result.get('event', {})
    score = 0
    feedback_parts = []
    
    # 1. Check Duration (CRITICAL) - 30 points
    # The duration is the key calculation part of this task.
    # 15+40+35+30 = 120 mins = 2.0 hours
    actual_duration = event.get('duration', 0.0)
    if abs(actual_duration - expected_duration) < 0.01:
        score += 30
        feedback_parts.append(f"Correct duration ({actual_duration}h)")
    else:
        feedback_parts.append(f"Incorrect duration: expected {expected_duration}h, got {actual_duration}h")

    # 2. Check Date and Time - 20 points
    # Odoo 'start' is usually UTC string "YYYY-MM-DD HH:MM:SS"
    start_str = event.get('start', '')
    date_correct = False
    if start_str.startswith(expected_date_str):
        date_correct = True
        score += 20
        feedback_parts.append("Correct date")
    else:
        # Check if it's the right day locally if UTC shift happened
        # But for simplicity in this env, dates usually align or we check substring
        feedback_parts.append(f"Incorrect date: expected {expected_date_str}, got {start_str}")

    # 3. Check Location - 10 points
    actual_location = event.get('location', '') or ""
    if expected_location.lower() in actual_location.lower():
        score += 10
        feedback_parts.append("Correct location")
    else:
        feedback_parts.append(f"Incorrect location: expected '{expected_location}', got '{actual_location}'")

    # 4. Check Attendees - 20 points
    actual_attendees = set(result.get('attendee_names', []))
    # Note: The creator (Admin) might be auto-added, so we check if expected are subset
    missing_attendees = expected_attendees - actual_attendees
    if not missing_attendees:
        score += 20
        feedback_parts.append("All required attendees present")
    else:
        score += 10 if len(missing_attendees) < len(expected_attendees) else 0
        feedback_parts.append(f"Missing attendees: {', '.join(missing_attendees)}")

    # 5. Check Description (Agenda) - 20 points
    description = event.get('description', '') or ""
    # Odoo descriptions often contain HTML tags (e.g., <p>), so we do loose matching
    keywords_found = [kw for kw in required_keywords if kw.lower() in description.lower()]
    
    if len(keywords_found) == len(required_keywords):
        score += 20
        feedback_parts.append("Agenda items found in description")
    elif len(keywords_found) > 0:
        score += int(20 * (len(keywords_found) / len(required_keywords)))
        feedback_parts.append(f"Partial agenda found ({len(keywords_found)}/{len(required_keywords)} items)")
    else:
        feedback_parts.append("Agenda missing from description")

    # 6. Anti-gaming check
    if not result.get('created_during_task', False):
        score = 0
        feedback_parts.append("FAILED: Event timestamp indicates it was not created during the task session.")

    # Pass/Fail Logic
    # Must have correct duration and date to pass
    passed = (score >= 70) and (abs(actual_duration - expected_duration) < 0.01) and date_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }