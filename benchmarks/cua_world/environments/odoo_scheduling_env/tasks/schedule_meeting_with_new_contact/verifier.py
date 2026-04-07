#!/usr/bin/env python3
"""
Verifier for schedule_meeting_with_new_contact task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_meeting_with_new_contact(traj, env_info, task_info):
    """
    Verifies that the agent created a specific contact and scheduled a meeting with them.
    
    Scoring Breakdown (100 pts):
    - Contact Created Correctly (40 pts):
      - Name match (15)
      - Email match (10)
      - Phone match (5)
      - Job/Company match (10)
    - Event Created Correctly (40 pts):
      - Title match (10)
      - Location match (5)
      - Description present (5)
      - Date/Time (Friday, 2pm) (10)
      - Attendee linked (10)
    - Anti-Gaming / New Records (20 pts):
      - Contact is a new record (10)
      - Event is a new record (10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_contact = metadata.get('expected_contact', {})
    expected_event = metadata.get('expected_event', {})

    # Copy result file
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback = []

    # --- Verify Contact (40 pts) ---
    contact_found = result.get('contact_found', False)
    contact_data = result.get('contact_data', {})

    if contact_found:
        score += 15 # Name match is implied by finding it, as we searched by name
        feedback.append("Contact 'Patricia Nguyen' created.")

        # Email
        actual_email = str(contact_data.get('email', '')).strip()
        if actual_email == expected_contact.get('email'):
            score += 10
        else:
            feedback.append(f"Incorrect email: {actual_email}")

        # Phone (allow loose matching)
        actual_phone = str(contact_data.get('phone', ''))
        expected_phone_digits = "".join(filter(str.isdigit, expected_contact.get('phone', '')))
        actual_phone_digits = "".join(filter(str.isdigit, actual_phone))
        if expected_phone_digits in actual_phone_digits and len(actual_phone_digits) > 5:
            score += 5
        else:
            feedback.append(f"Incorrect phone: {actual_phone}")

        # Job / Company
        actual_job = str(contact_data.get('function', '')).lower()
        if "director" in actual_job and "operations" in actual_job:
            score += 5
        else:
            feedback.append(f"Incorrect job position: {actual_job}")
            
        actual_company = str(contact_data.get('company_name', '')).lower()
        if "westfield" in actual_company:
            score += 5
        else:
             feedback.append("Company name mismatch")

    else:
        feedback.append("Contact 'Patricia Nguyen' NOT found.")

    # --- Verify Event (40 pts) ---
    event_found = result.get('event_found', False)
    event_data = result.get('event_data', {})

    if event_found:
        score += 10 # Title match implied by search
        feedback.append("Event 'Onboarding Call' created.")

        # Location
        loc = str(event_data.get('location', '')).lower()
        if "zoom" in loc:
            score += 5
        else:
            feedback.append(f"Incorrect location: {loc}")

        # Description
        desc = str(event_data.get('description', '')).lower()
        if "onboarding" in desc or "setup" in desc:
            score += 5
        else:
            feedback.append("Description missing or incomplete")

        # Date/Time (Friday check + Hour check)
        # Weekday: 4 is Friday
        weekday = result.get('event_weekday')
        if weekday == 4:
            score += 5
        else:
            feedback.append("Event is not on a Friday")

        # Hour check (UTC vs Local is tricky, but Odoo usually stores UTC)
        # 2 PM EST/PST is evening UTC. 
        # Odoo 17 Docker often runs in UTC. 2:00 PM local usually means user input 14:00.
        # If user input 14:00 in UI, DB might store 14:00 if timezone naive, or converted.
        # We'll allow a range to be safe (13-18 UTC range covers US mornings/afternoons)
        # OR simply check if the user input something reasonable.
        # Let's rely on the hour in the export which parsed the stored string.
        # If the start hour is between 12 and 18, we accept it as reasonable 'afternoon' scheduling.
        start_hour = result.get('event_hour')
        if start_hour is not None and 13 <= start_hour <= 19:
             score += 5
        elif start_hour is not None:
             feedback.append(f"Event time seems off (Hour: {start_hour})")

        # Attendee Link
        if result.get('attendee_link_verified'):
            score += 10
            feedback.append("Patricia linked as attendee.")
        else:
            feedback.append("Patricia NOT linked as attendee.")

    else:
        feedback.append("Event 'Onboarding Call' NOT found.")

    # --- Verify Anti-Gaming (20 pts) ---
    if result.get('contact_is_new'):
        score += 10
    else:
        if contact_found: feedback.append("Contact was pre-existing (not created new).")
        
    if result.get('event_is_new'):
        score += 10
    else:
        if event_found: feedback.append("Event was pre-existing (not created new).")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }